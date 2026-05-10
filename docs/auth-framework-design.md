# Rally Auth Framework Design

## Problem

Rally apps need authentication and authorization but rally has no opinion on how they work. Apps currently hardcode identity or build ad-hoc session handling in `app.gleam`. There's no convention for protecting pages, resolving user identity, or gating access by role. Server handlers (RPCs) are completely unprotected across both WebSocket and HTTP transports.

## Design

### Convention-Based Auth Module

Each client namespace may have an `auth.gleam` at its root. Rally scans for it during codegen and generates handler plumbing that calls into it.

```
src/admin/auth.gleam     → admin namespace auth
src/public/auth.gleam    → public namespace auth
```

If no `auth.gleam` exists for a namespace, rally generates handlers without auth (backwards compatible, current behavior).

### Auth Module Contract

The auth module must export:

| Export | Signature | Purpose |
|--------|-----------|---------|
| `Identity` | type | App-defined identity type. Opaque to rally. |
| `AuthError` | type | App-defined error type for infrastructure failures. Opaque to rally. |
| `resolve` | `fn(ServerContext, String) -> Result(Identity, AuthError)` | Resolves session_id into an identity. Returns `Ok(Anonymous)` for missing/expired sessions, `Error(...)` for infrastructure failures (DB down, etc.). |
| `is_authenticated` | `fn(Identity) -> Bool` | Rally calls this for `Required` pages to decide whether to redirect. |
| `redirect_url` | `String` | Where to redirect unauthenticated users. |

Rally imports the app's `Identity` type and threads it through to page functions. Rally never inspects the type's structure.

**Error handling:** `resolve` returns `Result` with an app-defined `AuthError` type. `Ok` with an unauthenticated variant (e.g., `Anonymous`) is a normal "no session" state. `Error` signals an infrastructure problem (DB unavailable, token verifier broken). Rally returns HTTP 500 on `Error` and logs the error's string representation. It never silently downgrades a broken auth check to "logged out."

### Interaction with from_session

Rally already has `client_context_server.from_session(server_context:, session_id:, hostname:)` which derives ClientContext and an updated ServerContext (including tenant-scoped fields like org_id). Auth's `resolve` handles identity; `from_session` handles everything else (org resolution, theme, translations, tenant scoping).

**Ordering:** `resolve` runs first, then `is_authenticated` check, then `from_session` (which enriches ServerContext with org_id), then `authorize` (which needs the enriched ServerContext for tenant-scoped queries):

```
resolve(server_context, session_id) → Result(identity, auth_error)
  → Error: return 500
  → Ok(identity):
    → if Required and !is_authenticated(identity): redirect to redirect_url
    → from_session(server_context, session_id, hostname, identity) → #(client_context, enriched_server_context)
    → if authorize exists: authorize(enriched_server_context, identity, params)
      → False: 403 (regardless of Required or Optional)
    → load(enriched_server_context, identity) → LoadResult
```

`from_session`'s signature gains an `identity` parameter. It uses identity to populate identity-related ClientContext fields (email, role, dark_mode preference, etc.) instead of hardcoding or re-looking-up the session. One session lookup, one code path, no duplication.

**Why authorize runs after from_session:** `authorize` may need `org_id` or other tenant-scoped data on ServerContext for row-level permission queries. `from_session` is what resolves the org from the hostname and sets org_id. Running authorize before from_session would give it an un-enriched ServerContext with org_id = 0.

### Page-Level Auth Declaration

Pages declare their auth requirement via a constant:

```gleam
pub const page_auth = rally.Required   // must be authenticated
pub const page_auth = rally.Optional   // resolve runs, page loads either way
// omitted = same as Optional
```

The constant is named `page_auth` (not `auth`) to avoid colliding with the app's auth module import. The values `rally.Required` and `rally.Optional` come from the rally package.

**What Optional means:** Optional skips the `is_authenticated` redirect check. It does NOT skip `authorize`. If a page is Optional and exports `authorize`, anonymous users reach the authorize check (since they pass the "no is_authenticated gate" step), and authorize decides whether they can proceed. This lets pages like "spares contact info" be Optional (anonymous users see a limited view) while still using authorize to gate specific content for members.

### Page-Level Authorization

Pages that need finer-grained access control export an `authorize` function:

```gleam
pub fn authorize(
  server_context: ServerContext,
  identity: Identity,
  // route params — rally passes whatever the page's route extracts
) -> Bool
```

Rally calls `authorize` after `from_session` for pages that export it. Returns `False` = 403 or redirect. This applies to both Required and Optional pages: if `authorize` exists and returns `False`, access is denied regardless of auth policy.

Pages without `authorize` are accessible to any authenticated user (Required) or anyone (Optional).

`authorize` receives the enriched `ServerContext` (with org_id set) so apps can run tenant-scoped DB queries for row-level or resource-scoped permission checks.

### Load Result Type

Load handlers return `LoadResult(data)` which supports page data, redirects, and cookies in a single type:

```gleam
pub type LoadResult(data) {
  Page(data: data, cookies: List(Cookie))
  Redirect(url: String, cookies: List(Cookie))
}
```

**Page:** normal page load with optional cookies (most pages return `Page(data, [])`)
**Redirect:** server-side redirect with optional cookies (auth callbacks, logout, dev_login)

Rally's generated SSR handler pattern-matches on the result:
- `Page` -> render the page, apply cookies to the HTTP response
- `Redirect` -> return HTTP 302, apply cookies, no rendering

```gleam
pub type Cookie {
  SetCookie(name: String, value: String, max_age: Int)
  ClearCookie(name: String)
}
```

### Generated SSR Handler Behavior

```
HTTP GET → extract session_id from cookie
  → auth.resolve(server_context, session_id)
    → Error: return 500, log error
    → Ok(identity):
      → if Required and !is_authenticated(identity): redirect to redirect_url
      → from_session(server_context, session_id, hostname, identity) → #(client_context, enriched_sc)
      → if authorize exists and !authorize(enriched_sc, identity, params): 403
      → load(enriched_sc, identity) → LoadResult
        → Page(data, cookies): render page, apply cookies
        → Redirect(url, cookies): HTTP 302, apply cookies
```

`load` gains an `identity` parameter when auth.gleam exists. This is a codegen change: rally generates `load(server_context, identity)` instead of `load(server_context)`.

### Generated HTTP RPC Handler Behavior

POST `/rpc` follows the same auth flow as SSR, run per-request:

```
HTTP POST /rpc → extract session_id from cookie → parse RPC message
  → auth.resolve(server_context, session_id)
    → Error: return 500
    → Ok(identity):
      → determine owning page module (rally knows this at codegen time)
      → if Required and !is_authenticated(identity): return 401
      → from_session(server_context, session_id, hostname, identity) → #(_, enriched_sc)
      → if authorize exists on owning page:
        → extract route params from message (see "RPC Route Params" below)
        → authorize(enriched_sc, identity, params): False → 403
      → dispatch to server_* handler with enriched_sc and identity
```

Each HTTP RPC is stateless: resolve and from_session run on every request. The owning page module is known at codegen time (each `server_*` handler belongs to exactly one page module).

### Generated WS Handler Behavior

**Pre-upgrade auth check:**

Auth for WebSocket connections happens before the upgrade, in the HTTP routing layer. `app.gleam` resolves identity from the upgrade request's cookies. If the namespace requires auth (has auth.gleam) and `is_authenticated` returns `False`, the upgrade is rejected with an HTTP redirect or 401. No WebSocket connection is opened.

If auth succeeds (or the namespace has no auth.gleam), the upgrade proceeds. Identity and a timestamp are stored on the connection state.

```
HTTP upgrade request → extract session_id from cookie
  → resolve(server_context, session_id)
  → if Required namespace and !is_authenticated(identity): reject upgrade (HTTP 302 or 401)
  → proceed with upgrade, store identity + auth_timestamp on connection state
```

**On page navigation (page-init frame):**

```
page-init frame → update current page + route params on connection state
  → if authorize exists on new page:
    → authorize(enriched_sc, identity, current_route_params)
    → False: send auth-failure frame (client handles redirect)
```

**On RPC message:**

```
on_message:
  → if (now - last_auth_check) > reauth_interval:
    → re-resolve identity, update connection state
    → if is_authenticated was true, now false: close connection
  → determine owning page (current page from connection state)
  → if authorize exists: authorize(enriched_sc, identity, current_route_params)
    → False: send auth-failure frame
  → dispatch to server_* handler with identity
```

**Reauth interval:** default 30 minutes. No timers, no polling. One integer comparison per incoming message. Only re-resolves when the interval has elapsed.

### RPC Route Params

`authorize` may need route params (e.g., item_id) to do row-level checks. How params are available depends on the transport:

**WebSocket:** the connection tracks the current page and its route params from the latest page-init frame. RPC dispatch passes these to `authorize`. This works because WS RPCs are contextual to the current page.

**HTTP RPC:** there's no "current page" context. The RPC message itself carries resource identifiers (e.g., `DeleteOrder(order_id: 5)`). For authorize to work, the page module can export an optional function:

```gleam
pub fn rpc_route_params(msg: ServerMsg) -> RouteParams {
  case msg {
    DeleteOrder(order_id:, ..) -> RouteParams(id: order_id)
    _ -> RouteParams(id: 0)
  }
}
```

Rally calls `rpc_route_params` to extract params from the message before calling `authorize`. If the page doesn't export `rpc_route_params`, authorize receives empty params. This makes HTTP RPC authorize opt-in per page.

### Server Handler Signatures

When auth.gleam exists, server handler signatures gain `identity`:

```gleam
pub fn server_delete_order(
  msg: DeleteOrder,
  server_context: ServerContext,
  identity: Identity,
) -> Result(response, error)
```

Identity is threaded to every server handler. The handler can use it for business-level authorization or ignore it if the page-level policy is sufficient.

### Scanner Changes

During codegen, rally's scanner checks each namespace for:

1. `auth.gleam` exists at namespace root
2. If yes, verify it exports: `Identity` (type), `AuthError` (type), `resolve` (fn), `is_authenticated` (fn), `redirect_url` (const)
3. For each page module, check for `pub const page_auth` declaration, optional `pub fn authorize`, and optional `pub fn rpc_route_params`
4. Generate handler code accordingly

Missing exports from auth.gleam should produce a clear codegen error.

### Page Function Signature Changes

When auth.gleam exists for a namespace, page function signatures change:

**Without auth (current):**
```gleam
pub fn load(server_context: ServerContext) -> Data
```

**With auth:**
```gleam
pub fn load(server_context: ServerContext, identity: Identity) -> LoadResult(Data)
```

The `identity` parameter is added to `load`, and the return type becomes `LoadResult(Data)`. Pages access identity data through their model (populated in `init_loaded`). The `view` function signature doesn't change since identity flows through the model.

## Implementation Checklist

1. Define `rally.Required` and `rally.Optional` constants, `LoadResult` type, `Cookie` type
2. Scanner: detect auth.gleam per namespace, parse exports (Identity, AuthError, resolve, is_authenticated, redirect_url)
3. Scanner: detect `pub const page_auth`, `pub fn authorize`, and `pub fn rpc_route_params` on page modules
4. SSR handler codegen: resolve → is_authenticated check → from_session(identity) → authorize(enriched_sc) → load ordering
5. SSR handler codegen: handle LoadResult (Page vs Redirect, apply cookies)
6. HTTP RPC handler codegen: resolve → is_authenticated → from_session → authorize (with rpc_route_params) → dispatch with identity
7. WS pre-upgrade: resolve + is_authenticated check before WebSocket upgrade in HTTP routing layer
8. WS handler codegen: store identity + auth_timestamp on connection state
9. WS handler codegen: re-run authorize on page-init frames with current route params
10. WS handler codegen: periodic re-resolve on message (30 min interval)
11. WS handler: send auth-failure frame on authorize failure (client handles redirect)
12. Error reporting: clear messages for missing auth exports, resolve errors → 500

## Design Principles

- **Rally is generic.** It calls hooks, threads types, and acts on booleans. It never imports app domain types or makes domain decisions.
- **Backwards compatible.** No auth.gleam = no auth. Existing apps don't break.
- **Convention over configuration.** File presence and export signatures are the configuration. No TOML knobs for auth.
- **App owns the identity.** The type, what it contains, how it's resolved, what "authenticated" means: all app decisions.
- **Authorization is page-local.** Each page knows its own access rules. No centralized route-to-role mapping to maintain.
- **One identity flow.** `resolve` is the single source of identity. `from_session` consumes it. RPC dispatch threads it. No parallel lookups, no inconsistent state.
- **Auth covers all surfaces.** SSR page loads, WebSocket RPCs, HTTP RPCs, and WS page navigation all run through the same auth/authorize flow.
- **Fail loud on infrastructure errors.** Missing sessions are normal (anonymous). Broken auth checks are 500s.
- **Optional means skip is_authenticated, not skip authorize.** If a page exports authorize, it's enforced regardless of auth policy.
