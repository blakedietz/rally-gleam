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

// Decode an inbound RPC from a WebSocket message (Binary or Text frame).
// ETF decodes Binary frames, JSON decodes Text frames, both ignore the other.
// Handlers call this one function for any frame type.
pub fn decode_ws_rpc_envelope(msg: WebsocketMessage) -> Result(RpcEnvelope, Nil)

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

// Identity string from envelope (for handler_page_info lookup)
pub fn rpc_identity(envelope: RpcEnvelope) -> String

// Request ID from envelope (for error response framing)
pub fn rpc_request_id(envelope: RpcEnvelope) -> Int
```

The `decode_ws_rpc_envelope` function eliminates the text-vs-binary split
from the handler. The ETF facade decodes `mist.Binary(data)` and ignores
`mist.Text(_)`; the JSON facade decodes `mist.Text(data)` and ignores
`mist.Binary(_)`. The handler calls one function and gets back an envelope
or `Error(Nil)`.

Both facade versions filter out `request_id == 0` (page-init frames) by
returning `Error(Nil)`, so page-init handling falls through to its existing
protocol-specific branch. Without this guard, a no-param ETF page-init
payload could pass `variant_tag` and get rejected as `"auth:unknown_rpc"`
instead of being handled as a page-init.

### Identity in handler_page_info

`endpoint_wire_tags` gains a `protocol` parameter. For ETF, it returns
`["server_fn_name", "<wire_hash>"]` (unchanged). For JSON, it returns
`["module_path.TypeName"]` (the same string `json_dispatch` matches on).

Both formats resolve to the same `PageAuthInfo(page, required, has_authorize)`
through the same generated `handler_page_info` function.

### What moves where

| Current location | Destination | Why |
|---|---|---|
| `ws_handler` `json_dispatch` generation | `protocol_wire` JSON facade (via `generator/json_rpc_dispatch.gleam`) | Protocol dispatch belongs in the protocol layer |
| `ws_handler` JSON dispatch helpers (`json_dispatch_arm`, `json_handler_call`, `json_response_encode`, `json_encoder_for_fieldtype`, `closure_param_for_fieldtype`) | `src/rally/generator/json_rpc_dispatch.gleam` | Shared by ws_handler (no-auth non-facade paths) and generator.gleam (facade generation). Avoids `generator.gleam` depending on `ws_handler.gleam`. |
| `ws_handler` JSON text branch auth bypass | Shared auth flow using `wire.decode_ws_rpc_envelope` | Bug fix |
| `http_handler` "Not implemented" stub | Shared auth flow using `wire.decode_rpc_envelope` | Bug fix |
| `http_handler` ETF-specific `decode_call` + `variant_tag` | `wire.decode_rpc_envelope` | Protocol agnosticism |
| `ws_handler` ETF-specific `decode_call` + `variant_tag` | `wire.decode_ws_rpc_envelope` | Protocol agnosticism |

### What stays put

- Page-init frame handling stays in WS handler (not RPC dispatch)
- `handler_page_info` stays generated in each handler (HTTP/WS have different
  endpoint sets in multi-namespace setups)
- `check_page_authorize` stays in each handler
- Push frame handling stays in WS handler

### Logging decision

Server message logging (`system.log_to_server`) currently takes `value:
Dynamic` (the decoded ETF value) and `raw_payload: BitArray`. Once
`RpcEnvelope` is opaque, the handler cannot access these directly.

Decision: add facade accessors for logging:

```gleam
// Return the raw payload for message logging (BitArray for ETF, String-as-BitArray for JSON)
pub fn rpc_raw_payload(envelope: RpcEnvelope) -> BitArray

// Return the identity string (already exposed via rpc_identity)
pub fn rpc_identity(envelope: RpcEnvelope) -> String
```

For `system.log_to_server`, change the `value: Dynamic` parameter: pass the
identity string instead of the raw decoded value. The identity string is
what the message inspector needs for variant name display. The raw payload
is preserved via `rpc_raw_payload` for debugging. Update `system.log_to_server`
call sites in Task 6.

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

Add `RpcEnvelope`, `decode_rpc_envelope`, `decode_ws_rpc_envelope`,
`rpc_request_id`, `rpc_identity`, and `rpc_raw_payload` to both facade versions.

- [ ] **Step 1: Add to ETF facade (`etf_protocol_wire_source`)**

The ETF facade needs new imports for `mist` (for `WebsocketMessage` type).
Add these to the generated source string:

```gleam
import mist

pub opaque type RpcEnvelope {
  RpcEnvelope(request_id: Int, identity: String, raw: BitArray)
}

pub fn rpc_request_id(envelope: RpcEnvelope) -> Int { envelope.request_id }
pub fn rpc_identity(envelope: RpcEnvelope) -> String { envelope.identity }
pub fn rpc_raw_payload(envelope: RpcEnvelope) -> BitArray { envelope.raw }

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

pub fn decode_ws_rpc_envelope(msg: mist.WebsocketMessage(a)) -> Result(RpcEnvelope, Nil) {
  case msg {
    mist.Binary(data) ->
      case decode_rpc_envelope(data) {
        Ok(envelope) if envelope.request_id == 0 -> Error(Nil)
        result -> result
      }
    _ -> Error(Nil)
  }
}
```

Note: `raw: data` stores the original body for dispatch (ETF's
`rpc_dispatch.handle` re-decodes from the raw body).

- [ ] **Step 2: Add to JSON facade (`json_protocol_wire_source`)**

The JSON facade needs new imports for `bit_array`, `gleam/dynamic/decode`,
and `mist`:

```gleam
import gleam/bit_array
import gleam/dynamic/decode as gleam_decode
import mist

pub opaque type RpcEnvelope {
  RpcEnvelope(request_id: Int, identity: String, message: Dynamic, raw_text: String)
}

pub fn rpc_request_id(envelope: RpcEnvelope) -> Int { envelope.request_id }
pub fn rpc_identity(envelope: RpcEnvelope) -> String { envelope.identity }
pub fn rpc_raw_payload(envelope: RpcEnvelope) -> BitArray { bit_array.from_string(envelope.raw_text) }

pub fn decode_rpc_envelope(data: BitArray) -> Result(RpcEnvelope, Nil) {
  case bit_array.to_string(data) {
    Error(_) -> Error(Nil)
    Ok(text) -> decode_rpc_envelope_text(text)
  }
}

pub fn decode_ws_rpc_envelope(msg: mist.WebsocketMessage(a)) -> Result(RpcEnvelope, Nil) {
  case msg {
    mist.Text(data) ->
      case decode_rpc_envelope_text(data) {
        Ok(envelope) if envelope.request_id == 0 -> Error(Nil)
        result -> result
      }
    _ -> Error(Nil)
  }
}

fn decode_rpc_envelope_text(data: String) -> Result(RpcEnvelope, Nil) {
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
            raw_text: data,
          ))
      }
  }
}

fn extract_message_type(message: Dynamic) -> Result(String, Nil) {
  case gleam_decode.run(
    message,
    gleam_decode.field("type", gleam_decode.string, fn(x) {
      gleam_decode.success(x)
    }),
  ) {
    Ok(type_str) -> Ok(type_str)
    Error(_) -> Error(Nil)
  }
}
```

Note: `raw_text` preserves the original JSON string for logging via
`rpc_raw_payload`. `decode_rpc_envelope_text` is private; external callers
use `decode_rpc_envelope` (for HTTP BitArray bodies) or
`decode_ws_rpc_envelope` (for WS frames).

- [ ] **Step 3: Run auth codegen check**

```sh
cd /Users/daverapin/projects/opensource/rally && bin/check-auth-codegen
```

Expected: generated code compiles. The new functions exist but are not
called yet; no behavior change.

- [ ] **Step 4: Run tests**

```sh
cd /Users/daverapin/projects/opensource/rally && gleam test
```

- [ ] **Step 5: Commit**

```sh
git add src/rally/generator.gleam
git commit -m "Add protocol-neutral decode_rpc_envelope to protocol_wire facade"
```

**Review checkpoint:** `decode_rpc_envelope` and `decode_ws_rpc_envelope`
compile in both facade variants. No callers yet; handler rewrites depend
on dispatch being available first.

### Task 4a: Extract JSON dispatch generator into shared module

**Files:**
- Create: `src/rally/generator/json_rpc_dispatch.gleam`
- Modify: `src/rally/generator/ws_handler.gleam` (import from new module)
- Test: existing tests pass (no behavior change)

The following functions are currently private in `ws_handler.gleam` and are
pure string-building helpers with no WS-specific logic:

- `json_dispatch_arm` (line 857)
- `json_handler_call` (line 899)
- `json_response_encode` (line 932)
- `json_encoder_for_fieldtype` (line 955)
- `closure_param_for_fieldtype` (line 948)
- `to_pascal_case` (line 995)
- `handler_alias` (line 1007)

Move them to `src/rally/generator/json_rpc_dispatch.gleam` and make them
`pub`. Then have `ws_handler.gleam` import and call the public versions.

Also add a new public function `generate_json_dispatch_body` that produces
just the dispatch function body (the arms and catch-all), which both
ws_handler and generator.gleam will use to generate the full function.

- [ ] **Step 1: Create `src/rally/generator/json_rpc_dispatch.gleam`**

```gleam
import gleam/list
import gleam/option.{Some}
import gleam/string
import libero/field_type.{
  type FieldType, BitArrayField, BoolField, DictOf, FloatField, IntField,
  ListOf, NilField, OptionOf, ResultOf, StringField, TupleOf, TypeVar,
  UserType,
}
import libero/scanner.{type HandlerEndpoint}
import libero/walker

pub fn to_pascal_case(name: String) -> String {
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

pub fn handler_alias(module_path: String) -> String {
  string.replace(module_path, "/", "_") <> "_handler"
}

pub fn endpoint_json_tag(endpoint: HandlerEndpoint) -> String {
  case endpoint.msg_type {
    Some(#(module_path, type_name)) -> module_path <> "." <> type_name
    _ ->
      endpoint.module_path
      <> "."
      <> to_pascal_case("server_" <> endpoint.fn_name)
  }
}

pub fn generate_json_dispatch_function(
  endpoints: List(HandlerEndpoint),
  has_auth: Bool,
) -> String {
  case endpoints {
    [] ->
      "\nfn json_dispatch(
  message _message: Dynamic,
  request_id request_id: Int,
  server_context server_context: ServerContext,"
      <> case has_auth {
        True -> "\n  identity _identity: auth.Identity,"
        False -> ""
      }
      <> "
) -> #(String, ServerContext) {
  let error_frame = wire.encode_error(Some(request_id), [JsonError(\"rpc\", \"no endpoints configured\")])
  #(error_frame, server_context)
}\n"
    _ -> {
      let arms =
        list.map(endpoints, fn(e) { json_dispatch_arm(e, has_auth) })
        |> string.join("\n")
      let catch_all =
        "      Ok(other) -> {
        let error_frame = wire.encode_error(Some(request_id), [JsonError(\"type\", \"unknown: \" <> other)])
        #(error_frame, server_context)
      }"

      "\nfn json_dispatch(
  message message: Dynamic,
  request_id request_id: Int,
  server_context server_context: ServerContext,"
      <> case has_auth {
        True -> "\n  identity identity: auth.Identity,"
        False -> ""
      }
      <> "
) -> #(String, ServerContext) {
  case decode.run(message, decode.field(\"type\", decode.string, fn(x) { decode.success(x) })) {
    Error(_) -> {
      let error_frame = wire.encode_error(Some(request_id), [JsonError(\"type\", \"missing or not a string\")])
      #(error_frame, server_context)
    }\n"
      <> arms
      <> "\n"
      <> catch_all
      <> "\n  }\n}\n"
    }
  }
}

pub fn json_dispatch_arm(
  e: HandlerEndpoint,
  has_auth: Bool,
) -> String {
  let alias = handler_alias(e.module_path)
  let #(type_module, type_name) = case e.msg_type {
    Some(#(mod, name)) -> #(mod, name)
    _ -> #(e.module_path, to_pascal_case("server_" <> e.fn_name))
  }
  let type_str = type_module <> "." <> type_name
  let msg_decoder =
    "json_codecs.json_decode_"
    <> walker.qualified_atom_name(type_module, type_name)
  let handler_call = json_handler_call(e, alias, has_auth)
  let #(ok_destructure, ok_ctx) = case e.mutates_context {
    True -> #("#(result, new_ctx)", "new_ctx")
    False -> #("result", "server_context")
  }
  let response_encode = json_response_encode(e)

  "    Ok(\"" <> type_str <> "\") -> {
      case " <> msg_decoder <> "(message) {
        Error(errors) -> {
          let error_frame = wire.encode_error(Some(request_id), errors)
          #(error_frame, server_context)
        }
        Ok(msg) -> {
          case trace.try_call(fn() { " <> handler_call <> " }) {
            Ok(" <> ok_destructure <> ") -> {
              " <> response_encode <> "
              let frame = wire.encode_response(request_id, encoded)
              #(frame, " <> ok_ctx <> ")
            }
            Error(reason) -> {
              let trace_id = trace.new_trace_id()
              io.println_error(\"[libero] \" <> trace_id <> \" " <> e.fn_name <> ": \" <> reason)
              let error_frame = wire.encode_error(Some(request_id), [JsonError(\"handler\", \"Something went wrong\")])
              #(error_frame, server_context)
            }
          }
        }
      }
    }"
}

pub fn json_handler_call(
  e: HandlerEndpoint,
  alias: String,
  has_auth: Bool,
) -> String {
  let extra = case has_auth {
    True -> ", identity:"
    False -> ""
  }
  case e.msg_type {
    Some(_) ->
      alias
      <> "."
      <> "server_"
      <> e.fn_name
      <> "(msg: msg, server_context: server_context"
      <> extra
      <> ")"
    _ -> {
      let labeled = list.map(e.params, fn(p) { p.0 <> ": " <> p.0 })
      let args =
        list.append(labeled, ["server_context: server_context" <> extra])
      alias
      <> "."
      <> "server_"
      <> e.fn_name
      <> "("
      <> string.join(args, ", ")
      <> ")"
    }
  }
}

pub fn json_response_encode(e: HandlerEndpoint) -> String {
  let ok_encoder = json_encoder_for_fieldtype(e.return_ok, "x")
  let err_encoder = json_encoder_for_fieldtype(e.return_err, "x")
  let ok_param = closure_param_for_fieldtype(e.return_ok)
  let err_param = closure_param_for_fieldtype(e.return_err)
  "let encoded = json_codecs.json_encode_gleam_result__result(result, fn("
  <> ok_param
  <> ") { "
  <> ok_encoder
  <> " }, fn("
  <> err_param
  <> ") { "
  <> err_encoder
  <> " })"
}

pub fn closure_param_for_fieldtype(ft: FieldType) -> String {
  case ft {
    NilField -> "_x"
    _ -> "x"
  }
}

pub fn json_encoder_for_fieldtype(ft: FieldType, var: String) -> String {
  case ft {
    StringField -> "json.string(" <> var <> ")"
    IntField -> "json.int(" <> var <> ")"
    FloatField -> "json.float(" <> var <> ")"
    BoolField -> "json.bool(" <> var <> ")"
    NilField -> "json.null()"
    BitArrayField ->
      "json.string(bit_array.base64_encode(" <> var <> ", True))"
    UserType(module_path:, type_name:, ..) ->
      "json_codecs.json_encode_"
      <> walker.qualified_atom_name(module_path, type_name)
      <> "("
      <> var
      <> ")"
    ListOf(inner) ->
      "json_codecs.json_encode_gleam__list("
      <> var
      <> ", fn(x) { "
      <> json_encoder_for_fieldtype(inner, "x")
      <> " })"
    OptionOf(inner) ->
      "json_codecs.json_encode_gleam_option__option("
      <> var
      <> ", fn(x) { "
      <> json_encoder_for_fieldtype(inner, "x")
      <> " })"
    ResultOf(ok, err) ->
      "json_codecs.json_encode_gleam_result__result("
      <> var
      <> ", fn(x) { "
      <> json_encoder_for_fieldtype(ok, "x")
      <> " }, fn(x) { "
      <> json_encoder_for_fieldtype(err, "x")
      <> " })"
    DictOf(_, _) ->
      "json_codecs.json_encode_gleam__dict(" <> var <> ")"
    TupleOf(_) ->
      "json_codecs.json_encode_gleam__tuple(" <> var <> ")"
    TypeVar(_) -> "panic as \"cannot encode type variable\""
  }
}

/// Collect unique handler module imports for generated code
pub fn handler_imports(
  endpoints: List(HandlerEndpoint),
) -> List(String) {
  endpoints
  |> list.map(fn(e) { e.module_path })
  |> list.unique()
  |> list.map(fn(mod) {
    let alias = handler_alias(mod)
    case string.split(mod, "/") |> list.last {
      Ok(seg) if seg == alias -> "import " <> mod
      _ -> "import " <> mod <> " as " <> alias
    }
  })
}
```

- [ ] **Step 2: Update `ws_handler.gleam` to import from the new module**

Replace the private copies of `json_dispatch_arm`, `json_handler_call`,
`json_response_encode`, `json_encoder_for_fieldtype`,
`closure_param_for_fieldtype`, `to_pascal_case`, and `handler_alias` with
imports from `rally/generator/json_rpc_dispatch`.

In `generate_json_dispatch_function`, delegate:

```gleam
fn generate_json_dispatch_function(
  endpoints: List(HandlerEndpoint),
  has_auth: Bool,
) -> String {
  json_rpc_dispatch.generate_json_dispatch_function(endpoints, has_auth)
}
```

Update the handler imports generation to use
`json_rpc_dispatch.handler_imports(endpoints)`.

- [ ] **Step 3: Run tests**

```sh
cd /Users/daverapin/projects/opensource/rally && gleam test
```

Expected: all pass, no behavior change. The dispatch output is identical;
only the source location of the generator helpers changed.

- [ ] **Step 4: Commit**

```sh
git add src/rally/generator/json_rpc_dispatch.gleam src/rally/generator/ws_handler.gleam
git commit -m "Extract JSON dispatch generator into shared module"
```

**Review checkpoint:** `json_rpc_dispatch.gleam` exists, ws_handler delegates
to it, all tests pass. No new callers yet.

### Task 4b: Add dispatch and response to protocol_wire facade

**Files:**
- Modify: `src/rally/generator.gleam`
- Modify: `src/rally.gleam` (call site for `generate_protocol_wire`)
- Test: `bin/check-auth-codegen`

The `generate_protocol_wire` signature grows to include everything the facade
needs to generate dispatch code, auth error responses, and the `json_dispatch`
function body:

```gleam
pub fn generate_protocol_wire(
  protocol: String,
  atoms_module: String,
  contract_hash: String,
  rpc_dispatch_module: String,
  endpoints: List(HandlerEndpoint),
  auth_config: Option(AuthConfig),
  wire_import_module: String,
) -> String
```

Required inputs and why:
- `rpc_dispatch_module`: ETF facade imports it for `dispatch_rpc`
- `endpoints`: JSON facade generates `json_dispatch` arms per endpoint
- `auth_config`: both facades conditionally include `identity` parameter
  in `dispatch_rpc`. JSON facade imports the auth module for `auth.Identity`.
  `None` means no auth: `dispatch_rpc` omits the identity parameter.
- `wire_import_module`: JSON facade derives the json_codecs module name
  from it (same `string.replace` pattern ws_handler uses today)

- [ ] **Step 1: Add RpcResult and dispatch to ETF facade**

Add to the `etf_protocol_wire_source` function. The function gains
`rpc_dispatch_module` and `auth_config` parameters. The generated source
includes:

```gleam
import gleam/bytes_tree
import glisten
import mist.{type WebsocketConnection}
import <rpc_dispatch_module> as rpc_dispatch

pub opaque type RpcResult {
  RpcResult(data: BitArray)
}

// When auth_config is None:
pub fn dispatch_rpc(
  envelope envelope: RpcEnvelope,
  server_context server_context: ServerContext,
) -> #(RpcResult, ServerContext) {
  let #(response_data, new_ctx) = rpc_dispatch.handle(server_context:, data: envelope.raw)
  #(RpcResult(data: response_data), new_ctx)
}

// When auth_config is Some(AuthConfig(auth_module:)):
// (import <auth_module> as auth)
pub fn dispatch_rpc(
  envelope envelope: RpcEnvelope,
  server_context server_context: ServerContext,
  identity identity: auth.Identity,
) -> #(RpcResult, ServerContext) {
  let #(response_data, new_ctx) = rpc_dispatch.handle(server_context:, data: envelope.raw, identity:)
  #(RpcResult(data: response_data), new_ctx)
}

pub fn send_rpc_result(
  conn: WebsocketConnection,
  result: RpcResult,
) -> Result(Nil, glisten.SocketReason) {
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

Only one `dispatch_rpc` variant is generated. The generator checks
`auth_config`: `Some` generates the identity variant, `None` generates
the no-identity variant.

- [ ] **Step 2: Add RpcResult and dispatch to JSON facade**

The JSON facade uses `json_rpc_dispatch.generate_json_dispatch_function`
to produce the `json_dispatch` function body. The function gains
`endpoints`, `auth_config`, and `wire_import_module` parameters.

Required imports in generated source (in addition to existing):

```gleam
import gleam/bytes_tree
import gleam/io
import gleam/json
import gleam/option.{Some}
import glisten
import libero/json/error.{JsonError}
import libero/trace
import mist.{type WebsocketConnection}
import <json_codec_module> as json_codecs
// Per-endpoint handler imports (from json_rpc_dispatch.handler_imports):
import <handler_module> as <handler_alias>
// When auth_config is Some:
import <auth_module> as auth
```

Where `json_codec_module` is derived from `wire_import_module` using
`string.replace(wire_import_module, "protocol_wire", "json_codecs")`.

Generated dispatch and response functions:

```gleam
pub opaque type RpcResult {
  RpcResult(text: String)
}

// json_dispatch body generated by json_rpc_dispatch.generate_json_dispatch_function
// This produces the full fn with arms like:
//   Ok("admin/pages/dashboard.ServerLoadData") -> { ... handler call ... }
<output of json_rpc_dispatch.generate_json_dispatch_function(endpoints, has_auth)>

// dispatch_rpc wraps json_dispatch, converting String result to RpcResult
// When auth_config is Some:
pub fn dispatch_rpc(
  envelope envelope: RpcEnvelope,
  server_context server_context: ServerContext,
  identity identity: auth.Identity,
) -> #(RpcResult, ServerContext) {
  let #(frame, ctx) = json_dispatch(
    message: envelope.message,
    request_id: envelope.request_id,
    server_context:,
    identity:,
  )
  #(RpcResult(text: frame), ctx)
}

pub fn send_rpc_result(
  conn: WebsocketConnection,
  result: RpcResult,
) -> Result(Nil, glisten.SocketReason) {
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
    request_id: Some(request_id),
    errors: [JsonError("rpc", message)],
  ))
}
```

The `json_dispatch` function body is generated by calling
`json_rpc_dispatch.generate_json_dispatch_function(endpoints, has_auth)`
and concatenating its output into the facade source string.

- [ ] **Step 3: Update `rally.gleam` call site**

Find `generator.generate_protocol_wire(` in `rally.gleam` (around line
967) and pass the new arguments:

```gleam
generator.generate_protocol_wire(
  config.protocol,
  config.atoms_module,
  contract_hash,
  rpc_dispatch_module,
  ns_endpoints,
  auth_config,
  protocol_wire_module,
)
```

`rpc_dispatch_module` is already in scope at this call site.
`ns_endpoints` is the filtered endpoint list.
`auth_config` is already in scope.
`protocol_wire_module` is already computed.

- [ ] **Step 4: Add a no-endpoints JSON facade compile test**

Generate a JSON protocol_wire with an empty endpoint list and verify the
output contains a `json_dispatch` stub that compiles (not an empty string):

```gleam
pub fn json_protocol_wire_no_endpoints_compiles_test() {
  let source =
    generator.generate_protocol_wire(
      "json",
      "generated/admin/rpc_atoms",
      "test_hash",
      "generated/admin/rpc_dispatch",
      [],
      None,
      "generated/admin/protocol_wire",
    )
  let assert True = string.contains(source, "fn json_dispatch(")
  let assert True = string.contains(source, "fn dispatch_rpc(")
}
```

- [ ] **Step 5: Run auth codegen check**

```sh
cd /Users/daverapin/projects/opensource/rally && bin/check-auth-codegen
```

This is the critical verification: the generated protocol_wire facade must
compile with its new imports (handler modules, json_codecs, auth module,
mist, glisten, bytes_tree) and the json_dispatch function must type-check.

- [ ] **Step 6: Run tests**

```sh
cd /Users/daverapin/projects/opensource/rally && gleam test
```

- [ ] **Step 7: Commit**

```sh
git add src/rally/generator.gleam src/rally.gleam
git commit -m "Add dispatch and response to protocol_wire facade"
```

**Review checkpoint:** Both facade variants compile with dispatch, including
zero-endpoint edge case. The
facade is now a complete server-side protocol boundary: decode, identity,
dispatch, response framing, error responses. No callers in the handlers
yet; that is Tasks 5 and 6.

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
decode path with a single `wire.decode_ws_rpc_envelope(msg)` call. Both
frame types should use the same auth + dispatch flow.

- [x] **Step 1: Unify the RPC frame decode (auth version)**

Currently the auth WS handler generates separate `mist.Binary(data)` and
`mist.Text(data)` branches. Replace both with a single RPC path that uses
`decode_ws_rpc_envelope`:

The frame handler's RPC path becomes:

```
case wire.decode_ws_rpc_envelope(msg) {
  Ok(envelope) -> {
    let request_id = wire.rpc_request_id(envelope)
    debug_log("[rally:ws] RPC: request_id=" <> int.to_string(request_id))
    let assert Ok(server_context) = effect.get_stored_server_context()
    let current_page = effect.get_ws_page()
    case handler_page_info(wire.rpc_identity(envelope)) {
      Error(Nil) -> {
        let result = wire.auth_error_result(request_id, "auth:unknown_rpc")
        let _send = wire.send_rpc_result(conn, result)
        send_pending_frames(conn)
        mist.continue(state)
      }
      Ok(info) -> {
        // ... same auth checks as current ETF path:
        // owning_page != current_page -> auth:page_mismatch
        // required && !is_authenticated -> auth:redirect
        // has_authorize && !check_page_authorize -> auth:forbidden
        // then:
        let start = timestamp.system_time()
        let #(result, new_ctx) = wire.dispatch_rpc(envelope, server_context, identity)
        let elapsed_ms = ...
        // logging (see Step 2)
        let Nil = effect.put_ws_state(conn, new_ctx, current_page)
        let _send = wire.send_rpc_result(conn, result)
        send_pending_frames(conn)
        mist.continue(state)
      }
    }
  }
  Error(Nil) -> {
    // Not an RPC frame (page-init, or unsupported frame type).
    // Fall through to page-init handling or ignore.
  }
}
```

Page-init frames are NOT decoded by `decode_ws_rpc_envelope` (they use
`decode_call` for ETF and are not yet implemented for JSON). Keep page-init
handling in its existing protocol-specific branch for now. The RPC path is
what gets unified.

The frame handler structure becomes: try `decode_ws_rpc_envelope` first
for RPC, then fall through to page-init handling if it returns `Error(Nil)`.

- [x] **Step 2: Update logging to use facade accessors**

Current logging calls:

```gleam
system.log_to_server(
  db: db_conn,
  session_id: session_id,
  user_id: Error(Nil),
  page: current_page,
  value: raw,           // <- Dynamic, from ETF decode
  raw_payload: data,    // <- BitArray, raw frame
  elapsed_ms: elapsed_ms,
)
```

Change to use the facade accessors:

```gleam
system.log_to_server(
  db: db_conn,
  session_id: session_id,
  user_id: Error(Nil),
  page: current_page,
  variant_name: wire.rpc_identity(envelope),
  raw_payload: wire.rpc_raw_payload(envelope),
  elapsed_ms: elapsed_ms,
)
```

This requires updating `system.log_to_server` to accept `variant_name:
String` instead of `value: Dynamic` (which it currently calls
`wire.variant_tag` on to derive the variant name). This is a small change
to `rally_runtime/system.gleam`: replace the `value` parameter with
`variant_name`.

JSON malformed RPC text frames now use `wire.malformed_rpc_result()` so
the handler still responds with a protocol-shaped error without calling the
JSON request decoder directly.

- [x] **Step 3: Rewrite the no-auth RPC branch**

Same pattern as Step 1 but without the auth checks. Replace
`rpc_dispatch.handle` and `json_dispatch` with `wire.dispatch_rpc`:

```
case wire.decode_ws_rpc_envelope(msg) {
  Ok(envelope) -> {
    let #(result, new_ctx) = wire.dispatch_rpc(envelope, server_context)
    // logging, state update
    let _send = wire.send_rpc_result(conn, result)
    send_pending_frames(conn)
    mist.continue(state)
  }
  Error(Nil) -> // page-init or ignore
}
```

- [x] **Step 4: Remove inline `json_dispatch` generation from ws_handler**

`generate_json_dispatch_function` was already delegated to
`json_rpc_dispatch` in Task 4a. Now remove the ws_handler's call to
generate it as a top-level function in the WS handler output, since
dispatch now goes through the facade. The `json_dispatch` variable in
`generate` (around line 119) should become `""` for all protocols.

- [x] **Step 5: Add JSON WS auth test**

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

  // Must use protocol-neutral decode (same call for both protocols)
  let assert True = string.contains(output, "wire.decode_ws_rpc_envelope(")
  // Must look up auth info by identity
  let assert True = string.contains(output, "handler_page_info(wire.rpc_identity(")
  // Must check is_authenticated
  let assert True = string.contains(output, "is_authenticated")
  // Must check page mismatch
  let assert True = string.contains(output, "owning_page != current_page")
  // Must dispatch through facade
  let assert True = string.contains(output, "wire.dispatch_rpc(")
  // Must NOT contain inline json_dispatch call
  let assert False = string.contains(output, "json_dispatch(")
  // Must NOT call decode_call or variant_tag
  let assert False = string.contains(output, "decode_call")
  let assert False = string.contains(output, "variant_tag")
}
```

Also add a test that verifies ETF output uses the same API:

```gleam
pub fn ws_auth_etf_also_uses_protocol_neutral_decode_test() {
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
      protocol: "etf",
    )

  // ETF also uses the unified decode before the page-init fallback
  let assert True = string.contains(output, "wire.decode_ws_rpc_envelope(")
  let assert Ok(#(before_page_init_decode, _)) =
    string.split_once(output, "wire.decode_call")
  let assert True =
    string.contains(before_page_init_decode, "wire.decode_ws_rpc_envelope(msg)")
  // Must NOT call variant_tag directly
  let assert False = string.contains(output, "variant_tag")
}
```

- [x] **Step 6: Update existing ETF WS test assertions**

Existing tests that assert `decode_call` or `variant_tag` in the generated
output must be updated to assert `decode_ws_rpc_envelope` and
`wire.rpc_identity` instead. Find all such assertions and update them.

- [x] **Step 7: Run tests**

```sh
cd /Users/daverapin/projects/opensource/rally && gleam test
cd /Users/daverapin/projects/opensource/rally && bin/check-auth-codegen
```

- [x] **Step 8: Update `system.gleam` if logging signature changed**

If Step 2 changed `system.log_to_server` to take `variant_name: String`
instead of `value: Dynamic`, update all callers. Check with:

```sh
grep -rn 'log_to_server' src/rally_runtime/
```

- [x] **Step 9: Commit**

```sh
git add src/rally/generator/ws_handler.gleam src/rally_runtime/system.gleam test/rally/ws_auth_test.gleam
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
# No protocol-specific calls in generated HTTP handlers
grep -n 'decode_call\|variant_tag\|decode_request' src/rally/generator/http_handler.gleam
# Expected: 0 matches (no direct protocol calls)

# WS may still use decode_call only in the ETF page-init fallback.
grep -n 'variant_tag\|decode_request' src/rally/generator/ws_handler.gleam
# Expected: 0 matches
grep -n 'decode_call' src/rally/generator/ws_handler.gleam
# Expected: page-init fallback only, after decode_ws_rpc_envelope.

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

- Server message logging: `system.log_to_server` changes from
  `value: Dynamic` (passed to `variant_tag` internally) to
  `variant_name: String` (the identity from the facade). The raw payload
  is available via `rpc_raw_payload`. This changes the `system.gleam`
  module signature. The message inspector's variant name display should
  still work since the identity string is what it ultimately displayed.
  The raw decoded Dynamic value (which the inspector could format) is no
  longer available through the handler; if that turns out to matter, a
  follow-up can add a `rpc_decoded_value` accessor.

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
- New: HTTP handlers do not call `decode_call`, `variant_tag`, or
  `decode_request` directly. WS RPC handling uses `decode_ws_rpc_envelope`;
  ETF `decode_call` remains only as the page-init fallback.
- New: Both ETF and JSON handler_page_info entries resolve to the same
  PageAuthInfo for the same endpoint
