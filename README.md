# Rally

A full-stack web framework for Gleam on the BEAM. You write page modules that contain both client and server code in the same file. Rally's codegen reads your source, splits out the client-safe parts, and produces a working web app with file-based routing, server-side rendering, and real-time client-server messaging over WebSockets.

The developer experience: define a `Model`, `Msg`, `init`, `update`, and `view` (standard Lustre TEA), add `server_*` handler functions for anything that needs the database, run `gleam run -m rally`, and the framework generates everything else: router, RPC dispatch, SSR handler, WebSocket handler, HTTP handler, and a complete client package with typed RPC stubs.

```sh
bin/new my_app
cd my_app && bin/dev
```

`bin/dev` runs codegen, builds the JS client, and starts the server on port 8080. Fresh apps default to `APP_ENV=dev`. Set `APP_ENV=prod` in production so session cookies include `Secure` and browser console logging stays off.

## What Rally generates

Running `gleam run -m rally` reads `[[tools.rally.clients]]` from gleam.toml and produces these files for each client namespace:

**Server-side** (in `src/generated/<namespace>/`):

| File | What it does |
|------|-------------|
| `router.gleam` | `Route` type, `parse_route`, `route_to_path`, `href` |
| `page_dispatch.gleam` | `PageModel`/`PageMsg` unions, per-route init/update/view dispatch |
| `rpc_dispatch.gleam` | Routes wire messages to `server_*` handler functions |
| `ssr_handler.gleam` | Calls `load`, renders `view` wrapped in layout, embeds model as flags |
| `ws_handler.gleam` | WebSocket frame loop: page topics, RPC dispatch, push frame delivery |
| `http_handler.gleam` | HTTP POST /rpc handler for non-WebSocket clients |
| `protocol_wire.gleam` | Protocol facade: delegates to libero's ETF or JSON wire module |

**Client-side** (in `.generated_clients/<namespace>/`):

| File | What it does |
|------|-------------|
| `src/generated/app.gleam` | Lustre SPA entry: per-page TEA loop, WebSocket transport, modem routing |
| `src/generated/transport.gleam` | FFI bridge to the WebSocket runtime |
| `src/generated/types.gleam` | `ClientMsg` type mirroring server dispatch variants |
| `src/generated/codec.gleam` | SSR flag decoding for hydration |
| `src/<namespace>/pages/*.gleam` | Tree-shaken page modules (server code stripped, client code kept) |
| `src/rally_runtime/effect.gleam` | Client-side effect shim: rpc, navigate, send_to_client_context |

The client package is a standalone Gleam project with its own `gleam.toml`. The server project is the single source of truth.

## The page module

A page file in `src/<namespace>/pages/` maps to a URL route. The filename determines the URL:

| File | URL | Route variant |
|------|-----|--------------|
| `home_.gleam` | `/` | `Home` |
| `about.gleam` | `/about` | `About` |
| `products/id_.gleam` | `/products/:id` | `ProductsId(id: Int)` |
| `settings/profile.gleam` | `/settings/profile` | `SettingsProfile` |

Trailing underscore marks a dynamic segment. Names ending in `_id` parse as `Int`; everything else is `String`.

A page module exports types and functions that the codegen consumes:

```gleam
// Client (standard Lustre TEA)
pub type Model { Model(count: Int, name: String) }
pub type Msg { Increment; GotData(Result(Data, List(String))) }

pub fn init(client_context: ClientContext) -> #(Model, Effect(Msg))
pub fn update(client_context: ClientContext, model: Model, msg: Msg) -> #(Model, Effect(Msg))
pub fn view(client_context: ClientContext, model: Model) -> Element(Msg)

// Server handler: the type is the RPC input, the function is the endpoint.
// Libero discovers any pub fn server_* with this shape.
pub type ServerLoadData { ServerLoadData(id: Int) }
pub fn server_load_data(
  msg msg: ServerLoadData,
  server_context server_context: ServerContext,
) -> Result(Data, List(String))
```

The client calls the server by constructing the message type directly:

```gleam
rally_effect.rpc(ServerLoadData(id: 42), on_response: GotData)
```

The handler's return type becomes the response type in the `on_response` callback. There is no separate API definition: the type *is* the contract.

### Stateful server model (optional)

For pages that need per-connection server state or bidirectional push, Rally supports a second pattern: define `ToServer`/`ToClient` message types, a `ServerModel`, and `server_init`/`server_update` functions. The server keeps state between calls and can push messages to the client at any time.

```gleam
pub type ToServer { ToggleFavorite; AddComment(body: String) }
pub type ToClient { ArticleUpdated(Article); CommentAdded(Comment) }
pub type ServerModel { ServerModel(article_id: Int) }

pub fn server_init(slug: String, server_context: ServerContext)
  -> #(ServerModel, Effect(ToClient))
pub fn server_update(model: ServerModel, msg: ToServer, server_context: ServerContext)
  -> #(ServerModel, Effect(ToClient))
```

Start with RPC. It's simpler, stateless, and covers most cases. Use the stateful model when you need server-side state between calls (like entity ownership for authorization) or server-initiated push messages. See `examples/realworld/` for both patterns side by side.

For SSR, a page can optionally export `load` (server-side data fetch) and `init_loaded` (client init from pre-fetched data). See [llms.txt](llms.txt) for the full hydration flow.

## How codegen works

The pipeline runs once per `[[tools.rally.clients]]` entry:

```
gleam.toml config
      |
      v
   scanner         Walks src/<namespace>/pages/, builds a List(ScannedRoute)
      |             from the filesystem structure.
      v
   parser           Parses each page's source with Glance AST, extracts
      |             Model/Msg types, function signatures, auth constants.
      |             Produces a PageContract per page.
      v
   libero           Scans for server_* handlers, discovers RPC endpoints,
      |             walks the type graph for codec generation.
      v
   generators       Emit server-side Gleam (router, dispatch, SSR, WS, HTTP),
      |             client-side Gleam (app, transport, tree-shaken pages),
      |             Erlang (atoms, wire), and JS (codec, transport).
      v
   tree shaker      Strips server-only code from page source before copying
      |             it to the client package. Uses Glance AST to identify
      |             server functions and trace reachability.
      v
   dependency       Follows import chains from client pages to copy any
   resolver         shared modules the client needs (and catches
      |             @external(erlang) imports that can't run in JS).
      v
   output           Writes all generated files, formats .gleam files
                    with `gleam format`, skips unchanged files.
```

The types that flow through this pipeline are defined in `src/rally/types.gleam`. That file is the vocabulary for the entire codegen system: `ScannedRoute`, `PageContract`, `ScanConfig`, `VariantInfo`, and the rest.

## Project layout

```
src/
  rally.gleam                    # CLI entry point, orchestrates the pipeline
  rally/
    scanner.gleam                # Filesystem walk -> List(ScannedRoute)
    parser.gleam                 # Glance AST -> PageContract
    types.gleam                  # Shared types for the pipeline
    tree_shaker.gleam            # Strips server code from page source
    dependency_resolver.gleam    # Follows imports to copy shared modules
    format.gleam                 # Runs gleam format on generated code
    generator.gleam              # Route type, parse_route, page dispatch codegen
    generator/
      client.gleam               # Client package: gleam.toml, app.gleam, transport
      codec.gleam                # Client codegen: types, decoders, effect shim, per-page modules
      ssr_handler.gleam          # SSR handler codegen
      ws_handler.gleam           # WebSocket handler codegen
      http_handler.gleam         # HTTP RPC handler codegen
      json_rpc_dispatch.gleam    # JSON-specific RPC dispatch codegen
  rally_runtime/
    effect.gleam                 # rpc, broadcast, navigate, send_to_client_context
    db.gleam                     # SQLite: open (WAL/busy/FK), query, transaction
    system.gleam                 # System DB: message logging, job queue
    jobs.gleam                   # Background job runner with retry
    session.gleam                # Session cookie generation and extraction
    env.gleam                    # APP_ENV parsing, secure cookie policy
    topics.gleam                 # OTP pg pub/sub for broadcast
    wire.gleam                   # Thin wrapper over libero wire protocol
    codec.gleam                  # Base64 ETF encode/decode for SSR flags
    ssr.gleam                    # Lustre element to HTML string
    auth.gleam                   # AuthPolicy, LoadResult, Cookie types
    migrate.gleam                # SQL migration runner
    test_db.gleam                # In-memory test DB with migration caching
    transport_ffi.mjs            # Browser WebSocket client (reconnect, RPC, push, debug)
    rally_runtime_ffi.mjs        # JS FFI stubs for server-only functions
    rally_effect_ffi.mjs         # Browser-side navigate via pushState
examples/
  realworld/                     # RealWorld (Conduit) clone: full CRUD with auth
test/
  rally/                         # Scanner, parser, generator, codec, auth tests
  rally_runtime/                 # Wire, session, broadcast, jobs, topics tests
  js/                            # Browser-side JS tests (auth errors, frame decode)
```

**Two module trees, two audiences.** `rally/` is the codegen tool that app developers run at build time. `rally_runtime/` is the library that ships with every Rally app and runs at request time. Contributors working on routing or code generation stay in `rally/`. Contributors working on WebSocket behavior, broadcasts, or database helpers stay in `rally_runtime/`.

## Development setup

Rally is a Gleam project targeting Erlang. You need:

- [Gleam](https://gleam.run/getting-started/installing/) (v1.x)
- Erlang/OTP 26+
- SQLite3 (usually already present on macOS and Linux)
- Node.js (for building and testing the generated JS client)

```sh
git clone <repo-url>
cd rally
gleam build
```

Rally depends on [libero](https://github.com/pairshaped/libero) as a sibling directory by default (see `gleam.toml` path dependency). Clone libero alongside rally if you don't have it.

## Running tests

```sh
gleam test                       # All Gleam tests: scanner, parser, generator, wire, codec, auth, etc.
gleam run -m birdie              # Review snapshot test changes interactively
gleam run -m birdie accept       # Accept all new snapshots
test/js/run_auth_error_test.sh   # JS-side auth error detection (not part of gleam test)
```

Tests create temporary directories in `/tmp/rally_test_*` and clean up after themselves. Codec and wire tests use in-memory SQLite via `test_db.gleam`.

## Where to start reading

If you're new to the codebase, read in this order:

1. **`src/rally/types.gleam`** -- the type vocabulary. Every pipeline type is documented here. Read this first so the rest of the code makes sense.
2. **`src/rally/scanner.gleam`** -- the simplest module in the pipeline. Walks the filesystem, returns routes. Good warmup.
3. **`src/rally/parser.gleam`** -- uses Glance AST to extract the page contract. Shows how Rally discovers what a page exports.
4. **`src/rally.gleam`** -- the orchestrator. Long file, but it shows how scanner, parser, libero, generators, tree shaker, and dependency resolver connect.
5. **`src/rally_runtime/effect.gleam`** -- the API that app developers call. Shows how server push, broadcast, and RPC work from the app's perspective.
6. **`examples/realworld/`** -- a full app built with Rally. See `examples/realworld/README.md` for a walkthrough of the pages and patterns.

For the codegen generators (`generator/*.gleam`): these files build Gleam/Erlang/JS source as strings. They're inherently harder to read than normal code. Start with `generator.gleam` (route type and parse function), which is the simplest, before moving to `generator/ws_handler.gleam` or `generator/ssr_handler.gleam`.

---

## Design decisions

### Single source, generated client

You write one Gleam project. Page modules contain both client and server code in the same file. The codegen reads your source, extracts the client-side types and functions, and generates a complete client package (its own `gleam.toml`, dependencies, transport layer, codec). The server source is the single source of truth. The tradeoff: you depend on the codegen to correctly split client from server, and debugging generated code requires understanding the tree shaker.

### Colocation-first

Types, state, and logic live in the page file until they need to be shared. A page module contains its client model, server model, messages in both directions, and all the update/view functions. There's no upfront shared domain layer. Extract when duplication becomes a maintenance problem, not before.

### SQLite ships with every app

Every Rally app gets SQLite with WAL mode, busy timeout, and foreign keys enabled. One embedded database, configured once in `db.open`. The tradeoff is that you're locked to SQLite (no Postgres, no MySQL). Marmot generates type-safe query functions from `.sql` files via live SQLite introspection.

### ETF over the wire

Client-server messages are serialized as ETF (Erlang External Term Format), not JSON. ETF is the BEAM's native binary format: atoms, tuples, and tagged variants survive the round trip without a separate schema definition layer. The codegen produces JS encode/decode functions that match the Gleam types exactly. JSON is available as an alternative protocol for non-Gleam clients.

### File-based routing with codegen

Routes are the filesystem. `src/pages/home_.gleam` is `/`, `src/pages/products/id_.gleam` is `/products/:id`. The codegen scans page modules, discovers `server_*` handlers via libero, and produces router, RPC dispatch, SSR handler, WebSocket handler, HTTP handler, and the full client package with typed RPC stubs. Everything happens at build time. The tradeoff: adding a route means creating a file and re-running codegen, and the naming conventions (trailing underscore for dynamic segments, `_id` suffix for integers) are fixed.

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

Most of the time. For apps where interactions are button clicks, form submissions, and navigation, the server round-trip on same-region infra is 10-50ms and users won't notice. You get a simpler mental model (one update function, no client/server split decisions), a tiny client bundle, zero codec concerns, and real-time multi-user for free since all clients subscribe to the same server-side state.

Server components can also embed client-side Lustre components as web components for spots that need local interactivity, with the server pushing data via attributes and context providers. For apps that are 90% server-driven with a few interactive widgets, this hybrid approach works well.

### When Rally makes more sense

**Multiple client surfaces.** The explicit server handler layer is a typed API contract. A web client calls handlers over WebSocket. A CLI calls the same handlers over HTTP. An AI agent uses the CLI. A JS SDK calls the same endpoints from a static site. One set of `server_*` functions serves all of them.

With server components, the wire protocol is VDOM patches: only a browser can consume them. If you later need a CLI or SDK, you build a separate API layer, maintain two ways to invoke the same business logic, two auth paths, two testing surfaces.

**Responsive local interactions.** For continuous client interactions (typing with live feedback, drag-and-drop, editors, optimistic updates), the server round-trip becomes perceptible. Rally keeps those interactions local and only crosses the network for things that actually need the server.

The cost is real: you write two update functions per page, you decide what belongs on the client vs. server for every interaction, the client bundle is larger, and you need a broadcast system for real-time multi-user features. But if your app has multiple client surfaces, the "overhead" of explicit domain messages is actually the architecture that enables them.

## Examples

- `examples/realworld/`: [RealWorld](https://github.com/gothinkster/realworld) (Conduit) clone with auth, articles, comments, tags, favorites, follows. See [its README](examples/realworld/README.md) for a walkthrough.

## Prior art

- [Lamdera](https://lamdera.com): explicit server handler types as client-server contract, TEA on both sides
- [elm-land](https://elm.land): file-based routing conventions
- [Marmot](https://github.com/daverapin/marmot): SQL-first codegen with live SQLite introspection

## Technical reference

[llms.txt](llms.txt) is the machine-readable framework contract: codegen modules, runtime library, wire protocol details, auth framework, configuration, and the full page module spec. It's maintained alongside the code and reflects the current state of the framework.
