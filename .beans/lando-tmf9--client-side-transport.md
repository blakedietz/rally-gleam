---
# lando-tmf9
title: Client-side transport
status: done
type: task
created_at: 2026-05-03T14:34:11Z
updated_at: 2026-05-03T15:55:00Z
---

Wire up send_to_backend/send_to_client with real WebSocket transport using rpc_ffi.mjs

## What was done

- Added `server_init` to page contract (parser detection, PageContract field, generator output)
- Updated `server_dispatch.gleam` generator to produce `init_server_model` function
- Created `ws_handler.gleam` generator — WebSocket frame loop with ETF call envelope decoding, dispatch to server_update, response/push frame sending
- Updated `effect.gleam` — `send_to_client`/`broadcast` now encode push frames via process dictionary accumulator
- Added Erlang FFI helpers: `put_ws_state`, `push_outgoing_frame`, `drain_outgoing_frames`
- Updated client generator to produce `transport.gleam` (FFI bridge to rpc_ffi.mjs), `rpc_ffi.mjs` (copied from lando_runtime), and updated `app.gleam` with WebSocket init
- Updated `bin/new` scaffold with WebSocket upgrade handler, static JS serving, and `server_init` in page template
- Fixed `lando_cli_ffi.erl` — `unique_id` and `find_executable` return type mismatches
- Updated `ScanConfig` with `output_ws` and `lando_package_path` fields
- Updated snapshot tests and llms.txt
