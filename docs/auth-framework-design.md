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
| `resolve` | `fn(ServerContext, String) -> Result(Identity, Nil)` | Resolves session_id into an identity. Returns `Ok(Anonymous)` for missing/expired sessions, `Error(Nil)` for infrastructure failures. `resolve` logs its own error details before returning `Error`. |
| `is_authenticated` | `fn(Identity) -> Bool` | Rally calls this for `Required` pages to decide whether to redirect. |
| `redirect_url` | `String` | Where to redirect unauthenticated users. |

Rally imports the app's `Identity` type and threads it through to page functions. Rally never inspects the type's structure.

**Error handling:** `resolve` returns `Result(Identity, Nil)`. `Ok` with an unauthenticated variant (e.g., `Anonymous`) is a normal "no session" state. `Error(Nil)` signals an infrastructure problem (DB unavailable, token verifier broken). The app's `resolve` function is responsible for logging error details (it knows the error type and context). Rally returns HTTP 500 on `Error` with a generic "auth service unavailable" message. It never silently downgrades a broken auth check to "logged out."

### Interaction with from_session

Rally already has `client_context_server.from_session(server_context:, session_id:, hostname:)` which derives ClientContext and an updated ServerContext (including tenant-scoped fields like org_id). Auth's `resolve` handles identity; `from_session` handles everything else (org resolution, theme, translations, tenant scoping).

**Ordering:** `resolve` runs first, then `is_authenticated` check, then `from_session` (which enriches ServerContext with org_id), then `authorize` (which needs the enriched ServerContext for tenant-scoped queries):

```
resolve(server_context, session_id) → Result(Identity, Nil)
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

Pages that need role or category-level access control export an `authorize` function:

```gleam
pub fn authorize(
  server_context: ServerContext,
  identity: Identity,
) -> Bool
```

`authorize` is a page gate: "Can this type of user access this area at all?" It checks roles, org membership, or user categories. It does not check resource-specific permissions (e.g., "can this user access item #5?").

Rally calls `authorize` after `from_session` for pages that export it. Returns `False` = 403 or redirect. This applies to both Required and Optional pages: if `authorize` exists and returns `False`, access is denied regardless of auth policy.

Pages without `authorize` are accessible to any authenticated user (Required) or anyone (Optional).

`authorize` receives the enriched `ServerContext` (with org_id set) so apps can run tenant-scoped queries (e.g., check org membership).

### Resource-Level Authorization

Resource-specific permission checks (e.g., "does this EventManager have access to event #5?", "has this member purchased product #3?") happen in `load` and server handlers, not in `authorize`. These functions have access to route params (from the URL for `load`) or message fields (for server handlers), plus identity and server_context.

```gleam
// src/admin/pages/registration/events/id_/registrations.gleam

// Page gate: any admin with item-management capability
pub fn authorize(server_context, identity) -> Bool {
  case identity {
    Admin(access: FullAccess, ..) | Admin(access: ItemManager(..), ..) -> True
    _ -> False
  }
}

// Resource check: this specific event
pub fn load(server_context, identity) -> LoadResult(Data) {
  let event_id = // from route params
  case identity {
    Admin(access: ItemManager(permissions), ..) ->
      case has_item_permission(permissions, event_id, Registrations) {
        True -> // load data
        False -> Redirect("/admin", [])
      }
    Admin(access: FullAccess, ..) -> // load data
    _ -> Redirect("/admin", [])
  }
}
```

This separation keeps `authorize` simple (one signature, no route params, works identically across SSR, WS, and HTTP RPC) and puts resource-level checks where the resource identity is naturally available.

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
      → if authorize exists and !authorize(enriched_sc, identity): 403
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
        → authorize(enriched_sc, identity): False → 403
      → dispatch to server_* handler with enriched_sc and identity
```

Each HTTP RPC is stateless: resolve and from_session run on every request. The owning page module is known at codegen time (each `server_*` handler belongs to exactly one page module).

### Generated WS Handler Behavior

**On upgrade (HTTP layer):**

The upgrade always proceeds. Auth is page-level, not namespace-level: a namespace with `auth.gleam` can still have Optional pages. Rejecting at upgrade time would block anonymous access to Optional pages.

```
HTTP upgrade request → extract session_id and hostname from request
  → resolve(server_context, session_id)
    → Error: reject upgrade with HTTP 500
    → Ok(identity):
      → from_session(server_context, session_id, hostname, identity) → #(client_context, enriched_sc)
      → proceed with upgrade
      → store identity + enriched_sc + client_context + hostname + auth_timestamp on connection state
```

`resolve` errors reject the upgrade (infrastructure failure, not an auth policy decision). Page-level auth (Required/Optional, authorize) is NOT checked at upgrade time.

`from_session` runs at upgrade time because the HTTP Host header (needed for org/tenant resolution) is not available after the WebSocket handshake. The hostname is stored on connection state so reauth can re-run `from_session` later. The enriched ServerContext and ClientContext are stored on connection state and used for all subsequent auth checks and RPC dispatch.

**On page navigation (page-init frame):**

Auth is checked against the candidate page *before* updating connection state. If auth fails, the current page remains unchanged, avoiding inconsistent state for subsequent RPC dispatch.

```
page-init frame → parse candidate page + route params (do NOT update connection state yet)
  → if Required and !is_authenticated(identity): send auth-redirect frame, keep current page
  → if authorize exists on candidate page:
    → authorize(enriched_sc, identity)
    → False: send auth-failure frame, keep current page
  → auth passed: update current page + route params on connection state
```

Page-level auth policy is enforced at navigation time, not upgrade time. This is where `Required` vs `Optional` matters for WebSocket connections.

**On RPC message:**

RPC auth uses the **owning page** (determined by the decoded message type at codegen time), not the current page from connection state. This prevents a client on an Optional page from calling handlers on a Required page.

```
on_message:
  → if (now - last_auth_check) > reauth_interval:
    → re-resolve identity, update connection state
    → re-run from_session(server_context, session_id, stored_hostname, identity)
      to refresh enriched_sc and client_context (role, org membership, theme may have changed)
  → decode RPC message → determine owning page (codegen-known, from message type)
  → verify owning page matches current page (reject if mismatch)
  → if Required on owning page and !is_authenticated(identity): send auth-redirect frame
  → if authorize exists on owning page:
    → authorize(enriched_sc, identity)
    → False: send auth-failure frame
  → dispatch to server_* handler with enriched_sc and identity
```

**Why owning page, not current page:** rally knows at codegen time which page module defines each `server_*` handler. The message type maps to exactly one page. Using the current page from connection state would be unsafe: a malicious client could navigate to an Optional page, then send RPC frames targeting handlers on Required pages. By checking the owning page, the auth policy of the handler's actual page always applies.

**Why verify current page matches:** in rally's model, RPCs are contextual to the current page. A client should not send RPCs for a page they're not on. Mismatches indicate a bug or a malicious client and are rejected.

**Reauth refresh:** when reauth triggers, both `resolve` and `from_session` re-run. This ensures the connection state reflects current reality: role changes, org membership changes, theme updates, etc. This is slightly more expensive than re-resolving identity alone, but only happens every 30 minutes.

**Reauth interval:** default 30 minutes. No timers, no polling. One integer comparison per incoming message. Only re-resolves when the interval has elapsed.

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

## Implementation Checklist

1. Define `rally.Required` and `rally.Optional` constants, `LoadResult` type, `Cookie` type
2. Scanner: detect auth.gleam per namespace, parse exports (Identity, resolve, is_authenticated, redirect_url)
3. Scanner: detect `pub const page_auth`, `pub fn authorize`, and `pub fn rpc_route_params` on page modules
4. SSR handler codegen: resolve → is_authenticated check → from_session(identity) → authorize(enriched_sc) → load ordering
5. SSR handler codegen: handle LoadResult (Page vs Redirect, apply cookies)
6. HTTP RPC handler codegen: resolve → is_authenticated → from_session → authorize → dispatch with identity
7. WS on-upgrade: resolve + from_session, store identity + enriched_sc + client_context + hostname + auth_timestamp on connection state (reject on resolve Error only)
8. WS handler codegen: enforce page-level auth on page-init frames (Required + is_authenticated, then authorize)
9. WS handler codegen: periodic re-resolve on message (30 min interval)
10. WS handler: send auth-failure / auth-redirect frames on policy failure
11. Error reporting: clear messages for missing auth exports, resolve Error → 500 with generic message

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
