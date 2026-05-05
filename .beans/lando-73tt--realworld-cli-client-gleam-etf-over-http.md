---
# lando-73tt
title: 'Realworld: CLI client (Gleam, ETF over HTTP)'
status: todo
type: task
priority: deferred
created_at: 2026-05-04T22:45:59Z
updated_at: 2026-05-05T02:06:21Z
---

Hand-write a CLI client for the realworld app using Gleam + ETF over HTTP.

## Approach (2025-05-04)

Work backwards from usage: build the CLI client manually against the HTTP handler (lando-ihjg), then extract patterns into codegen (lando-mpov).

Depends on: lando-ihjg (HTTP handler must exist first).

## Open question

If server TEA is removed, the CLI just sends ToServer messages and receives ToClient responses over HTTP. No model lifecycle to worry about.
