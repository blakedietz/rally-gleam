# Rally Auth Framework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add convention-based auth to rally: per-namespace auth modules, page-level auth declarations, identity threading through SSR/WS/HTTP handlers, LoadResult with cookie/redirect support.

**Architecture:** Rally scans for `auth.gleam` per namespace during codegen, detects `page_auth` constants and `authorize` functions on pages, and generates handler code that calls resolve/is_authenticated/authorize before dispatching to page load and server handlers. Auth is opt-in (backwards compatible) and app-defined (rally never inspects the Identity type).

**Tech Stack:** Gleam, Glance (AST parsing), Libero (RPC codegen), Mist (HTTP/WS)

**Spec:** `docs/auth-framework-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `src/rally/types.gleam` | Modify | Add `has_page_auth`, `page_auth_required`, `has_authorize` to `PageContract`. Add `AuthConfig` type. |
| `src/rally/parser.gleam` | Modify | Detect `pub const page_auth` and `pub fn authorize` in page modules. |
| `src/rally.gleam` | Modify | Detect auth.gleam per namespace, pass auth config to generators. |
| `src/rally/generator/ssr_handler.gleam` | Modify | Generate resolve → is_authenticated → from_session(identity) → authorize → load(identity) → LoadResult flow. |
| `src/rally/generator/ws_handler.gleam` | Modify | Generate on_init with resolve+from_session, page-init auth checks, RPC auth with owning-page verification, reauth. |
| `src/rally/generator/http_handler.gleam` | Modify | Generate resolve → from_session → authorize → dispatch with identity. |
| `src/rally_runtime/auth.gleam` | Create | `Required`/`Optional` constants, `LoadResult`/`Cookie` types. |
| `test/rally/parser_auth_test.gleam` | Create | Tests for page_auth and authorize detection. |
| `test/rally/auth_codegen_test.gleam` | Create | Snapshot tests for generated handler code with auth. |

## Progress

---

### Task 1: Define runtime auth types

The types that consuming apps import: `rally.Required`, `rally.Optional`, `LoadResult`, `Cookie`.

**Files:**
- Create: `src/rally_runtime/auth.gleam`

- [ ] **Step 1: Create the auth module**

```gleam
// src/rally_runtime/auth.gleam

pub type AuthPolicy {
  Required
  Optional
}

pub type LoadResult(data) {
  Page(data: data, cookies: List(Cookie))
  Redirect(url: String, cookies: List(Cookie))
}

pub type Cookie {
  SetCookie(name: String, value: String, max_age: Int)
  ClearCookie(name: String)
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/daverapin/projects/opensource/rally && gleam build`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add src/rally_runtime/auth.gleam
git commit -m "Add auth runtime types: AuthPolicy, LoadResult, Cookie"
```

---

### Task 2: Add auth fields to PageContract

The parser needs to report what auth-related exports a page has.

**Files:**
- Modify: `src/rally/types.gleam`

- [ ] **Step 1: Add auth fields to PageContract**

Add three fields to `PageContract`:

```gleam
pub type PageContract {
  PageContract(
    model_variants: List(VariantInfo),
    msg_variants: List(VariantInfo),
    has_load: Bool,
    has_init: Bool,
    has_init_loaded: Bool,
    has_model: Bool,
    updates_client_context: Bool,
    param_names: List(String),
    source: String,
    view_source: String,
    init_source: String,
    update_source: String,
    has_page_auth: Bool,
    page_auth_required: Bool,
    has_authorize: Bool,
  )
}
```

- [ ] **Step 2: Fix all PageContract construction sites**

Every place that constructs a `PageContract` needs the new fields. Search for `PageContract(` in:
- `src/rally/parser.gleam` (the main constructor)
- Any test files that construct PageContract directly

Add `has_page_auth: False, page_auth_required: False, has_authorize: False` to each.

- [ ] **Step 3: Verify it compiles**

Run: `cd /Users/daverapin/projects/opensource/rally && gleam build`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add src/rally/types.gleam src/rally/parser.gleam
git commit -m "Add auth fields to PageContract type"
```

---

### Task 3: Parse page_auth and authorize from page modules

Teach the parser to detect `pub const page_auth` and `pub fn authorize` in page source files.

**Files:**
- Modify: `src/rally/parser.gleam`
- Create: `test/rally/parser_auth_test.gleam`

- [ ] **Step 1: Write failing test for page_auth detection**

```gleam
// test/rally/parser_auth_test.gleam
import rally/parser

pub fn parse_page_auth_required_test() {
  let source = "
import rally_runtime/auth

pub const page_auth = auth.Required

pub type Model { Model }
pub type Msg { NoOp }
pub fn load(server_context) { Nil }
pub fn init_loaded(ctx, data) { #(Model, []) }
pub fn view(ctx, model) { element.none() }
pub fn update(ctx, model, msg) { #(model, []) }
"
  let assert Ok(contract) = parser.parse_page(source:, module_path: "test/page")
  let assert True = contract.has_page_auth
  let assert True = contract.page_auth_required
  let assert False = contract.has_authorize
}

pub fn parse_page_auth_optional_test() {
  let source = "
import rally_runtime/auth

pub const page_auth = auth.Optional

pub type Model { Model }
pub type Msg { NoOp }
pub fn load(server_context) { Nil }
pub fn init_loaded(ctx, data) { #(Model, []) }
pub fn view(ctx, model) { element.none() }
pub fn update(ctx, model, msg) { #(model, []) }
"
  let assert Ok(contract) = parser.parse_page(source:, module_path: "test/page")
  let assert True = contract.has_page_auth
  let assert False = contract.page_auth_required
}

pub fn parse_page_no_auth_test() {
  let source = "
pub type Model { Model }
pub type Msg { NoOp }
pub fn load(server_context) { Nil }
pub fn init_loaded(ctx, data) { #(Model, []) }
pub fn view(ctx, model) { element.none() }
pub fn update(ctx, model, msg) { #(model, []) }
"
  let assert Ok(contract) = parser.parse_page(source:, module_path: "test/page")
  let assert False = contract.has_page_auth
  let assert False = contract.page_auth_required
}

pub fn parse_authorize_test() {
  let source = "
import rally_runtime/auth

pub const page_auth = auth.Required

pub fn authorize(server_context, identity) { True }

pub type Model { Model }
pub type Msg { NoOp }
pub fn load(server_context) { Nil }
pub fn init_loaded(ctx, data) { #(Model, []) }
pub fn view(ctx, model) { element.none() }
pub fn update(ctx, model, msg) { #(model, []) }
"
  let assert Ok(contract) = parser.parse_page(source:, module_path: "test/page")
  let assert True = contract.has_authorize
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/daverapin/projects/opensource/rally && gleam test`
Expected: FAIL (has_page_auth is False for all since parser doesn't detect it yet)

- [ ] **Step 3: Implement page_auth and authorize detection**

In `src/rally/parser.gleam`, add detection in `parse_page` after the existing `has_load`/`has_init` checks. Use the Glance AST to find constants and functions:

```gleam
// In parse_page, after the existing function detection block:
let #(has_page_auth, page_auth_required) = detect_page_auth(ast)
let has_authorize = has_function(functions_list, "authorize")
```

Add the `detect_page_auth` function. It needs to search `ast.constants` for a constant named `page_auth` and check its value:

```gleam
fn detect_page_auth(ast: glance.Module) -> #(Bool, Bool) {
  list.find_map(ast.constants, fn(def) {
    let glance.Definition(_, constant) = def
    case constant.name {
      "page_auth" -> {
        let is_required = case constant.value {
          glance.FieldAccess(
            glance.Variable("auth"),
            "Required",
          ) -> True
          _ -> False
        }
        Ok(#(True, is_required))
      }
      _ -> Error(Nil)
    }
  })
  |> result.unwrap(#(False, False))
}
```

Then wire the new fields into the `PageContract` constructor at the bottom of `parse_page`:

```gleam
Ok(PageContract(
  ..existing fields..,
  has_page_auth:,
  page_auth_required:,
  has_authorize:,
))
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/daverapin/projects/opensource/rally && gleam test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/rally/parser.gleam test/rally/parser_auth_test.gleam
git commit -m "Parse page_auth constant and authorize function from page modules"
```

---

### Task 4: Detect auth.gleam per namespace

Teach the main pipeline to find and validate auth modules.

**Files:**
- Modify: `src/rally.gleam`
- Modify: `src/rally/types.gleam`

- [ ] **Step 1: Add AuthConfig type**

In `src/rally/types.gleam`:

```gleam
pub type AuthConfig {
  AuthConfig(
    auth_module: String,
    redirect_url_const: String,
  )
}
```

- [ ] **Step 2: Add auth detection in generate_for_config**

In `src/rally.gleam`, after the `from_session` detection block (around line 285), add auth.gleam detection:

```gleam
let auth_path = dirname(config.pages_root) <> "/auth.gleam"
let auth_config = case simplifile.read(auth_path) {
  Ok(source) -> {
    let auth_module = module_from_src_path(auth_path)
    case string.contains(source, "pub type Identity")
      && string.contains(source, "pub fn resolve")
      && string.contains(source, "pub fn is_authenticated")
      && string.contains(source, "pub const redirect_url")
    {
      True -> option.Some(AuthConfig(
        auth_module:,
        redirect_url_const: auth_module <> ".redirect_url",
      ))
      False -> {
        io.println_error(
          "rally: auth.gleam found at " <> auth_path
          <> " but missing required exports (Identity, resolve, is_authenticated, redirect_url)"
        )
        option.None
      }
    }
  }
  _ -> option.None
}
let has_auth = option.is_some(auth_config)
```

- [ ] **Step 3: Pass auth_config to SSR, WS, and HTTP handler generators**

Update the `ssr_handler.generate(...)` call to include auth_config. This will require updating the function signature in a later task, but for now just add the parameter threading in `rally.gleam`:

```gleam
let ssr_source =
  ssr_handler.generate(
    contracts,
    has_client_context,
    has_from_session,
    from_session_module,
    router_module,
    shell_html,
    config.atoms_module,
    option.Some(config.wire_module),
    case has_client_context {
      True -> option.Some(client_context_module)
      False -> option.None
    },
    auth_config,
  )
```

Do the same for `ws_handler.generate(...)` and the HTTP handler generation.

- [ ] **Step 4: Verify it compiles**

Run: `cd /Users/daverapin/projects/opensource/rally && gleam build`
Expected: FAIL (generator signatures don't accept auth_config yet -- expected, will fix in next tasks)

- [ ] **Step 5: Commit work in progress**

```bash
git add src/rally.gleam src/rally/types.gleam
git commit -m "Detect auth.gleam per namespace, add AuthConfig type"
```

---

### Task 5: SSR handler auth codegen

Generate the auth flow in the SSR handler: resolve → is_authenticated → from_session(identity) → authorize → load(identity) → LoadResult handling.

**Files:**
- Modify: `src/rally/generator/ssr_handler.gleam`

- [ ] **Step 1: Update generate function signature**

Add `auth_config` parameter:

```gleam
pub fn generate(
  page_contracts page_contracts: List(#(ScannedRoute, PageContract)),
  has_client_context has_client_context: Bool,
  has_from_session has_from_session: Bool,
  from_session_module from_session_module: String,
  router_module router_module: String,
  shell_html shell_html: String,
  atoms_module atoms_module: String,
  wire_module wire_module: Option(String),
  client_context_module client_context_module: Option(String),
  auth_config auth_config: Option(AuthConfig),
) -> String {
```

- [ ] **Step 2: Add auth imports to generated code**

When `auth_config` is `Some`, add the auth module import and rally_runtime/auth import:

```gleam
let auth_imports = case auth_config {
  Some(AuthConfig(auth_module:, ..)) ->
    "import " <> auth_module <> " as auth\nimport rally_runtime/auth as rally_auth\n"
  None -> ""
}
```

- [ ] **Step 3: Modify generate_load_arms to inject auth flow**

The key change is in `generate_load_arms`. When auth is enabled, each load arm needs:

1. Call `auth.resolve(server_context, session_id)` and handle Error
2. Check `page_auth_required && !auth.is_authenticated(identity)` → redirect
3. Call `from_session(server_context, session_id, hostname, identity)` (note: identity param added)
4. Check `authorize(server_context, identity)` if page exports it → 403
5. Call `load(args, server_context, identity)` instead of `load(args, server_context)`
6. Handle `LoadResult`: `Page(data, cookies)` renders normally with cookies, `Redirect(url, cookies)` returns 302

Pass `auth_config` through to `generate_load_arms` and modify the arm generation. The `ctx_init` block changes from:

```gleam
// Old (no auth):
let #(client_context, server_context) = from_session_ref.from_session(
  server_context: server_context, session_id: session_id, hostname: hostname)
```

To (with auth):

```gleam
// New (with auth):
case auth.resolve(server_context, session_id) {
  Error(Nil) ->
    response.new(500)
    |> response.set_body(mist.Bytes(bytes_tree.from_string("Auth service unavailable")))
  Ok(identity) -> {
    // is_authenticated check (only for Required pages)
    use <- require_auth(identity)  // generated only for Required pages
    let #(client_context, server_context) = from_session_ref.from_session(
      server_context: server_context, session_id: session_id, hostname: hostname, identity: identity)
    // authorize check (only if page exports authorize)
    use <- check_authorize(server_context, identity)  // generated only if has_authorize
    let data = alias.load(load_args, server_context, identity)
    // ... rest of rendering
  }
}
```

The exact string generation follows the existing pattern in `generate_load_arms` (building strings with `<>` concatenation). Generate the auth checks conditionally based on `contract.page_auth_required` and `contract.has_authorize`.

For LoadResult handling, wrap the existing render logic in a case on the load result:

```gleam
case alias.load(load_args, server_context, identity) {
  rally_auth.Page(data, cookies) -> {
    // existing render logic (init_loaded, view, etc.)
    // apply cookies to response
    apply_cookies(response, cookies)
  }
  rally_auth.Redirect(url, cookies) -> {
    response.new(302)
    |> response.set_header("location", url)
    |> apply_cookies(cookies)
  }
}
```

- [ ] **Step 4: Add apply_cookies helper to generated code**

Generate an `apply_cookies` function in the handler:

```gleam
fn apply_cookies(resp, cookies) {
  list.fold(cookies, resp, fn(resp, cookie) {
    case cookie {
      rally_auth.SetCookie(name, value, max_age) ->
        response.set_header(resp, "set-cookie",
          name <> "=" <> value <> "; Path=/; HttpOnly; SameSite=Lax; Max-Age=" <> int.to_string(max_age))
      rally_auth.ClearCookie(name) ->
        response.set_header(resp, "set-cookie",
          name <> "=; Path=/; HttpOnly; Max-Age=0")
    }
  })
}
```

- [ ] **Step 5: Verify it compiles**

Run: `cd /Users/daverapin/projects/opensource/rally && gleam build`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add src/rally/generator/ssr_handler.gleam
git commit -m "SSR handler auth codegen: resolve, is_authenticated, authorize, LoadResult"
```

---

### Task 6: WS handler auth codegen

Generate auth-aware WebSocket handlers: resolve+from_session on upgrade, page-init auth checks, RPC owning-page verification, reauth.

**Files:**
- Modify: `src/rally/generator/ws_handler.gleam`

- [ ] **Step 1: Update generate function signature**

```gleam
pub fn generate(
  _page_contracts: List(#(ScannedRoute, PageContract)),
  atoms_module: String,
  rpc_dispatch_module: String,
  auth_config: Option(AuthConfig),
  has_from_session: Bool,
  from_session_module: String,
) -> String {
```

- [ ] **Step 2: Modify on_init to resolve identity and call from_session**

When auth is enabled, `on_init` gains `hostname` parameter and stores identity + enriched context:

```gleam
pub fn on_init(
  conn conn: WebsocketConnection,
  server_context server_context: ServerContext,
  session_id session_id: String,
  hostname hostname: String,
) {
  ensure_atoms()
  topics.start()
  // Resolve identity
  let identity = case auth.resolve(server_context, session_id) {
    Ok(identity) -> identity
    Error(Nil) -> {
      // Infrastructure failure -- logged by resolve, we just proceed with unauthenticated
      auth.Unauthenticated  // This won't work because rally doesn't know the Identity type
    }
  }
  // ... store identity, enriched_sc, hostname on connection state
}
```

**Important design note:** Rally doesn't know the app's Identity type, so it can't construct an "unauthenticated" value on `Error(Nil)`. For WS, the spec says to reject the upgrade with HTTP 500 on resolve Error. This rejection happens in `app.gleam` (before the WS upgrade), not in `on_init`. So `on_init` can assume resolve succeeded. The `on_init` signature should receive identity as a parameter:

```gleam
pub fn on_init(
  conn conn: WebsocketConnection,
  server_context server_context: ServerContext,
  session_id session_id: String,
  hostname hostname: String,
  identity identity: auth.Identity,
) {
```

But rally can't import `auth.Identity` directly because it's app-defined. The generated code imports the namespace's auth module. So the generated `on_init` uses the app's auth type:

Generate imports: `import admin/auth` (or whatever the namespace auth module is).

Generate `on_init` with identity and from_session:

```gleam
pub fn on_init(conn, server_context, session_id, hostname, identity) {
  ensure_atoms()
  topics.start()
  let #(client_context, server_context) = client_context_server.from_session(
    server_context:, session_id:, hostname:, identity:)
  let now = // unix timestamp
  let Nil = effect.put_ws_auth_state(conn, server_context, identity, hostname, session_id, now, "")
  // ... topics, selector
}
```

This requires new effect functions for storing auth state. That can be a separate `effect.put_ws_auth_state` or extending the existing `effect.put_ws_state`.

- [ ] **Step 3: Modify page-init to check auth before updating state**

In the frame handler, when `request_id == 0` (page-init), generate:

```gleam
// Parse candidate page
let page = // decoded page name
// Check auth BEFORE updating state
let auth_ok = case page_auth_policy(page) {
  rally_auth.Required -> auth.is_authenticated(identity)
  rally_auth.Optional -> True
}
case auth_ok {
  False -> {
    // Send auth-redirect frame
    let response_frame = wire.encode_auth_redirect(auth.redirect_url)
    mist.send_binary_frame(conn, response_frame)
    mist.continue(state)
  }
  True -> {
    // Check authorize if page exports it
    case check_page_authorize(page, server_context, identity) {
      False -> {
        // Send auth-failure frame
        mist.continue(state)
      }
      True -> {
        // Update state, join topics (existing logic)
        effect.put_ws_state(conn, server_context, page)
        // ...
      }
    }
  }
}
```

The `page_auth_policy` and `check_page_authorize` functions are generated as case expressions mapping page names to their auth policy/authorize calls. Rally generates these from the scanned page contracts.

- [ ] **Step 4: Modify RPC dispatch to verify owning page and check auth**

In the RPC message handler, before dispatching:

```gleam
// Determine owning page (from decoded message, codegen-known)
let owning_page = rpc_dispatch.owning_page(data)
let current_page = effect.get_ws_page()
// Verify owning page matches current page
case owning_page == current_page {
  False -> {
    // Reject: page mismatch
    mist.continue(state)
  }
  True -> {
    // Reauth check
    let #(identity, server_context) = case should_reauth(auth_timestamp) {
      True -> {
        let assert Ok(new_identity) = auth.resolve(server_context, session_id)
        let #(_, new_sc) = from_session(server_context, session_id, hostname, new_identity)
        effect.update_auth_state(new_identity, new_sc, now)
        #(new_identity, new_sc)
      }
      False -> #(identity, server_context)
    }
    // Check page auth policy
    // ... dispatch with identity
    let #(response_data, new_ctx) = rpc_dispatch.handle(server_context:, data:, identity:)
  }
}
```

- [ ] **Step 5: Add owning_page function to RPC dispatch**

This requires libero to generate an `owning_page(data) -> String` function that decodes the RPC message header and returns the page module name. This may need a rally-side wrapper if libero doesn't support it directly. Alternative: include the owning page in the RPC dispatch generated code itself, as each handler case already knows its page.

- [ ] **Step 6: Verify it compiles**

Run: `cd /Users/daverapin/projects/opensource/rally && gleam build`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add src/rally/generator/ws_handler.gleam
git commit -m "WS handler auth codegen: identity on init, page-init auth, RPC ownership check, reauth"
```

---

### Task 7: HTTP handler auth codegen

**Files:**
- Modify: `src/rally/generator/http_handler.gleam`

- [ ] **Step 1: Update generate function signature**

```gleam
pub fn generate(
  _endpoints: List(HandlerEndpoint),
  rpc_dispatch_module: String,
  auth_config: Option(AuthConfig),
  has_from_session: Bool,
  from_session_module: String,
) -> String
```

- [ ] **Step 2: Generate auth flow in handle function**

When auth is enabled, the generated `handle` function wraps the dispatch with auth checks:

```gleam
pub fn handle(
  body body: BitArray,
  server_context server_context: ServerContext,
  session_id session_id: String,
  hostname hostname: String,
) -> Response(ResponseData) {
  let Nil = effect.put_ws_session(session_id)
  case auth.resolve(server_context, session_id) {
    Error(Nil) ->
      response.new(500)
      |> response.set_body(mist.Bytes(bytes_tree.from_string("Auth service unavailable")))
    Ok(identity) -> {
      let #(_, server_context) = from_session.from_session(
        server_context:, session_id:, hostname:, identity:)
      // RPC dispatch with identity
      let #(response_data, _) = rpc_dispatch.handle(
        server_context:, data: body, identity:)
      response.new(200)
      |> response.set_header("content-type", "application/octet-stream")
      |> response.set_body(mist.Bytes(bytes_tree.from_bit_array(response_data)))
    }
  }
}
```

Note: page-level auth (is_authenticated, authorize) for HTTP RPC is enforced inside `rpc_dispatch.handle`, which knows the owning page for each handler. This is generated by libero. The HTTP handler just resolves identity and passes it through.

- [ ] **Step 3: Verify it compiles**

Run: `cd /Users/daverapin/projects/opensource/rally && gleam build`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add src/rally/generator/http_handler.gleam
git commit -m "HTTP handler auth codegen: resolve, from_session, identity threading"
```

---

### Task 8: Thread identity through RPC dispatch

Libero generates the RPC dispatch. When auth is enabled, dispatch needs to receive identity and pass it to server handlers.

**Files:**
- Modify: `src/rally.gleam` (dispatch generation call)
- Potentially modify: libero's dispatch generation

- [ ] **Step 1: Investigate libero's dispatch generation**

Check how libero generates `rpc_dispatch.handle()`. The current signature is:

```gleam
pub fn handle(server_context server_context: ServerContext, data data: BitArray) -> #(BitArray, ServerContext)
```

With auth, it needs to become:

```gleam
pub fn handle(server_context server_context: ServerContext, data data: BitArray, identity identity: auth.Identity) -> #(BitArray, ServerContext)
```

And each handler call needs to pass identity:

```gleam
// Current:
page.server_do_thing(msg, server_context)
// With auth:
page.server_do_thing(msg, server_context, identity)
```

This may require changes to libero's codegen. Check if libero has a mechanism for adding extra parameters to dispatch and handlers. If not, rally can post-process the generated dispatch code (similar to `normalize_rpc_dispatch_context_import` and `normalize_rpc_dispatch_unused_fields`).

- [ ] **Step 2: Implement identity threading**

If libero supports extra params: configure it.
If not: use string replacement on the generated dispatch source to add the identity parameter to the `handle` function signature and all handler calls.

```gleam
// In rally.gleam, after generating sd_source:
let sd_source = case has_auth {
  True -> inject_identity_into_dispatch(sd_source, auth_module)
  False -> sd_source
}
```

The `inject_identity_into_dispatch` function:
1. Adds `import <auth_module> as auth` to the dispatch imports
2. Adds `identity identity: auth.Identity` parameter to `handle()`
3. Adds `, identity` to each handler call in the dispatch case expression

- [ ] **Step 3: Verify it compiles**

Run: `cd /Users/daverapin/projects/opensource/rally && gleam build`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add src/rally.gleam
git commit -m "Thread identity through RPC dispatch to server handlers"
```

---

### Task 9: Update from_session signature in generated code

When auth is enabled, `from_session` gains an `identity` parameter. The generated code that calls `from_session` needs to pass it.

**Files:**
- Modify: `src/rally/generator/ssr_handler.gleam` (already partially done in Task 5)

- [ ] **Step 1: Update from_session call in SSR load arms**

In `generate_load_arms`, when auth is enabled, change the `ctx_init` block:

```gleam
// Old:
let #(client_context, server_context) = from_session_ref.from_session(
  server_context: server_context, session_id: session_id, hostname: hostname)

// New (with auth):
let #(client_context, server_context) = from_session_ref.from_session(
  server_context: server_context, session_id: session_id, hostname: hostname, identity: identity)
```

- [ ] **Step 2: Update from_session call in shell_fn**

The `serve_html_shell` function also calls `from_session`. When auth is enabled, it needs to resolve identity first:

```gleam
fn serve_html_shell(server_context, session_id, hostname) {
  case auth.resolve(server_context, session_id) {
    Error(Nil) ->
      // return 500
    Ok(identity) -> {
      let #(client_context, _) = from_session_ref.from_session(
        server_context:, session_id:, hostname:, identity:)
      // render shell with client_context
    }
  }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `cd /Users/daverapin/projects/opensource/rally && gleam build`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add src/rally/generator/ssr_handler.gleam
git commit -m "Pass identity to from_session in all generated call sites"
```

---

### Task 10: WS effect state extensions

The WS handler needs to store additional state (identity, hostname, auth timestamp) on the connection.

**Files:**
- Modify: `src/rally_runtime/effect.gleam` (or equivalent)

- [ ] **Step 1: Check current effect state storage**

Read `src/rally_runtime/effect.gleam` to understand how `put_ws_state` and `get_stored_server_context` work. They likely use Erlang process dictionary or ETS.

- [ ] **Step 2: Add auth state storage functions**

Add functions to store and retrieve auth-related state alongside the existing WS state:

```gleam
pub fn put_ws_hostname(hostname: String) -> Nil
pub fn get_ws_hostname() -> String

pub fn put_ws_identity(identity: a) -> Nil
pub fn get_ws_identity() -> a

pub fn put_ws_auth_timestamp(ts: Int) -> Nil
pub fn get_ws_auth_timestamp() -> Int
```

These likely use the Erlang process dictionary (same as the existing state storage).

- [ ] **Step 3: Verify it compiles**

Run: `cd /Users/daverapin/projects/opensource/rally && gleam build`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add src/rally_runtime/effect.gleam
git commit -m "Add WS auth state storage: identity, hostname, auth timestamp"
```

---

### Task 11: Integration test with example app

Verify the full pipeline works with a minimal auth-enabled app.

**Files:**
- Create: `test/rally/auth_codegen_test.gleam`

- [ ] **Step 1: Write a codegen snapshot test**

Create a test that sets up a minimal auth-enabled namespace and verifies the generated SSR handler contains the expected auth flow:

```gleam
// test/rally/auth_codegen_test.gleam

pub fn ssr_handler_with_auth_generates_resolve_call_test() {
  // Set up a ScanConfig pointing to test fixtures
  // Create a temporary auth.gleam with the required exports
  // Create a page with page_auth = Required
  // Run the pipeline
  // Assert the generated SSR handler contains:
  //   - "auth.resolve("
  //   - "auth.is_authenticated("
  //   - "from_session(server_context: server_context, session_id: session_id, hostname: hostname, identity: identity)"
  //   - "rally_auth.Page("
  //   - "rally_auth.Redirect("
}
```

- [ ] **Step 2: Run the test**

Run: `cd /Users/daverapin/projects/opensource/rally && gleam test`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add test/rally/auth_codegen_test.gleam
git commit -m "Add auth codegen integration test"
```

---

### Task 12: Backwards compatibility verification

Verify that apps without auth.gleam still work identically.

**Files:**
- No new files

- [ ] **Step 1: Run existing test suite**

Run: `cd /Users/daverapin/projects/opensource/rally && gleam test`
Expected: ALL PASS (no regressions)

- [ ] **Step 2: Test with curling/v3**

Run: `cd /Users/daverapin/projects/curling/v3 && bin/dev`
Expected: Builds and runs without errors (v3 doesn't have auth.gleam yet, so auth codegen shouldn't activate)

- [ ] **Step 3: Commit any fixes**

If any backwards compatibility issues were found and fixed:
```bash
git commit -m "Fix backwards compatibility: auth-free namespaces unchanged"
```

---

## Notes

### Deferred to v3 plan
- Writing `src/admin/auth.gleam` and `src/public/auth.gleam` (app-defined)
- Modifying `from_session` to accept identity parameter (app code)
- Session infrastructure (`src/session.gleam`)
- Auth pages (login, verify, logout, OAuth callbacks)
- `app.gleam` routing changes

### Open implementation questions
- **Libero dispatch identity threading (Task 8):** May need libero changes or rally post-processing. Investigate during implementation.
- **WS owning-page verification (Task 6):** The RPC dispatch knows which handler it's dispatching to. The owning page check could be a generated function or a case expression in the WS handler itself. Decide during implementation.
- **Effect state storage (Task 10):** The exact mechanism depends on what `effect.gleam` currently uses (process dictionary, ETS, etc.). Adapt to the existing pattern.
