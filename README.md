# Rally

A full-stack web framework for Gleam on the BEAM. Write page modules, run the codegen, get a working web app with real-time client-server messaging over WebSockets.

## Quick start

```sh
bin/new my_app
cd my_app && bin/dev
```

`bin/dev` runs codegen, builds the JS client, and starts the server on port 8080.

## Design decisions

### Single source, generated client

You write one Gleam project. Page modules contain both client and server code in the same file. The codegen reads your source, extracts the client-side types and functions, and generates a complete client package (its own `gleam.toml`, dependencies, transport layer, codec). No shared library to keep in sync, no three-project workspace, no "which project does this type belong in?" decisions. The server source is the single source of truth.

### Colocation-first

Types, state, and logic live in the page file until they need to be shared. A page module contains its client model, server model, messages in both directions, and all the update/view functions. There's no upfront shared domain layer. Extract when duplication becomes a maintenance problem, not before.

### SQLite ships with every app

Every rally app gets SQLite with WAL mode, busy timeout, and foreign keys enabled. No database selection step, no adapter pattern, no connection pooling config. One process, one file, one less thing to debug. Marmot generates type-safe query functions from `.sql` files via live SQLite introspection.

### ETF over the wire

Client-server messages are serialized as ETF (Erlang External Term Format), not JSON. ETF is the BEAM's native binary format: atoms, tuples, and tagged variants survive the round trip without a separate schema definition layer. The codegen produces JS encode/decode functions that match the Gleam types exactly.

### File-based routing with codegen

Routes are the filesystem. `src/pages/home_.gleam` is `/`, `src/pages/products/id_.gleam` is `/products/:id`. The codegen scans page modules, discovers `server_*` handlers via libero, and produces router, RPC dispatch, SSR handler, WebSocket handler, HTTP handler, and the full client package with typed RPC stubs. No runtime reflection, no macro system, no build plugins.

### Lamdera-inspired, not Lamdera-bound

Lamdera's architecture is the starting point: explicit server handler types as the client-server contract, server-side state per connection, TEA on both sides. But Gleam on the BEAM gives us OTP processes, pg groups, and native concurrency that Elm can't access. Where the BEAM offers a better primitive, we take it (four-level broadcast via pg, process dictionary for handler state, native ETF codec, libero for RPC dispatch).

### Four-level broadcast

Server-to-client messaging at four scopes, all built on OTP pg process groups:

| Effect | Who receives it |
|---|---|
| `send_to_client(msg)` | One specific connection |
| `broadcast_to_session(msg)` | Every tab in the same browser session |
| `broadcast_to_page(msg)` | Every connection viewing the same page |
| `broadcast_to_app(msg)` | Every connection to the app |

Connections auto-subscribe to their relevant topics on WebSocket connect. No pub/sub configuration needed.

### SSR with hydration

First request renders full HTML server-side with the model embedded as flags. The client reads the flags, boots Lustre, and takes over as a SPA. Subsequent navigations are client-side only (modem handles pushState).

### The page contract

A page module exports a fixed set of types and functions. The codegen enforces the shape:

```gleam
// Client (TEA)
pub type Model { ... }
pub type Msg { ... }
pub fn init() -> #(Model, Effect(Msg))
pub fn update(_cc, model, msg) -> #(Model, Effect(Msg))
pub fn view(_cc, model) -> Element(Msg)

// Server handlers (one per RPC call)
pub type ServerDoSomething { ServerDoSomething(field: String) }
pub fn server_do_something(
  msg msg: ServerDoSomething,
  server_context server_context: ServerContext,
) -> Result(ReturnType, ErrorType)
```

Server handlers are discovered by libero: any `pub fn server_*` that takes a single-variant message type and `ServerContext` becomes an RPC endpoint. The message type doubles as the client's constructor:

```gleam
rally_effect.rpc(ServerDoSomething(field: "value"), on_response: GotResult)
```

The return type of the handler determines the response type for the `on_response` callback.

For SSR, a page can optionally export:

```gleam
pub fn load(server_context: ServerContext) -> Model
pub fn init_loaded(data, ...) -> #(Model, Effect(Msg))
```

## Rally vs Lustre server components

These are two different architectures for building full-stack Lustre apps. Neither is strictly better.

**Lustre server components** run the TEA loop on the server: model, update, and view all execute server-side. On first connect, the server sends the full VDOM. On each subsequent update, it diffs the old and new VDOM and sends only the patch. The client is a thin JS shell (~10KB) that applies DOM patches and forwards events back to the server.

**Rally** runs TEA on both sides. The client handles UI state locally (model, update, view run in the browser). The server has handler functions, and only gets involved when the client explicitly calls an RPC. The server responds with domain data, not VDOM patches.

| | Lustre server components | Rally |
|---|---|---|
| **Where UI runs** | Server (model + update + view) | Client (model + update + view) |
| **What goes over the wire** | VDOM patches down, DOM events up | Domain messages in both directions |
| **Interaction latency** | Every event round-trips to server | Local state changes are instant |
| **Server memory** | Model + VDOM + event handler cache (shared across subscribers of same component) | ServerContext per connection (stateless handlers) |
| **Client JS bundle** | Minimal (DOM patcher, ~10KB) | Full app logic (Lustre + page modules) |
| **Client/server decision** | None: everything is server-side | You decide per interaction |
| **Real-time multi-user** | Built in (all subscribers see same state) | Requires explicit broadcast |
| **Code to write** | One update function | Two update functions (client + server) |

### When server components make more sense

**Most of the time, honestly.** For apps where interactions are button clicks, form submissions, and navigation, the server round-trip on same-region infra is 10-50ms and users won't notice. You get a simpler mental model (one update function, no client/server split decisions), a tiny client bundle, zero codec concerns, and real-time multi-user for free since all clients subscribe to the same server-side state.

Server components can also embed client-side Lustre components as web components for spots that need local interactivity, with the server pushing data via attributes and context providers. For apps that are 90% server-driven with a few interactive widgets, this hybrid approach works well.

### When rally makes more sense

**Multiple client surfaces.** The explicit server handler layer is a typed API contract. A web client calls handlers over WebSocket. A CLI calls the same handlers over HTTP. An AI agent uses the CLI. A JS SDK calls the same endpoints from a static site. One set of `server_*` functions serves all of them.

With server components, the wire protocol is VDOM patches: only a browser can consume them. If you later need a CLI or SDK, you build a separate API layer, maintain two ways to invoke the same business logic, two auth paths, two testing surfaces.

**Responsive local interactions.** For continuous client interactions (typing with live feedback, drag-and-drop, editors, optimistic updates), the server round-trip becomes perceptible. Rally keeps those interactions local and only crosses the network for things that actually need the server.

The cost is real: you write two update functions per page, you decide what belongs on the client vs. server for every interaction, the client bundle is larger, and you need a broadcast system for real-time multi-user features. But if your app has multiple client surfaces, the "overhead" of explicit domain messages is actually the architecture that enables them.

## Examples

- `examples/realworld/` — [RealWorld](https://github.com/gothinkster/realworld) (Conduit) clone with auth, articles, comments, tags, favorites, follows

## Prior art

- [Lamdera](https://lamdera.com): explicit server handler types as client-server contract, TEA on both sides
- [elm-land](https://elm.land): file-based routing conventions
- [Marmot](https://github.com/daverapin/marmot): SQL-first codegen with live SQLite introspection

## Technical reference

See [llms.txt](llms.txt) for the full architecture breakdown: codegen modules, runtime library, wire protocol details, configuration, and project structure.
