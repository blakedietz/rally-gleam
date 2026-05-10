# HTTP RPC Handler-to-Page Ownership Mapping

## Scope

Add per-page auth policy enforcement to Rally's HTTP RPC handler. The handler currently resolves identity and passes it to dispatch but never checks `Required`/`Optional` or `authorize`. This spec covers the ownership mapping both HTTP and WS RPC enforcement need.

## Design

### Ownership mapping

At codegen time, cross-reference Libero's `handler_endpoints` (each has `module_path` pointing to the owning page and `fn_name` identifying the handler, documented as the name without `server_` prefix) with Rally's `contracts` (each has `page_auth_required` and `has_authorize`). Build a mapping from wire variant tag to page auth info.

**Variant tag derivation:** Libero's dispatch extracts the constructor atom name via `wire.variant_tag(msg)`, returning strings like `"server_decrement"`. Rally derives the wire tag from each endpoint as `"server_" <> endpoint.fn_name`. A test must prove this derivation matches the actual `wire.variant_tag` output before the mapping is used in auth enforcement. If the format diverges, the test catches it and the derivation is corrected.

### Type

```gleam
type PageAuthInfo {
  PageAuthInfo(page_module: String, required: Bool, has_authorize: Bool)
}
```

### Generated functions in HTTP handler

**`handler_page_info(variant: String) -> Result(PageAuthInfo, Nil)`** — explicit case on every known variant tag. Unknown variants return `Error(Nil)`. No default/permissive arm.

**`check_page_authorize(page: String, server_context, identity) -> Bool`** — case on page module, one arm per page that exports `authorize`. Calls the page module's `authorize` function directly.

### HTTP handler flow (auth enabled)

```
handle(body, server_context, session_id, hostname)
  → auth.resolve(server_context, session_id)
    → Error(Nil): 500
    → Ok(identity):
      → wire.decode_call(body)
        → Error(_): 400 (malformed body)
        → Ok(#(_, _, msg)):
          → wire.variant_tag(msg) → handler_page_info(variant)
            → Error(Nil): 400 (unknown variant or undecodable body)
            → Ok(PageAuthInfo(page, required, has_authorize)):
              → if required && !auth.is_authenticated(identity): 401
              → from_session(server_context, session_id, hostname, identity)
              → if has_authorize && !check_page_authorize(page, enriched_sc, identity): 403
              → rpc_dispatch.handle(server_context:, data: body, identity:)
```

### Imports

The HTTP handler imports:
- The wire module (for `decode_call`, `variant_tag`) — only when auth is enabled
- Page modules that export `authorize` — for the `check_page_authorize` function
- The auth module (already imported)

No-auth HTTP output stays unchanged.

### Tests

| Test | Expected |
|------|----------|
| Required page + anonymous identity | 401, no dispatch |
| Optional page + anonymous identity | dispatches normally |
| Page with authorize returning false | 403, no dispatch |
| Unknown variant tag | 400, no dispatch |
| Malformed body (decode_call fails) | 400, no dispatch |
| No-auth namespace | output identical to current |
| Wire tag derivation matches `wire.variant_tag` output | pass |

Wire tag format must be verified by test before the mapping is assumed correct.

### Security properties

- Malformed bodies and unknown variants both fail closed (400). Never fall through to dispatch.
- `handler_page_info` has explicit case arms only. No catch-all that passes through.
- Policy enforcement runs before dispatch. Rejected requests never reach handlers.
- `authorize` check runs after `from_session` so it receives the enriched `ServerContext` with tenant scope.
