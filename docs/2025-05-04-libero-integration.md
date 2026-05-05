# Libero Integration: Replace Server TEA with Handler-as-Contract

## Context

Lando currently uses a Lamdera-style server TEA pattern: `ServerModel`, `server_init`, `server_update`, `ToServer`/`ToClient` types. This is being replaced with libero's handler-as-contract pattern where server functions define the wire contract through their signatures.

Libero v6 (at `../libero`) is cleaned up as a focused library: scanner, dispatch codegen, wire protocol, decoder generation. Lando will consume it as a path dependency.

## What changes for users

### Before (server TEA)
```gleam
// src/pages/login.gleam

pub type ToServer { SubmitLogin(email: String, password: String) }
pub type ToClient { LoginSuccess(token: String); LoginError(errors: List(String)) }
pub type ServerModel { ServerModel }

pub fn server_init(_server_context: ServerContext) -> ServerModel { ServerModel }

pub fn server_update(
  _model: ServerModel,
  msg: ToServer,
  server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  case msg {
    SubmitLogin(email, password) -> {
      // ...validate, query DB...
      #(ServerModel, lando_effect.send_to_client(LoginSuccess(token)))
    }
  }
}
```

### After (handler-as-contract)
```gleam
// src/pages/login.gleam

pub fn server_login(
  email email: String,
  password password: String,
  server_context server_context: ServerContext,
) -> Result(String, List(String)) {
  // ...validate, query DB...
  Ok(token)
}
```

That's it. No ToServer, no ToClient, no ServerModel, no server_init, no effect wrapping. The function signature IS the contract. The scanner finds it, generates dispatch + client stubs.

### Client side changes

Before:
```gleam
pub type Msg { GotServerMsg(ToClient) }

pub fn update(client_context, model, msg) {
  case msg {
    GotServerMsg(LoginSuccess(token)) -> ...
    GotServerMsg(LoginError(errors)) -> ...
  }
}

// Calling the server:
lando_effect.send_to_server(SubmitLogin(email, password))
```

After:
```gleam
import libero/remote_data.{type RpcData}

pub type Msg { GotLogin(RpcData(String, List(String))) }

pub fn update(client_context, model, msg) {
  case msg {
    GotLogin(remote_data.Success(token)) -> ...
    GotLogin(remote_data.Failure(remote_data.DomainError(errors))) -> ...
  }
}

// Calling the server (generated stub):
// The generated views.gleam provides: login_server_login(email:, password:, on_response: GotLogin)
```

## Libero's public API (what Lando calls)

```gleam
import libero/scanner.{type HandlerEndpoint}
import libero/walker
import libero/field_type.{type FieldType}
import libero/codegen_dispatch
import libero/codegen_decoders
```

### scanner.scan(src_dir:, context_type_name:)
Walks src_dir, finds `pub fn server_*` functions with the named context type as a param and Result return. Returns `List(HandlerEndpoint)` with fn_name (prefix stripped), params, return_ok, return_err, mutates_context.

### codegen_dispatch.generate(endpoints:, context_module:, context_type_name:, wire_module_tag:)
Generates server dispatch source. Pattern matches incoming wire calls to handler invocations. Catches panics via trace.try_call.

### walker.walk(seeds, file_paths, src_root)
BFS type graph from seed types. Discovers all reachable custom types for decoder generation.

### codegen_decoders
Generates JS type registration files so the ETF codec can reconstruct typed Gleam values on the client.

## Implementation plan

### Phase 1: Add libero dependency, wire up scanner

1. Add `libero = { path = "../libero" }` to Lando's gleam.toml
2. In `src/lando.gleam`, after route scanning, call `libero/scanner.scan(config.pages_root, "ServerContext")` to discover handler endpoints
3. Verify scanner finds server_ functions in the realworld example pages
4. Print discovered endpoints for debugging

### Phase 2: Generate dispatch from libero

1. Call `codegen_dispatch.generate(endpoints:, context_module: "server_context", context_type_name: "ServerContext", wire_module_tag: "rpc")`
2. Write to `src/generated/server_dispatch.gleam` (replaces the old hand-rolled dispatch)
3. The generated dispatch imports handler modules and calls their server_ functions directly

### Phase 3: Replace Lando's duplicated modules with libero imports

Remove from Lando (now provided by libero):
- `src/lando/field_type.gleam` -> use `libero/field_type`
- `src/lando/walker.gleam` -> use `libero/walker`
- `src/lando_runtime/wire.gleam` -> use `libero/wire`
- `src/lando_runtime/trace.gleam` -> use `libero/trace`
- `src/lando_runtime/remote_data.gleam` -> use `libero/remote_data`
- `src/lando_runtime/error.gleam` -> use `libero/error`
- `src/lando_runtime/rpc_ffi.mjs` -> use libero's copy
- `src/lando_runtime/decoders_prelude.mjs` -> use libero's copy
- `src/lando_runtime_ffi.erl` (encode/decode functions) -> use libero's FFI
- `src/lando_runtime_wire_ffi.erl` -> use libero's FFI

Keep in Lando (framework-specific):
- `src/lando_runtime/effect.gleam` (send_to_client, broadcast, navigate, topics interaction)
- `src/lando_runtime/topics.gleam` + FFI (pg group pub/sub)
- `src/lando_runtime/db.gleam` + FFI (SQLite helpers)
- `src/lando_runtime/system.gleam` (system DB, jobs)
- `src/lando_runtime/jobs.gleam`
- `src/lando_runtime/session.gleam`
- `src/lando_runtime/codec.gleam` (base64 flags for SSR)
- `src/lando_runtime/lando_effect_ffi.mjs` (navigate)
- `src/lando_runtime_topics_ffi.erl`
- `src/lando_runtime_db_ffi.erl`

### Phase 4: Remove server TEA from parser/generators

1. Remove from `src/lando/parser.gleam`: parsing of ServerModel, server_init, server_update, ToServer, ToClient
2. Remove from `src/lando/types.gleam`: related type fields
3. Rewrite `src/lando/generator/server_dispatch.gleam` to just call libero's codegen_dispatch (or delete it entirely and call libero directly from lando.gleam)
4. Simplify `src/lando/generator/ws_handler.gleam`: no more state Dict for models, just call dispatch.handle and drain frames
5. Update `src/lando/generator/ssr_handler.gleam`: no more server_init for load pages (load stays as-is since it's an SSR concern, not an RPC concern)

### Phase 5: Generate client stubs from endpoints

1. Rewrite `src/lando/generator/codec.gleam` to generate client stubs from `HandlerEndpoint` list instead of from ToServer/ToClient types
2. Each endpoint becomes a typed function in the generated views.gleam (or a new stubs file):
   ```gleam
   pub fn login_server_login(
     email email: String,
     password password: String,
     on_response on_response: fn(RpcData(String, List(String))) -> Msg,
   ) -> Effect(Msg)
   ```
3. Remove the old per-page GotServerMsg pattern
4. Remove generated types.gleam (ToServer/ToClient mirrors) since there are no message types to mirror

### Phase 6: Add HTTP handler

1. New generator: `src/lando/generator/http_handler.gleam`
2. Generates a handler that: reads ETF body from POST /rpc, calls dispatch.handle, returns ETF response
3. Session from Authorization header or cookie
4. Wire into the scaffold's app.gleam

### Phase 7: Update realworld example

1. Convert all pages: remove ServerModel/server_init/server_update/ToServer/ToClient
2. Add server_ prefixed handler functions
3. Update client Msg types to use RpcData
4. Update client update functions for new response shape
5. Regenerate all generated code
6. Verify it builds and works

### Phase 8: Update tests, docs, scaffold

1. Remove/update parser tests that test for ToServer/ToClient parsing
2. Add tests for the new libero-based pipeline
3. Update llms.txt
4. Update bin/new scaffold template
5. Update realworld README

## Effect changes

The current `lando_effect.send_to_server(msg)` goes away. Client-to-server calls are now generated stubs that use libero's wire protocol directly.

For server-to-client push (broadcast, send_to_client_context), these remain as Lando framework effects. They're not RPC (no request/response), they're fire-and-forget pushes.

So the effect module keeps:
- `broadcast_to_page(msg)` / `broadcast_to_app(msg)` / `broadcast_to_session(msg)`
- `send_to_client_context(msg)`
- `navigate(path)`
- `get_ws_session()`

And loses:
- `send_to_server(msg)` (replaced by generated stubs)
- `send_to_client(msg)` (replaced by handler return values via dispatch)

## Open questions

1. **Broadcast from handlers**: if a server_create_article handler wants to broadcast to all page viewers, how? Options: (a) the handler returns a special value, (b) the handler calls an effect directly, (c) lando wraps the dispatch call and checks for broadcasts after. Recommend (b): handler calls `lando_runtime/effect.broadcast_to_page(msg)` directly since it's in the same process with the right process dict state.

2. **Load function**: SSR load stays separate from the handler pattern. It's called during SSR rendering, not via RPC. Keep `pub fn load(server_context) -> Model` as-is.

3. **Naming collisions**: if two pages both have `server_login`, libero's scanner will flag a duplicate. This is correct since dispatch is global. Pages should use descriptive names: `server_submit_login` on the login page, or we scope by page name in the wire tag.

## File path reference

- Libero source: `/Users/daverapin/projects/opensource/libero/src/libero/`
- Lando codegen: `/Users/daverapin/projects/opensource/lando/src/lando/`
- Lando runtime: `/Users/daverapin/projects/opensource/lando/src/lando_runtime/`
- Lando generators: `/Users/daverapin/projects/opensource/lando/src/lando/generator/`
- Realworld example: `/Users/daverapin/projects/opensource/lando/examples/realworld/`
- Libero v6 spec: `/Users/daverapin/projects/opensource/libero/docs/v6-library-cleanup.md`
