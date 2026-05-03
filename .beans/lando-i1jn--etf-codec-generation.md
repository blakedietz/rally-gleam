---
# lando-i1jn
title: ETF codec generation
status: done
type: task
created_at: 2026-05-03T14:34:11Z
updated_at: 2026-05-03T17:45:00Z
---

Generate per-page ETF encode/decode from ToBackend/ToFrontend types

## What was done

- Ported `walker.gleam` from libero — BFS type graph walker that discovers all reachable custom types from ToBackend/ToFrontend seed types
- Created `generator/codec.gleam` — generates client codec files:
  - `codec_ffi.mjs` — JS typed decoders from discovered types (adapted from libero's codegen_decoders)
  - `types.gleam` — mirrored page ToBackend/ToFrontend types with full field type info
  - `codec.gleam` — typed encode/decode wrapper functions per page
- Updated `lando.gleam` to run the walker + codec generator pipeline
- Copies `decoders_prelude.mjs` to client package (needed by codec_ffi.mjs)
- Made parser import map builders public for walker reuse
