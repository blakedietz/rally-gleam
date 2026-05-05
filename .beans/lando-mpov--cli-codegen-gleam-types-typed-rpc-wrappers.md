---
# lando-mpov
title: 'CLI codegen: Gleam types + typed RPC wrappers'
status: todo
type: epic
priority: deferred
created_at: 2026-05-04T22:42:56Z
updated_at: 2026-05-05T02:06:28Z
---

Generate Gleam types and typed RPC wrappers for CLI/HTTP clients.

## Approach (2025-05-04)

Build after lando-73tt (hand-written CLI client). Extract the repetitive patterns (typed request/response functions, ETF encoding, error handling) into codegen that produces a client library from the page contracts.

Depends on: lando-ihjg (HTTP handler) and lando-73tt (manual CLI client to learn from).
