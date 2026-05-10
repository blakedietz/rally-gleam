# Rally Auth Framework Design

## Problem

Rally apps need authentication and authorization but rally has no opinion on how they work. Apps currently hardcode identity or build ad-hoc session handling in `app.gleam`. There's no convention for protecting pages, resolving user identity, or gating access by role.

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
| `resolve` | `fn(ServerContext, String) -> Identity` | Resolves session_id into an identity. Always succeeds (returns an unauthenticated variant when no valid session exists). |
| `is_authenticated` | `fn(Identity) -> Bool` | Rally calls this for `Required` pages to decide whether to redirect. |
| `redirect_url` | `String` | Where to redirect unauthenticated users. |

Rally imports the app's `Identity` type and threads it through to page functions. Rally never inspects the type's structure.

### Page-Level Auth Declaration

Pages declare their auth requirement via a constant:

```gleam
pub const auth = auth.Required   // must be authenticated
pub const auth = auth.Optional   // resolve runs, page loads either way
// omitted = same as Optional
```

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
  → auth.resolve(server_context, session_id) → identity
  → if Required and !is_authenticated(identity): redirect to redirect_url
  → if authorize exists and !authorize(server_context, identity, params): 403
  → else: load(server_context, identity) → init_loaded → view → HTML
```

`load` gains an `identity` parameter when auth.gleam exists. This is a codegen change: rally generates `load(server_context, identity)` instead of `load(server_context)`.

### Generated WS Handler Behavior

```
on_init: resolve identity, store on connection state
on_message: if (now - last_auth_check) > reauth_interval:
  → re-resolve identity
  → if no longer authenticated: close WebSocket
  → else: update last_auth_check timestamp, proceed
```

Re-authorization is lazy: no timers, no polling. One integer comparison per incoming message. Only re-resolves when the interval has elapsed. Default interval: 30 minutes.

### SSR Cookie Support

Auth pages (login verification, logout, OAuth callbacks) need to set or clear session cookies in the HTTP response. Rally's SSR load handlers currently return page data only.

New capability: load handlers can return cookie instructions alongside page data. Rally's generated SSR handler applies them to the HTTP response before sending.

Proposed API (TBD during implementation):

```gleam
// Option A: wrapper return type
pub fn load(server_context, identity) -> LoadResult(Data) {
  LoadResult(data: my_data, cookies: [SetCookie("rally_session", token)])
}

// Option B: effect-based
pub fn load(server_context, identity) -> #(Data, List(Cookie)) {
  #(my_data, [set_cookie("rally_session", token)])
}
```

### SSR Redirect Support

Some pages are pure server-side redirects with no rendering (e.g., OAuth callbacks, email verification landing pages). Load handlers need a way to return a redirect response instead of page data.

```gleam
pub fn load(server_context, identity) -> Result(Data, Redirect) {
  // process callback, create session...
  Error(Redirect(to: "/admin", cookies: [set_cookie(...)]))
}
```

The exact API should compose cleanly with cookie support. Both are response-level concerns that load handlers need access to.

### Scanner Changes

During codegen, rally's scanner checks each namespace for:

1. `auth.gleam` exists at namespace root
2. If yes, verify it exports: `Identity` (type), `resolve` (fn), `is_authenticated` (fn), `redirect_url` (const)
3. For each page module, check for `pub const auth` declaration and optional `pub fn authorize`
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
pub fn load(server_context: ServerContext, identity: Identity) -> Data
```

The `identity` parameter is added to `load`. Pages access identity data through their model (populated in `init_loaded`). The `view` function signature doesn't change since identity flows through the model.

## Implementation Checklist

1. Scanner: detect auth.gleam per namespace, parse exports
2. Scanner: detect `pub const auth` and `pub fn authorize` on page modules
3. SSR handler codegen: insert resolve/is_authenticated/authorize calls
4. SSR handler codegen: pass identity to load
5. SSR handler: support cookie setting on response
6. SSR handler: support redirect returns from load
7. WS handler codegen: resolve on init, periodic re-resolve
8. WS handler: close connection on re-auth failure
9. Error reporting: clear messages for missing auth exports

## Design Principles

- **Rally is generic.** It calls hooks, threads types, and acts on booleans. It never imports app domain types or makes domain decisions.
- **Backwards compatible.** No auth.gleam = no auth. Existing apps don't break.
- **Convention over configuration.** File presence and export signatures are the configuration. No TOML knobs for auth.
- **App owns the identity.** The type, what it contains, how it's resolved, what "authenticated" means: all app decisions.
- **Authorization is page-local.** Each page knows its own access rules. No centralized route-to-role mapping to maintain.
