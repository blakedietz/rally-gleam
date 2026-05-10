# Rally Auth Framework Design

## Problem

Rally apps need authentication and authorization but rally has no opinion on how they work. Apps currently hardcode identity or build ad-hoc session handling in `app.gleam`. There's no convention for protecting pages, resolving user identity, or gating access by role. Server handlers (RPCs) are completely unprotected.

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
| `resolve` | `fn(ServerContext, String) -> Result(Identity, String)` | Resolves session_id into an identity. Returns `Ok(Anonymous)` for missing/expired sessions, `Error(reason)` for infrastructure failures (DB down, etc.). |
| `is_authenticated` | `fn(Identity) -> Bool` | Rally calls this for `Required` pages to decide whether to redirect. |
| `redirect_url` | `String` | Where to redirect unauthenticated users. |

Rally imports the app's `Identity` type and threads it through to page functions. Rally never inspects the type's structure.

**Error handling:** `resolve` returns `Result`. `Ok` with an unauthenticated variant (e.g., `Anonymous`) is a normal "no session" state. `Error` signals an infrastructure problem (DB unavailable, token verifier broken). Rally returns HTTP 500 on `Error`, never silently downgrades a broken auth check to "logged out."

### Interaction with from_session

Rally already has `client_context_server.from_session(server_context:, session_id:, hostname:)` which derives ClientContext and an updated ServerContext. Auth's `resolve` handles identity; `from_session` handles everything else (org resolution, theme, translations, tenant scoping).

**Ordering:** `resolve` runs first. Rally passes the resulting identity to `from_session` as a parameter:

```
resolve(server_context, session_id) → Result(identity, error)
from_session(server_context, session_id, hostname, identity) → #(ClientContext, ServerContext)
```

`from_session`'s signature gains an `identity` parameter. It uses identity to populate identity-related ClientContext fields (email, role, dark_mode preference, etc.) instead of hardcoding or re-looking-up the session. One session lookup, one code path, no duplication.

### Page-Level Auth Declaration

Pages declare their auth requirement via a constant:

```gleam
pub const page_auth = rally.Required   // must be authenticated
pub const page_auth = rally.Optional   // resolve runs, page loads either way
// omitted = same as Optional
```

The constant is named `page_auth` (not `auth`) to avoid colliding with the app's auth module import. The values `rally.Required` and `rally.Optional` come from the rally package.

### Page-Level Authorization

Pages that need finer-grained access control export an `authorize` function:

```gleam
pub fn authorize(
  server_context: ServerContext,
  identity: Identity,
  // route params — rally passes whatever the page's route extracts
) -> Bool
```

Rally calls `authorize` after successful `resolve` for pages that export it. Returns `False` = 403 or redirect. Pages without `authorize` are accessible to any authenticated user (Required) or anyone (Optional).

`authorize` receives `ServerContext` so apps can run DB queries for row-level or resource-scoped permission checks. Rally doesn't know or care what those checks are.

### Generated SSR Handler Behavior

```
HTTP GET → extract session_id from cookie
  → auth.resolve(server_context, session_id)
    → Error: return 500
    → Ok(identity):
      → if Required and !is_authenticated(identity): redirect to redirect_url
      → if authorize exists and !authorize(server_context, identity, params): 403
      → from_session(server_context, session_id, hostname, identity) → #(client_context, server_context)
      → load(server_context, identity) → init_loaded(client_context, data) → view → HTML
```

`load` gains an `identity` parameter when auth.gleam exists. This is a codegen change: rally generates `load(server_context, identity)` instead of `load(server_context)`.

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

### Generated WS Handler Behavior

```
on_init:
  → resolve identity, store on connection state with timestamp
  → if Required and !is_authenticated(identity): reject upgrade (HTTP 302)

on_message (RPC dispatch):
  → if (now - last_auth_check) > reauth_interval:
    → re-resolve identity, update connection state
  → check page-level auth policy for the target page
  → if authorize exists on target page: run authorize(server_context, identity, params)
  → if checks pass: dispatch to server_* handler with identity
  → if checks fail on Required page: close WebSocket
  → if checks fail on Optional page: dispatch with current identity (may be unauthenticated)

on page navigation (page-init frame):
  → re-run authorize for the new page with current identity
  → if authorize fails: send auth-failure frame (client redirects)
```

**RPC authorization:** every server_* handler receives `identity` as a parameter. Rally's generated RPC dispatch enforces the page-level auth policy before dispatching. The handler can do additional business-level checks (e.g., "can this user delete this specific record?").

```gleam
// Page server handler signature (generated by rally)
pub fn server_delete_order(
  msg: DeleteOrder,
  server_context: ServerContext,
  identity: Identity,
) -> Result(response, error)
```

**Page navigation:** when the client navigates between pages within the SPA, rally sends a page-init frame. The WS handler re-runs `authorize` for the new page. This covers the case where a user's permissions change during a session, or where they navigate to a page with stricter requirements.

**Reauth interval:** default 30 minutes. No timers, no polling. One integer comparison per incoming message. Only re-resolves when the interval has elapsed.

### Scanner Changes

During codegen, rally's scanner checks each namespace for:

1. `auth.gleam` exists at namespace root
2. If yes, verify it exports: `Identity` (type), `resolve` (fn), `is_authenticated` (fn), `redirect_url` (const)
3. For each page module, check for `pub const page_auth` declaration and optional `pub fn authorize`
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

**Server handler signatures with auth:**
```gleam
pub fn server_do_thing(
  msg: DoThing,
  server_context: ServerContext,
  identity: Identity,
) -> Result(response, error)
```

Identity is threaded to every server handler. The handler can use it for business-level authorization or ignore it if the page-level policy is sufficient.

## Implementation Checklist

1. Define `rally.Required` and `rally.Optional` constants, `LoadResult` type, `Cookie` type
2. Scanner: detect auth.gleam per namespace, parse exports
3. Scanner: detect `pub const page_auth` and `pub fn authorize` on page modules
4. SSR handler codegen: insert resolve → from_session ordering, pass identity to both
5. SSR handler codegen: insert is_authenticated/authorize checks
6. SSR handler codegen: handle LoadResult (Page vs Redirect, apply cookies)
7. RPC dispatch codegen: thread identity to all server_* handlers
8. RPC dispatch codegen: enforce page-level auth policy before dispatch
9. WS handler codegen: resolve on init, store identity + timestamp on connection state
10. WS handler codegen: periodic re-resolve on message
11. WS handler codegen: re-run authorize on page-init frames
12. WS handler: reject upgrade or close connection on auth failure (Required pages only)
13. Error reporting: clear messages for missing auth exports, resolve errors

## Design Principles

- **Rally is generic.** It calls hooks, threads types, and acts on booleans. It never imports app domain types or makes domain decisions.
- **Backwards compatible.** No auth.gleam = no auth. Existing apps don't break.
- **Convention over configuration.** File presence and export signatures are the configuration. No TOML knobs for auth.
- **App owns the identity.** The type, what it contains, how it's resolved, what "authenticated" means: all app decisions.
- **Authorization is page-local.** Each page knows its own access rules. No centralized route-to-role mapping to maintain.
- **One identity flow.** `resolve` is the single source of identity. `from_session` consumes it. RPC dispatch threads it. No parallel lookups, no inconsistent state.
- **Fail loud on infrastructure errors.** Missing sessions are normal (anonymous). Broken auth checks are 500s.
