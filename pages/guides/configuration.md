# Configuration

Rally reads its configuration from `gleam.toml` under `[[tools.rally.clients]]`. Each entry describes one browser app namespace.

```toml
[[tools.rally.clients]]
namespace = "public"
route_root = "/"
protocol = "etf"
```

- `namespace` names the client. Page modules live under `src/<namespace>/pages/` and generated code lands in `src/generated/<namespace>/`.
- `route_root` sets the URL prefix for all routes in this client.
- `protocol` selects the wire format (see [Protocols](#protocols) below). Defaults to `"etf"` if omitted.

## Generated server files

When codegen runs, Rally writes the following files into `src/generated/<namespace>/`:

| File | Purpose |
| --- | --- |
| `router.gleam` | Route type, parser, path builder, and `href` |
| `page_dispatch.gleam` | Per-route page init, update, and view dispatch |
| `rpc_dispatch.gleam` | Server RPC dispatch |
| `ssr_handler.gleam` | Server-side render entry |
| `ws_handler.gleam` | WebSocket handler |
| `http_handler.gleam` | HTTP RPC handler |
| `protocol_wire.gleam` | Protocol facade |

These files are derived from your page modules. You don't edit them directly; re-running codegen overwrites them.

## Generated client package

Rally also writes a standalone client package under `.generated_clients/<namespace>/`. This package has its own `gleam.toml` (targeting JavaScript), a generated SPA entry point, transport layer, tree-shaken copies of your page modules, and the codec for whatever protocol you selected.

The server project remains the source of truth. The client package is an output artifact, rebuilt on every codegen pass.

## Protocols

The `protocol` field in a client entry selects the wire format used between client and server.

- **ETF** (Erlang Term Format) is the default. It maps closely to BEAM terms. Use it when your clients are browser SPAs and you do not need to inspect payloads by eye.
- **JSON** is available for clients and tools that need readable envelopes, or when you want to inspect traffic in browser devtools.

The generated `protocol_wire.gleam` facade adapts at compile time based on the selected protocol. Your application code never branches on protocol at runtime.

```toml
[[tools.rally.clients]]
namespace = "public"
protocol = "json"
```

## Multiple clients

You can define more than one `[[tools.rally.clients]]` entry. Each gets its own namespace, route root, and protocol. Codegen runs once per entry, producing a separate set of generated server files and a separate client package.

A common setup: one client for the public site and another for an admin panel.

```toml
[[tools.rally.clients]]
namespace = "public"
route_root = "/"

[[tools.rally.clients]]
namespace = "admin"
route_root = "/admin"
protocol = "json"
```

## Environment

Rally checks the `APP_ENV` environment variable at startup.

- `APP_ENV=dev` is the default. Session cookies are set without the `Secure` flag (so `localhost` works), and console output is verbose.
- `APP_ENV=prod` enables secure session cookies and quieter logging. Set this in production.

```sh
APP_ENV=prod gleam run
```
