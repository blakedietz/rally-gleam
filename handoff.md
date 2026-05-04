# Lando Framework — Session Handoff

**Repo**: `github.com/pairshaped/lando` (private)
**Branch**: `master` (clean, pushed)
**State**: 88 tests, server + client both compile zero-warning

## What Lando is

Full-stack Gleam + Lustre framework. Write page modules in `src/pages/`, run `bin/dev`, get a web app. Lamdera-style ToServer/ToClient message types, ETF over WebSocket, SSR + hydration for initial load, SPA for navigation.

## What a page looks like

```gleam
// src/pages/counter.gleam
pub type Model { Model(count: Int) }
pub type Msg { UserClickedIncrement; GotServerMsg(ToClient) }
pub type ToServer { Increment; Decrement }
pub type ToClient { CounterNewValue(value: Int) }
pub type ServerModel { ServerModel(count: Int) }

pub fn init() -> #(Model, Effect(Msg))
pub fn update(model, msg) -> #(Model, Effect(Msg))
pub fn view(model) -> Element(Msg)
pub fn server_update(model, msg, ctx) -> #(ServerModel, Effect(ToClient))
pub fn server_init(ctx) -> ServerModel
```

## What was built (6 beans, all done)

| Bean | What |
|---|---|
| Client-side transport | WebSocket handler (ws_handler generator), server_init, push frame queuing, client transport FFI bridge via rpc_ffi.mjs |
| Glance-based parser | AST parsing via glance.module(), full variant/field type extraction, import map building |
| ETF codec generation | Walker.gleam (type graph discovery), codec.gleam generator (types.gleam, codec.gleam, codec_ffi.mjs) |
| Framework async UX | Connection state tracking, reconnect banner, loading bar, toast notifications in generated app |
| Layout system | layout.gleam detection, nearest-ancestor assignment, SSR view wrapping |
| Marmot SQL integration | sql/ scanning, `gleam run -m marmot` subprocess invocation |

## What exists

```
lando/
├── src/
│   ├── lando/              # codegen (scanner, parser, walker, generators)
│   ├── lando_runtime/      # runtime (effect, wire, codec, rpc_ffi.mjs)
│   └── lando_runtime_ffi.erl  # Erlang FFI
├── examples/counter/       # 2-page counter app (Home + About)
├── bin/new                 # project scaffold (Mist v6 compatible)
├── test/                   # 88 tests (scanner, parser, generator, wire, codec)
└── .beans/                 # 6 done, 0 remaining
```

## Generated client package (10 files)

`router.gleam`, `router_ffi.mjs`, `transport.gleam`, `rpc_ffi.mjs`, `decoders_prelude.mjs`, `app.gleam`, `types.gleam`, `codec.gleam`, `codec_ffi.mjs`, `views.gleam`

## Key decisions to remember

- **ToServer/ToClient** naming (not ToBackend/ToFrontend)
- **wire.coerce** is `fn(a) -> b` (fully generic unwitnessed cast)
- **Mist v6 API**: `Request(Connection)` not `Request(BitArray)`, `websocket.handler` takes `WebsocketMessage(a)`, builder pattern for `mist.new |> mist.port |> mist.start`
- **ctx stored in process dict** for WS handler (not captured in closure — broke type inference)
- **Page view extraction**: parser extracts view function via AST span positions, codec adapts (renames Model→HomeModel etc.)
- **Test apps in `./tmp/`** (per CLAUDE.md)

## Lamdera reference

The starter template at `github.com/elm-land/lamdera` shows the pattern we mirror: Bridge.elm (our ToServer), Types.elm (our ToClient), Backend.elm (our server_update), Shared.elm (our layout system).

## What's next

Building a real-world example — a multi-page app with CRUD, Marmot SQL queries, and full round-trip WebSocket communication. The Lamdera realworld app or the elm-spa example app would be good reference points for scope.

Use `./tmp` for test scaffolds, `gleam test` to verify, `echo "a" | gleam run -m birdie` to accept snapshots.
