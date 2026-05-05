---
# lando-ihjg
title: 'HTTP handler: stateless ETF endpoint for non-WebSocket clients'
status: todo
type: epic
priority: deferred
created_at: 2026-05-04T22:42:56Z
updated_at: 2026-05-05T02:28:17Z
blocked_by:
    - lando-3gid
---

Stateless ETF endpoint for non-WebSocket clients (CLI, other Gleam services).

## Design direction (2025-05-04)

Endpoint: POST /rpc with ETF body, same call envelope format {page_name, request_id, msg}.

Flow: decode call envelope, set up process dict for effects, dispatch via server_dispatch, drain outgoing frames, return as ETF response.

Session: from Authorization header (CLI) or cookie (browser). Both supported.

Response: ETF-encoded push frame payloads.

Generated as src/generated/http_handler.gleam, same pattern as ws_handler.

## Open question

Server TEA (ServerModel/server_init/server_update) may be removed entirely. If the server side becomes a simple `handle(msg, server_context) -> Effect(ToClient)`, the HTTP handler is trivial: call handle, drain effects, return. No init + update dance, no throwaway model. Decision pending.

## Ordering

This is a prerequisite for lando-73tt (realworld CLI client) and lando-mpov (CLI codegen). Build HTTP handler first, then hand-write a CLI client against it, then extract codegen patterns.
