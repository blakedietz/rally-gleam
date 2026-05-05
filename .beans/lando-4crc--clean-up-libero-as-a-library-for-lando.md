---
# lando-4crc
title: Clean up libero as a library for lando
status: todo
type: epic
created_at: 2026-05-05T02:28:04Z
updated_at: 2026-05-05T02:28:04Z
---

Strip libero down to its core value as an RPC plumbing library. Libero owns: scanner (handler discovery via server_ prefix + signature), field_type, walker, codegen_dispatch, wire.gleam + FFI (ETF encode/decode, call envelopes, frame tagging), rpc_ffi.mjs (JS ETF codec), decoders_prelude.mjs, codec.gleam (base64 ETF for flags). Strip: client stub generation, multi-client/shared directory, server scaffolding, SSR, rpc_config, push delivery. Scanner convention: pub fn server_* with ServerContext param + Result return. Strips prefix for wire/stub name. Two return shapes: Result(ok, err) for reads, #(Result(ok, err), ServerContext) for writes. Boundary: libero defines wire format, lando decides delivery.
