# JSON Auth Routing: Protocol-Agnostic RPC Boundary

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix two P1 auth bypasses in JSON protocol and make generated Rally handlers protocol-agnostic.

**Architecture:** The generated `protocol_wire` facade becomes the server-side protocol boundary. It exposes `decode_rpc_envelope`, `dispatch_rpc`, `send_rpc_result`, and `rpc_content_type` so Rally handlers never call `decode_call`, `variant_tag`, `decode_request`, or any other protocol-specific API. Handler generators produce the same auth/dispatch code regardless of protocol. JSON `json_dispatch` moves from `ws_handler` into `protocol_wire` (it was already generated per-client; now it lives where protocol knowledge belongs).

**Tech Stack:** Gleam, Libero wire modules, Rally codegen generators

---

## Current State

### The two P1 bugs

**HTTP JSON auth bypass:** `http_handler.gleam:320` returns `200 "Not implemented"` after
decoding a JSON request. Auth lookup, authorize, and dispatch never run.

**WS JSON auth bypass:** `ws_handler.gleam:451` calls `json_dispatch` directly after
decoding the JSON envelope. It does not call `handler_page_info`, does not check
`is_authenticated` per-page, does not call `authorize`, and does not check page
mismatch. The ETF path at `ws_handler.gleam:557` does all of that.

### Protocol leakage in generated handlers

Generated handlers currently branch on protocol:

- HTTP handler calls `wire.decode_call(body)` (ETF) then falls back to
  `wire.decode_request(text_body)` (JSON). No `protocol` parameter exists.
- WS handler generates different frame handling code for ETF (`mist.Binary`) vs
  JSON (`mist.Text`), with ETF getting full auth and JSON getting none.
- `handler_page_info` maps ETF-only identity strings (atom names, wire hashes).
  JSON identity strings (`module_path.TypeName`) have no entries.

### The generated protocol_wire facade

Already protocol-specific (ETF delegates to `libero/wire`, JSON delegates to
`libero/json/wire`). Already generated per-client. Already wraps
`decode_request`, `encode_response`, etc. The right place to absorb the
remaining protocol knowledge.

ETF facade: `src/rally/generator.gleam:952`
JSON facade: `src/rally/generator.gleam:983`

## Design

### Protocol-neutral types in protocol_wire

```gleam
pub opaque type RpcEnvelope {
  RpcEnvelope(request_id: Int, identity: String, ...)
  // ETF: also carries raw BitArray for dispatch
  // JSON: also carries Dynamic message for dispatch
}

pub fn rpc_request_id(envelope: RpcEnvelope) -> Int
pub fn rpc_identity(envelope: RpcEnvelope) -> String

pub opaque type RpcResult {
  RpcResult(...)
  // ETF: BitArray response frame
  // JSON: String response frame
}
```

### Unified server API in protocol_wire

```gleam
// Decode an inbound RPC from HTTP body (BitArray)
pub fn decode_rpc_envelope(data: BitArray) -> Result(RpcEnvelope, Nil)

// Decode an inbound RPC from WS text frame (String) — JSON only.
// ETF version returns Error(Nil).
pub fn decode_rpc_envelope_text(data: String) -> Result(RpcEnvelope, Nil)

// Dispatch after auth checks pass. Calls the handler, encodes the response.
pub fn dispatch_rpc(
  envelope: RpcEnvelope,
  server_context: ServerContext,
  identity: auth.Identity,  // only when auth is configured
) -> #(RpcResult, ServerContext)

// Send an RPC result over WebSocket (binary or text frame as appropriate)
pub fn send_rpc_result(
  conn: WebsocketConnection,
  result: RpcResult,
) -> Result(Nil, glisten.SocketReason)

// Build an RPC response body for HTTP
pub fn rpc_result_body(result: RpcResult) -> bytes_tree.BytesTree

// Content-Type header for HTTP RPC responses
pub fn rpc_content_type() -> String

// Build an auth error response (auth:redirect, auth:forbidden, etc.)
pub fn auth_error_result(request_id: Int, message: String) -> RpcResult

// Build a decode/protocol error response
pub fn error_result(request_id: Int, message: String) -> RpcResult
```

### Identity in handler_page_info

`endpoint_wire_tags` gains a `protocol` parameter. For ETF, it returns
`["server_fn_name", "<wire_hash>"]` (unchanged). For JSON, it returns
`["module_path.TypeName"]` (the same string `json_dispatch` matches on).

Both formats resolve to the same `PageAuthInfo(page, required, has_authorize)`
through the same generated `handler_page_info` function.

### What moves where

| Current location | Destination | Why |
|---|---|---|
| `ws_handler` `json_dispatch` function | `protocol_wire` JSON facade | Protocol dispatch belongs in the protocol layer |
| `ws_handler` JSON text branch auth bypass | Shared auth flow using `decode_rpc_envelope_text` | Bug fix |
| `http_handler` "Not implemented" stub | Shared auth flow using `decode_rpc_envelope` | Bug fix |
| `http_handler` ETF-specific `decode_call` + `variant_tag` | `wire.decode_rpc_envelope` | Protocol agnosticism |
| `ws_handler` ETF-specific `decode_call` + `variant_tag` | `wire.decode_rpc_envelope` | Protocol agnosticism |

### What stays put

- Page-init frame handling stays in WS handler (not RPC dispatch)
- `handler_page_info` stays generated in each handler (HTTP/WS have different
  endpoint sets in multi-namespace setups)
- `check_page_authorize` stays in each handler
- Server message logging stays in the handler (can log timing, identity, page
  around the dispatch call without the facade knowing about the system DB)
- Push frame handling stays in WS handler

## Non-Goals

- Do not change Libero's `rpc_dispatch` codegen (ETF dispatch stays in Erlang)
- Do not change Libero's JSON wire module
- Do not change client-side transport or protocol detection
- Do not add protocol auto-detection at the server (each client is one protocol)
- Do not change the SSR handler
- Do not change page-init frame handling (JSON page-init frames are a
  separate concern from RPC auth routing; address if needed after this plan)

## Implementation Plan

### Task 0: Baseline

**Files:**
- Read: `src/rally/generator.gleam` (protocol_wire generation)
- Read: `src/rally/generator/http_handler.gleam`
- Read: `src/rally/generator/ws_handler.gleam`

- [ ] **Step 1: Run all tests**

```sh
cd /Users/daverapin/projects/opensource/libero && gleam test
cd /Users/daverapin/projects/opensource/rally && gleam test
cd /Users/daverapin/projects/opensource/rally && test/js/run_auth_error_test.sh
cd /Users/daverapin/projects/opensource/rally && bin/check-auth-codegen
```

Note any failures before editing. Do not explain them away.

- [ ] **Step 2: Confirm the two bugs in code**

Verify that `http_handler.gleam:320` returns `"Not implemented"`.
Verify that `ws_handler.gleam:451` calls `json_dispatch` without
`handler_page_info`.

Commit: none.

### Task 1: Add `protocol` to HTTP handler generator

**Files:**
- Modify: `src/rally/generator/http_handler.gleam`
- Modify: `src/rally.gleam` (call site)
- Test: `test/rally/http_auth_test.gleam`

The HTTP handler generator currently has no `protocol` parameter. Add it so
downstream tasks can generate protocol-appropriate code.

- [ ] **Step 1: Add `protocol` parameter to `generate`**

```gleam
pub fn generate(
  endpoints: List(HandlerEndpoint),
  rpc_dispatch_module: String,
  auth_config: Option(AuthConfig),
  contracts: List(#(ScannedRoute, PageContract)),
  from_session_module from_session_module: String,
  wire_import_module wire_import_module: String,
  protocol protocol: String,
) -> String {
```

Pass it through to `generate_with_auth` (add the parameter there too).
`generate_no_auth` also needs it (for the same reason: the no-auth handler
currently hardcodes ETF decoding).

- [ ] **Step 2: Update the call site in `rally.gleam`**

Find `http_handler.generate(` (around line 950) and add `protocol:
config.protocol`.

- [ ] **Step 3: Update all test call sites**

Every `http_handler.generate(...)` call in `test/rally/http_auth_test.gleam`
currently passes 6 arguments. Add `protocol: "etf"` to each so they compile
and continue testing ETF behavior.

- [ ] **Step 4: Run tests**

```sh
cd /Users/daverapin/projects/opensource/rally && gleam test
```

Expected: all pass, no behavior change.

- [ ] **Step 5: Commit**

```sh
git add src/rally/generator/http_handler.gleam src/rally.gleam test/rally/http_auth_test.gleam
git commit -m "Add protocol parameter to HTTP handler generator"
```

### Task 2: Add `endpoint_json_tag` and make `endpoint_wire_tags` protocol-aware

**Files:**
- Modify: `src/rally/generator/http_handler.gleam`
- Modify: `src/rally/generator/ws_handler.gleam`
- Test: `test/rally/http_auth_test.gleam`
- Test: `test/rally/ws_auth_test.gleam`

Both generators have their own `endpoint_wire_tags` function. Both currently
return ETF-only tags. Add the JSON type string tag and make the function
protocol-aware.

The JSON type string for an endpoint is `module_path.TypeName` where:
- If `msg_type` is `Some(#(module, name))`: `module <> "." <> name`
- If `msg_type` is `None`: `module_path <> "." <> to_pascal_case("server_" <> fn_name)`

This is the same string used in `json_dispatch_arm` at `ws_handler.gleam:863`.

- [ ] **Step 1: Add `endpoint_json_tag` to `http_handler.gleam`**

```gleam
fn endpoint_json_tag(endpoint: HandlerEndpoint) -> String {
  case endpoint.msg_type {
    Some(#(module_path, type_name)) -> module_path <> "." <> type_name
    None ->
      endpoint.module_path <> "." <> to_pascal_case("server_" <> endpoint.fn_name)
  }
}

fn to_pascal_case(name: String) -> String {
  name
  |> string.split("_")
  |> list.map(fn(word) {
    case string.pop_grapheme(word) {
      Ok(#(first, rest)) -> string.uppercase(first) <> rest
      Error(Nil) -> word
    }
  })
  |> string.join("")
}
```

- [ ] **Step 2: Make `endpoint_wire_tags` protocol-aware in `http_handler.gleam`**

Change the existing `endpoint_wire_tags` to accept `protocol`:

```gleam
fn endpoint_wire_tags(endpoint: HandlerEndpoint, protocol: String) -> List(String) {
  case protocol {
    "json" -> [endpoint_json_tag(endpoint)]
    _ -> {
      let function_tag = "server_" <> endpoint.fn_name
      let hash_tags = case endpoint.msg_type {
        Some(#(module_path, type_name)) -> {
          let fields = list.map(endpoint.params, fn(param) { param.1 })
          let #(_, hash) = wire_identity.wire_identity(module_path, type_name, fields)
          [hash]
        }
        None -> []
      }
      list.append([function_tag], hash_tags)
    }
  }
}
```

Update `build_page_auth_map` to pass `protocol` through to `endpoint_wire_tags`.

- [ ] **Step 3: Do the same in `ws_handler.gleam`**

The WS handler has its own `endpoint_wire_tags` (around line 799). Apply the
same change: add `protocol` parameter, add JSON case, add
`endpoint_json_tag` and `to_pascal_case` (the WS handler already has
`to_pascal_case` at line 995). Update callers.

- [ ] **Step 4: Add test for JSON identity in handler_page_info**

In `test/rally/http_auth_test.gleam`:

```gleam
pub fn http_auth_json_handler_page_info_uses_type_string_test() {
  let endpoints = [
    make_endpoint("admin/pages/dashboard", "load_data"),
  ]
  let contracts = [
    #(
      make_route_named("AdminDashboard", "admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "json",
    )

  // JSON handler_page_info should map the type string, not the atom name
  let assert True =
    string.contains(output, "\"admin/pages/dashboard.ServerLoadData\"")
  // Should NOT contain ETF-style atom tags
  let assert False = string.contains(output, "\"server_load_data\"")
}
```

Add a similar test in `test/rally/ws_auth_test.gleam`.

- [ ] **Step 5: Run tests**

```sh
cd /Users/daverapin/projects/opensource/rally && gleam test
```

- [ ] **Step 6: Commit**

```sh
git add src/rally/generator/http_handler.gleam src/rally/generator/ws_handler.gleam test/rally/http_auth_test.gleam test/rally/ws_auth_test.gleam
git commit -m "Make handler_page_info protocol-aware with JSON type strings"
```

### Task 3: Add protocol-neutral decode to protocol_wire facade

**Files:**
- Modify: `src/rally/generator.gleam` (etf and json protocol_wire generation)
- Test: verify via `bin/check-auth-codegen` (generated code compiles)

Add `RpcEnvelope`, `decode_rpc_envelope`, `decode_rpc_envelope_text`,
`rpc_request_id`, and `rpc_identity` to both facade versions.

- [ ] **Step 1: Add to ETF facade (`etf_protocol_wire_source`)**

Add these to the generated source:

```gleam
pub opaque type RpcEnvelope {
  RpcEnvelope(request_id: Int, identity: String, raw: BitArray)
}

pub fn rpc_request_id(envelope: RpcEnvelope) -> Int { envelope.request_id }
pub fn rpc_identity(envelope: RpcEnvelope) -> String { envelope.identity }

pub fn decode_rpc_envelope(data: BitArray) -> Result(RpcEnvelope, Nil) {
  case libero_wire.decode_call(data) {
    Ok(#(_module, request_id, raw)) ->
      case libero_wire.variant_tag(raw) {
        Ok(tag) -> Ok(RpcEnvelope(request_id:, identity: tag, raw: data))
        Error(Nil) -> Error(Nil)
      }
    Error(_) -> Error(Nil)
  }
}

pub fn decode_rpc_envelope_text(_data: String) -> Result(RpcEnvelope, Nil) {
  Error(Nil)
}
```

Note: `raw: data` stores the original body for dispatch (ETF's
`rpc_dispatch.handle` re-decodes from the raw body).

- [ ] **Step 2: Add to JSON facade (`json_protocol_wire_source`)**

```gleam
import gleam/bit_array
import gleam/dynamic/decode as gleam_decode

pub opaque type RpcEnvelope {
  RpcEnvelope(request_id: Int, identity: String, message: Dynamic)
}

pub fn rpc_request_id(envelope: RpcEnvelope) -> Int { envelope.request_id }
pub fn rpc_identity(envelope: RpcEnvelope) -> String { envelope.identity }

pub fn decode_rpc_envelope(data: BitArray) -> Result(RpcEnvelope, Nil) {
  case bit_array.to_string(data) {
    Error(_) -> Error(Nil)
    Ok(text) -> decode_rpc_envelope_text(text)
  }
}

pub fn decode_rpc_envelope_text(data: String) -> Result(RpcEnvelope, Nil) {
  case json_wire.decode_request(data, contract_hash) {
    Error(_) -> Error(Nil)
    Ok(envelope) ->
      case extract_message_type(envelope.message) {
        Error(_) -> Error(Nil)
        Ok(type_str) ->
          Ok(RpcEnvelope(
            request_id: envelope.request_id,
            identity: type_str,
            message: envelope.message,
          ))
      }
  }
}

fn extract_message_type(message: Dynamic) -> Result(String, Nil) {
  case gleam_decode.run(message, gleam_decode.field("type", gleam_decode.string, fn(x) { gleam_decode.success(x) })) {
    Ok(type_str) -> Ok(type_str)
    Error(_) -> Error(Nil)
  }
}
```

- [ ] **Step 3: Run auth codegen check**

```sh
cd /Users/daverapin/projects/opensource/rally && bin/check-auth-codegen
```

Expected: generated code compiles.

- [ ] **Step 4: Run tests**

```sh
cd /Users/daverapin/projects/opensource/rally && gleam test
```

- [ ] **Step 5: Commit**

```sh
git add src/rally/generator.gleam
git commit -m "Add protocol-neutral decode_rpc_envelope to protocol_wire facade"
```

### Task 4: Add dispatch and response to protocol_wire facade

**Files:**
- Modify: `src/rally/generator.gleam`
- Modify: `src/rally/generator/ws_handler.gleam` (move `json_dispatch` helpers)

This task adds `dispatch_rpc`, `send_rpc_result`, `rpc_result_body`,
`rpc_content_type`, `auth_error_result`, and `error_result` to both facade
versions.

The JSON facade needs the `json_dispatch` function (currently generated
inline in ws_handler). Move the generation logic so the facade generator can
produce it. The generator helper functions (`json_dispatch_arm`,
`json_handler_call`, `json_response_encode`, `json_encoder_for_fieldtype`,
`closure_param_for_fieldtype`) stay in ws_handler.gleam as shared helper
functions called by both ws_handler and generator.gleam.

The `generate_protocol_wire` signature grows:

```gleam
pub fn generate_protocol_wire(
  protocol: String,
  atoms_module: String,
  contract_hash: String,
  endpoints: List(HandlerEndpoint),
  has_auth: Bool,
) -> String
```

Update the call site in `rally.gleam` (`do_write_files` or the inline call).

- [ ] **Step 1: Add RpcResult and dispatch/response to ETF facade**

```gleam
pub opaque type RpcResult {
  RpcResult(data: BitArray)
}

pub fn dispatch_rpc(
  envelope: RpcEnvelope,
  server_context: ServerContext,
) -> #(RpcResult, ServerContext) {
  let #(response_data, new_ctx) = rpc_dispatch.handle(server_context:, data: envelope.raw)
  #(RpcResult(data: response_data), new_ctx)
}
// Auth variant (only generated when auth is configured):
pub fn dispatch_rpc(
  envelope: RpcEnvelope,
  server_context: ServerContext,
  identity: auth.Identity,
) -> #(RpcResult, ServerContext) {
  let #(response_data, new_ctx) = rpc_dispatch.handle(server_context:, data: envelope.raw, identity:)
  #(RpcResult(data: response_data), new_ctx)
}

pub fn send_rpc_result(conn: WebsocketConnection, result: RpcResult) -> Result(Nil, glisten.SocketReason) {
  mist.send_binary_frame(conn, result.data)
}

pub fn rpc_result_body(result: RpcResult) -> bytes_tree.BytesTree {
  bytes_tree.from_bit_array(result.data)
}

pub fn rpc_content_type() -> String { "application/octet-stream" }

pub fn auth_error_result(request_id: Int, message: String) -> RpcResult {
  RpcResult(data: libero_wire.encode_response(request_id:, value: Error(message)))
}

pub fn error_result(request_id: Int, message: String) -> RpcResult {
  RpcResult(data: libero_wire.encode_response(request_id:, value: Error(message)))
}
```

Note: `dispatch_rpc` has a different signature depending on whether auth is
configured. Gleam does not support overloading, so the generator produces
exactly one version: with `identity` when auth is configured, without when
not. Use the same conditional generation pattern that `json_dispatch` uses.
The no-auth and auth facades are separate generated source strings.

- [ ] **Step 2: Add RpcResult and dispatch/response to JSON facade**

The JSON facade needs the `json_dispatch` function body moved into it. This
means:

- The facade imports handler modules (generated per-endpoint)
- The facade imports `json_codecs`
- The facade contains the per-endpoint dispatch arms

Generate the `json_dispatch` function inside the facade using the same
`json_dispatch_arm` helper that ws_handler uses. Since these helpers
(`json_dispatch_arm`, `json_handler_call`, `json_response_encode`,
`json_encoder_for_fieldtype`, `closure_param_for_fieldtype`) are pure
string-building functions, extract them into a shared location or have
`generator.gleam` import them from `ws_handler.gleam`.

```gleam
pub opaque type RpcResult {
  RpcResult(text: String)
}

// json_dispatch is generated per-app, same arms as current ws_handler version
fn json_dispatch(
  message message: Dynamic,
  request_id request_id: Int,
  server_context server_context: ServerContext,
  identity identity: auth.Identity,  // when auth configured
) -> #(RpcResult, ServerContext) {
  // ... generated dispatch arms matching on "type" field ...
}

pub fn dispatch_rpc(
  envelope: RpcEnvelope,
  server_context: ServerContext,
  identity: auth.Identity,
) -> #(RpcResult, ServerContext) {
  let #(frame, ctx) = json_dispatch(
    message: envelope.message,
    request_id: envelope.request_id,
    server_context:,
    identity:,
  )
  #(RpcResult(text: frame), ctx)
}

pub fn send_rpc_result(conn, result: RpcResult) {
  mist.send_text_frame(conn, result.text)
}

pub fn rpc_result_body(result: RpcResult) -> bytes_tree.BytesTree {
  bytes_tree.from_string(result.text)
}

pub fn rpc_content_type() -> String { "application/json" }

pub fn auth_error_result(request_id: Int, message: String) -> RpcResult {
  RpcResult(text: json_wire.encode_response(
    request_id:,
    value: json_codecs.json_encode_gleam_result__result(
      Error(message),
      fn(_) { json.null() },
      fn(x) { json.string(x) },
    ),
  ))
}

pub fn error_result(request_id: Int, message: String) -> RpcResult {
  RpcResult(text: json_wire.encode_error(
    request_id: option.Some(request_id),
    errors: [JsonError("rpc", message)],
  ))
}
```

- [ ] **Step 3: Update rally.gleam call site**

Pass `endpoints` and `has_auth` (derived from `auth_config`) to
`generate_protocol_wire`.

- [ ] **Step 4: Run auth codegen check and tests**

```sh
cd /Users/daverapin/projects/opensource/rally && bin/check-auth-codegen
cd /Users/daverapin/projects/opensource/rally && gleam test
```

- [ ] **Step 5: Commit**

```sh
git add src/rally/generator.gleam src/rally/generator/ws_handler.gleam src/rally.gleam
git commit -m "Add dispatch and response to protocol_wire facade"
```

### Task 5: Make HTTP handler protocol-agnostic

**Files:**
- Modify: `src/rally/generator/http_handler.gleam`
- Test: `test/rally/http_auth_test.gleam`

Replace the entire ETF-then-JSON decode path with the protocol-neutral
`wire.decode_rpc_envelope(body)`. Replace the dispatch call with
`wire.dispatch_rpc`. Delete the "Not implemented" JSON stub.

- [ ] **Step 1: Rewrite `generate_no_auth`**

The no-auth HTTP handler should decode via the facade and dispatch:

```gleam
fn generate_no_auth(
  rpc_dispatch_module: String,
  wire_import_module: String,
) -> String {
  "// Generated by Rally — do not edit.

import gleam/bytes_tree
import gleam/http/response.{type Response}
import mist.{type ResponseData}
import " <> import_as(wire_import_module, "wire") <> "
import rally_runtime/effect
import server_context.{type ServerContext}

pub fn handle(
  body body: BitArray,
  server_context server_context: ServerContext,
  session_id session_id: String,
) -> Response(ResponseData) {
  let Nil = effect.put_ws_session(session_id)
  case wire.decode_rpc_envelope(body) {
    Ok(envelope) -> {
      let #(result, _new_ctx) = wire.dispatch_rpc(envelope, server_context)
      response.new(200)
      |> response.set_header(\"content-type\", wire.rpc_content_type())
      |> response.set_body(mist.Bytes(wire.rpc_result_body(result)))
    }
    Error(Nil) ->
      response.new(400)
      |> response.set_body(mist.Bytes(bytes_tree.from_string(\"Bad request\")))
  }
}
"
  |> string.trim
}
```

Note: the no-auth handler no longer needs to import `rpc_dispatch` directly.
It dispatches through `wire.dispatch_rpc`. Remove the `rpc_dispatch_module`
parameter if no longer needed (but check other callers first).

- [ ] **Step 2: Rewrite `generate_auth_flow`**

Replace `decode_and_lookup` (which calls `wire.decode_call` + `wire.variant_tag`)
with `wire.decode_rpc_envelope`:

```
case wire.decode_rpc_envelope(body) {
  Ok(envelope) ->
    case handler_page_info(wire.rpc_identity(envelope)) {
      Error(Nil) ->
        response.new(400) |> ... "Unknown RPC"
      Ok(info) -> {
        // ... same auth checks (is_authenticated, from_session, authorize) ...
        let #(result, _new_ctx) = wire.dispatch_rpc(envelope, server_context, identity)
        response.new(200)
        |> response.set_header("content-type", wire.rpc_content_type())
        |> response.set_body(mist.Bytes(wire.rpc_result_body(result)))
      }
    }
  Error(Nil) ->
    response.new(400) |> ... "Bad request"
}
```

Delete the entire JSON fallback branch (the "Not implemented" stub and
surrounding `bit_array.to_string` / `wire.decode_request` code).

Remove `import gleam/bit_array` from the generated source since it is only
used by the deleted JSON fallback.

- [ ] **Step 3: Add JSON HTTP auth tests**

```gleam
pub fn http_auth_json_protocol_enforces_auth_test() {
  let endpoints = [
    make_endpoint("admin/pages/dashboard", "load_data"),
  ]
  let contracts = [
    #(
      make_route_named("AdminDashboard", "admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "json",
    )

  // Must use protocol-neutral decode
  let assert True = string.contains(output, "wire.decode_rpc_envelope(body)")
  // Must look up auth info by identity
  let assert True = string.contains(output, "wire.rpc_identity(envelope)")
  let assert True = string.contains(output, "handler_page_info(")
  // Must check auth
  let assert True = string.contains(output, "is_authenticated")
  // Must dispatch through facade
  let assert True = string.contains(output, "wire.dispatch_rpc(")
  // Must NOT contain "Not implemented"
  let assert False = string.contains(output, "Not implemented")
  // Must NOT call decode_call or variant_tag
  let assert False = string.contains(output, "decode_call")
  let assert False = string.contains(output, "variant_tag")
}
```

Also verify that ETF tests still pass unchanged (they now also use
`decode_rpc_envelope` instead of `decode_call` + `variant_tag`, so update
the ETF test assertions to match the new generated code).

- [ ] **Step 4: Verify "Not implemented" is gone**

```gleam
pub fn http_auth_no_not_implemented_stub_test() {
  // Generate with both protocols and verify neither contains the stub
  let endpoints = [make_endpoint("admin/pages/dashboard", "load_data")]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(has_page_auth: True, page_auth_required: True, has_authorize: False),
    ),
  ]
  let etf_output = http_handler.generate(endpoints, "generated/admin/rpc_dispatch",
    Some(AuthConfig(auth_module: "admin/auth")), contracts,
    from_session_module: "admin/client_context_server",
    wire_import_module: "generated/admin/protocol_wire", protocol: "etf")
  let json_output = http_handler.generate(endpoints, "generated/admin/rpc_dispatch",
    Some(AuthConfig(auth_module: "admin/auth")), contracts,
    from_session_module: "admin/client_context_server",
    wire_import_module: "generated/admin/protocol_wire", protocol: "json")
  let assert False = string.contains(etf_output, "Not implemented")
  let assert False = string.contains(json_output, "Not implemented")
}
```

- [ ] **Step 5: Run tests**

```sh
cd /Users/daverapin/projects/opensource/rally && gleam test
```

- [ ] **Step 6: Commit**

```sh
git add src/rally/generator/http_handler.gleam test/rally/http_auth_test.gleam
git commit -m "Make HTTP handler protocol-agnostic, fix JSON auth bypass"
```

### Task 6: Make WS handler protocol-agnostic

**Files:**
- Modify: `src/rally/generator/ws_handler.gleam`
- Test: `test/rally/ws_auth_test.gleam`

Replace the ETF-specific binary decode path and the JSON-specific text
decode path with protocol-neutral calls through the facade. Both frame types
should use the same auth + dispatch flow.

- [ ] **Step 1: Rewrite the binary frame RPC branch (auth version)**

Replace `wire.decode_call(data)` + `wire.variant_tag(raw)` +
`handler_page_info(variant)` with:

```
case wire.decode_rpc_envelope(data) {
  Ok(envelope) -> {
    case handler_page_info(wire.rpc_identity(envelope)) {
      // ... same auth checks ...
      // dispatch:
      let #(result, new_ctx) = wire.dispatch_rpc(envelope, server_context, identity)
      let _send = wire.send_rpc_result(conn, result)
      // ... logging, state update, send_pending_frames ...
    }
  }
  Error(Nil) -> // bad request
}
```

- [ ] **Step 2: Rewrite the text frame RPC branch (auth version)**

The JSON text branch currently bypasses auth. Replace with the same
structure as the binary branch, using `decode_rpc_envelope_text`:

```
case wire.decode_rpc_envelope_text(data) {
  Ok(envelope) -> {
    case handler_page_info(wire.rpc_identity(envelope)) {
      // ... identical auth checks as binary branch ...
      let #(result, new_ctx) = wire.dispatch_rpc(envelope, server_context, identity)
      let _send = wire.send_rpc_result(conn, result)
      // ...
    }
  }
  Error(Nil) -> // error handling
}
```

The auth flow in both branches is now structurally identical. Consider
extracting the shared body into a generated helper function to keep the
handler DRY. If the generator produces an `fn handle_rpc_envelope(envelope,
conn, state)` that both frame branches call, there is zero duplication.

- [ ] **Step 3: Rewrite the no-auth binary and text branches**

Same pattern: replace `rpc_dispatch.handle` with `wire.dispatch_rpc` and
`json_dispatch` with `wire.dispatch_rpc`. Both go through the facade.

- [ ] **Step 4: Remove `generate_json_dispatch_function` from ws_handler**

This function is now generated inside the protocol_wire facade. Remove it
from ws_handler, along with `json_dispatch_arm` if it was not extracted as
a shared helper. If it was extracted to a shared module, keep it there.

- [ ] **Step 5: Add JSON WS auth test**

```gleam
pub fn ws_auth_json_protocol_enforces_auth_test() {
  let endpoints = [make_endpoint("admin/pages/dashboard", "load_data")]
  let contracts = [
    #(
      make_route_named("AdminDashboard", "admin/pages/dashboard"),
      make_contract(has_page_auth: True, page_auth_required: True, has_authorize: False),
    ),
  ]
  let output =
    ws_handler.generate(
      contracts,
      "generated/admin/atoms",
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
      endpoints: endpoints,
      wire_import_module: "generated/admin/protocol_wire",
      protocol: "json",
    )

  // Text frame must use protocol-neutral decode
  let assert True = string.contains(output, "wire.decode_rpc_envelope_text(data)")
  // Must look up auth info
  let assert True = string.contains(output, "handler_page_info(wire.rpc_identity(")
  // Must check is_authenticated
  let assert True = string.contains(output, "is_authenticated")
  // Must dispatch through facade
  let assert True = string.contains(output, "wire.dispatch_rpc(")
  // Must NOT contain inline json_dispatch call
  let assert False = string.contains(output, "json_dispatch(")
  // Must NOT call variant_tag
  let assert False = string.contains(output, "variant_tag")
}
```

Add a page-mismatch test for JSON WS too:

```gleam
pub fn ws_auth_json_checks_page_mismatch_test() {
  // same setup as above
  let assert True = string.contains(output, "owning_page != current_page")
}
```

- [ ] **Step 6: Verify ETF WS tests still pass**

Run all existing WS tests:

```sh
cd /Users/daverapin/projects/opensource/rally && gleam test
```

Update ETF test assertions if the generated code shape changed (e.g.,
`decode_rpc_envelope` instead of `decode_call`).

- [ ] **Step 7: Commit**

```sh
git add src/rally/generator/ws_handler.gleam test/rally/ws_auth_test.gleam
git commit -m "Make WS handler protocol-agnostic, fix JSON auth bypass"
```

### Task 7: Final verification

**Files:** none (read-only)

- [ ] **Step 1: Run all tests**

```sh
cd /Users/daverapin/projects/opensource/libero && gleam test
cd /Users/daverapin/projects/opensource/rally && gleam test
cd /Users/daverapin/projects/opensource/rally && test/js/run_auth_error_test.sh
cd /Users/daverapin/projects/opensource/rally && bin/check-auth-codegen
```

- [ ] **Step 2: Verify acceptance criteria**

```sh
# No protocol-specific calls in generated handlers
grep -n 'decode_call\|variant_tag\|decode_request' src/rally/generator/http_handler.gleam
# Expected: 0 matches (no direct protocol calls)

grep -n 'decode_call\|variant_tag' src/rally/generator/ws_handler.gleam
# Expected: 0 matches

# No "Not implemented" anywhere
grep -rn 'Not implemented' src/rally/generator/
# Expected: 0 matches

# JSON dispatch is in protocol_wire, not ws_handler
grep -n 'json_dispatch' src/rally/generator/ws_handler.gleam
# Expected: 0 matches for function definition (may have helper references)
grep -n 'json_dispatch' src/rally/generator.gleam
# Expected: matches in the JSON facade generation
```

- [ ] **Step 3: Update llms.txt**

Add to the protocol boundary description: Rally handlers use
`wire.decode_rpc_envelope` for identity extraction and
`wire.dispatch_rpc` for dispatch, making them protocol-agnostic.
The protocol_wire facade absorbs all ETF/JSON differences.

- [ ] **Step 4: Commit**

```sh
git add llms.txt
git commit -m "Update docs: Protocol-agnostic RPC handlers"
```

## Risks

- Moving `json_dispatch` into `protocol_wire` makes the facade larger and gives
  it handler-module imports. If the facade grows unwieldy, a future pass could
  split it into `protocol_wire` (encode/decode) and `protocol_dispatch`
  (handler routing). Do not do this now.

- Server message logging (`system.log_to_server`) currently accesses
  ETF-specific values (`raw`, `data`). After this change, the handler has an
  `RpcEnvelope` (opaque) and an `RpcResult` (opaque). Add accessor functions
  to the facade (`rpc_raw_payload`, `rpc_identity`) so logging can still
  capture timing and identity. The raw decoded value for the message inspector
  may need a protocol-neutral accessor too, but that can be a follow-up if
  the current logging shape doesn't fit cleanly.

- The `auth_error_result` encoding for JSON must produce responses that the
  client-side `transport_ffi.mjs` can detect as auth errors. The ETF path
  sends `Error("auth:redirect:...")` which the JS side checks for. The JSON
  path must encode the same semantic shape. Verify with
  `test/js/run_auth_error_test.sh`.

- `bin/check-auth-codegen` compiles a full generated app. If the protocol_wire
  facade gains new imports (handler modules, mist, bytes_tree), the check app
  must have matching dependencies. Verify early with `bin/check-auth-codegen`.

## Test Plan

- All existing ETF tests pass (behavioral regression)
- `bin/check-auth-codegen` passes (generated code compiles)
- `test/js/run_auth_error_test.sh` passes (client-side auth error detection)
- New: JSON HTTP handler generates auth checks (not "Not implemented")
- New: JSON WS handler generates handler_page_info lookup
- New: JSON WS handler generates page mismatch check
- New: JSON WS handler generates is_authenticated check
- New: JSON WS handler generates authorize check
- New: JSON handler_page_info maps type strings, not ETF atom tags
- New: No generated handler calls `decode_call`, `variant_tag`, or
  `decode_request` directly
- New: Both ETF and JSON handler_page_info entries resolve to the same
  PageAuthInfo for the same endpoint
