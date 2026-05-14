![Rally](https://github.com/pairshaped/rally/blob/master/rally.png?raw=true)

# Rally

[![Package Version](https://img.shields.io/hexpm/v/rally)](https://hex.pm/packages/rally)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/rally/)

Rally is a full-stack web framework for Gleam on the BEAM. You write page modules where client code and server code live in the same file, and Rally generates the glue: routing, server-side rendering, WebSocket transport, and typed client-server messaging.

Rally apps use SQLite by default. You get an embedded database, migrations, and type-safe SQL codegen without running a separate database server.

Each page is a standard Lustre TEA component (Model, Msg, init, update, view). Add a `server_*` handler function for anything that needs the database, and Rally generates the encoders, decoders, and dispatch so the client can call it with a typed message. The wire protocol comes from [libero](https://hexdocs.pm/libero/), which owns the RPC contract between client and server.

## Create an app

```sh
gleam new my_app
cd my_app
gleam add rally libero
gleam run -m rally init
bin/dev
```

`rally init` writes the starter app into the current Gleam project. `bin/dev` runs codegen, builds the JS client, and starts the server on port 8080. SQLite is the database; there is no separate database service to install.

Fresh apps default to `APP_ENV=dev`. Set `APP_ENV=prod` in production so session cookies include `Secure` and browser console logging stays off.

## Writing a page

A page file in `src/<namespace>/pages/` is a Lustre component:

```gleam
pub type Model { Model(count: Int, name: String) }
pub type Msg { Increment; GotData(Result(Data, List(String))) }

pub fn init(client_context: ClientContext) -> #(Model, Effect(Msg))
pub fn update(client_context: ClientContext, model: Model, msg: Msg) -> #(Model, Effect(Msg))
pub fn view(client_context: ClientContext, model: Model) -> Element(Msg)
```

That's the client side. To add a server call, define a handler in the same file:

```gleam
pub type ServerLoadData { ServerLoadData(id: Int) }
pub fn server_load_data(
  msg msg: ServerLoadData,
  server_context server_context: ServerContext,
) -> Result(Data, List(String))
```

The client calls it by constructing the message type:

```gleam
rally_effect.rpc(ServerLoadData(id: 42), on_response: GotData)
```

There is no separate API definition. The type *is* the contract. Libero discovers `server_*` functions, walks their type signatures, and generates the wire protocol automatically.

## File-based routing

The filename determines the URL:

| File | URL | Route variant |
|------|-----|--------------|
| `home_.gleam` or `index.gleam` | `/` | `Home` |
| `about.gleam` | `/about` | `About` |
| `products/id_.gleam` | `/products/:id` | `ProductsId(id: Int)` |
| `settings/profile.gleam` | `/settings/profile` | `SettingsProfile` |

Rally follows Elm Land's homepage convention: `home_.gleam` is reserved for `/`. `index.gleam` also maps to its parent directory. Outside those root-page cases, a file or directory segment ending in `_` becomes dynamic. After Rally removes the trailing `_`, params named `id` or ending in `_id` parse as `Int`; other params parse as `String`. Adding a route means creating a file and re-running codegen.

## Stateful server model

Most server work is just a `server_*` handler called with `rally_effect.rpc`. Use the stateful model only when the server needs to remember page state between client messages. In that case, define `ToServer`/`ToClient` message types and a `ServerModel`:

```gleam
pub type ToServer { ToggleFavorite; AddComment(body: String) }
pub type ToClient { ArticleUpdated(Article); CommentAdded(Comment) }
pub type ServerModel { ServerModel(article_id: Int) }

pub fn server_init(slug: String, server_context: ServerContext)
  -> #(ServerModel, Effect(ToClient))
pub fn server_update(model: ServerModel, msg: ToServer, server_context: ServerContext)
  -> #(ServerModel, Effect(ToClient))
```

The client sends `ToServer` messages with `rally_effect.send_to_server`, and the server responds or pushes `ToClient` messages from `server_init` and `server_update`. Start with RPC; reach for the stateful model when you need server-side state between calls, like entity ownership for authorization. See `examples/realworld/` for both patterns side by side.

## Broadcast

Server-to-client messaging at four scopes, built on OTP pg process groups:

| Effect | Who receives it |
|---|---|
| `send_to_client(msg)` | One specific connection |
| `broadcast_to_session(msg)` | Every tab in the same browser session |
| `broadcast_to_page(msg)` | Every connection viewing the same page |
| `broadcast_to_app(msg)` | Every connection to the app |

Connections auto-subscribe to their relevant topics on WebSocket connect.

## SSR with hydration

The first request renders full HTML server-side with the model embedded as flags. The client reads the flags, boots Lustre, and takes over as a SPA. Subsequent navigations are client-side only (modem handles pushState).

A page can optionally export `load` (server-side data fetch) and `init_loaded` (client init from pre-fetched data).

---

## What to import

Most Rally apps use only a small set of modules directly:

| Module | Use it for |
|---|---|
| `rally_runtime/effect` | Page effects: RPC, server messages, navigation, broadcast, and client context updates |
| `rally_runtime/db` | Opening SQLite, timed queries, nested transactions, and small SQL value helpers |
| `rally_runtime/system` | App startup, message logging, and background jobs |
| `rally_runtime/session` | Session cookie generation, parsing, and response headers |
| `rally_runtime/auth` | Auth policy and load result types used by page modules |
| `rally_runtime/env` | `APP_ENV` parsing and production cookie policy |
| `rally_runtime/migrate` | Running numbered SQLite migrations |
| `rally_runtime/test_db` | Fast in-memory SQLite setup for tests |

The `rally/internal/...` modules are Rally's codegen implementation. They are tested, but app code should treat them as private. The generated files under `src/generated/` are the stable boundary between Rally's internals and your app.

---

## Under the hood

This section covers what Rally generates and how the codegen pipeline works. You don't need this to start building, but it helps when debugging or contributing.

### What Rally generates

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

### The codegen pipeline

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

The types that flow through this pipeline are defined in `src/rally/internal/types.gleam`.

### Libero and the wire protocol

[Libero](https://hexdocs.pm/libero/) handles the wire protocol and RPC contracts. It scans page modules for `server_*` handler functions, walks the type graph to discover what needs encoding, and generates the ETF and JSON codec functions for both sides of the wire.

Rally's codegen calls into libero after the scanner and parser have extracted the page structure. From that point, libero owns everything related to wire protocol and RPC dispatch: the `protocol_wire.gleam` facade, the JS codec modules, and the Erlang atom/wire helpers all come from libero's type walk. If you're working on how messages get encoded, decoded, or dispatched, you're working in libero's domain.

Messages are serialized as ETF (Erlang External Term Format) by default. ETF is the BEAM's native binary format: atoms, tuples, and tagged variants survive the round trip without a separate schema definition layer. JSON is available as an alternative for non-Gleam clients.

---

## Design decisions

### Single source, generated client

You write one Gleam project. The codegen reads your source, extracts client-side types and functions, and generates a complete client package (its own `gleam.toml`, dependencies, transport layer, codec). The tradeoff: you depend on the codegen to correctly split client from server, and debugging generated code requires understanding the tree shaker.

### Colocation-first

Types, state, and logic live in the page file until they need to be shared. There's no upfront shared domain layer. Extract when duplication becomes a maintenance problem, not before.

### SQLite ships with every app

Every Rally app gets SQLite with WAL mode, busy timeout, and foreign keys enabled. One embedded database, configured once in `db.open`. The tradeoff is that there is no tradeoff: you don't need anything more than sqlite3. Marmot generates type-safe query functions from `.sql` files via live SQLite introspection.

### Lamdera-inspired, not Lamdera-bound

Lamdera's architecture is the starting point: explicit server handler types as the client-server contract, server-side state per connection, TEA on both sides. But Gleam on the BEAM gives us OTP processes, pg groups, and native concurrency that Elm can't access. Where the BEAM offers a better primitive, we use it (four-level broadcast via pg, process dictionary for handler state, native ETF codec, libero for RPC dispatch).

---

## Rally vs Lustre server components

These are two different architectures for building full-stack Lustre apps.

**Lustre server components** run the TEA loop on the server: model, update, and view all execute server-side. On first connect, the server sends the full VDOM. On each subsequent update, it diffs the old and new VDOM and sends only the patch. The client is a thin JS shell (~10KB) that applies DOM patches and forwards events back to the server.

**Rally** runs TEA in the browser for UI state. Server work is explicit: most pages call stateless `server_*` RPC handlers, while pages that need per-connection server state use `server_init`/`server_update` and `ToServer`/`ToClient` messages. In both cases the wire carries domain messages, not VDOM patches.

| | Lustre server components | Rally |
|---|---|---|
| **Where UI runs** | Server (model + update + view) | Client (model + update + view) |
| **What goes over the wire** | VDOM patches down, DOM events up | Domain messages in both directions |
| **Interaction latency** | Every event round-trips to server | Local state changes are instant |
| **Server memory** | Model + VDOM + event handler cache (shared across subscribers of same component) | Optional ServerModel per connection for stateful pages; stateless RPC pages keep no page model on the server |
| **Client JS bundle** | Minimal (DOM patcher, ~10KB) | Full app logic (Lustre + page modules) |
| **Client/server decision** | None: everything is server-side | You decide per interaction |
| **Real-time multi-user** | Built in (all subscribers see same state) | Requires explicit broadcast |
| **Code to write** | One update function | Client update plus server handlers; stateful pages also define server_update |

### When to use Lustre server components

To be honest? Most of the time. For apps where interactions are button clicks, form submissions, and navigation, the server round-trip on same-region infra is 10-50ms and users won't notice. You get a simpler mental model (one update function, no client/server split decisions), a tiny client bundle, zero codec concerns, and real-time multi-user for free since all clients subscribe to the same server-side state.

Server components can also embed client-side Lustre components as web components for spots that need local interactivity, with the server pushing data via attributes and context providers. For apps that are 90% server-driven with a few interactive widgets, this hybrid approach works well.

### When to use Rally

**Multiple client surfaces.** The explicit server handler layer is a typed API contract. A web client calls handlers over WebSocket. A CLI calls the same handlers over HTTP. An AI agent uses the CLI. A JS SDK calls the same endpoints from a static site. One set of `server_*` functions serves all of them.

With server components, the wire protocol is VDOM patches: only a browser can consume them. If you later need a CLI or SDK, you build a separate API layer, maintain two ways to invoke the same business logic, two auth paths, two testing surfaces.

**Responsive local interactions.** For continuous client interactions (typing with live feedback, drag-and-drop, editors, optimistic updates), the server round-trip becomes perceptible. Rally keeps those interactions local and only crosses the network for things that actually need the server.

Rally unfortunately needs a bit more from you. Each page has a client update and a server update. You have to decide which side owns each interaction. The browser ships more code. Real-time multi-user work goes through broadcast. If your app has more than one client, that explicit message layer pays for itself.

## Examples

- `examples/realworld/`: [RealWorld](https://github.com/gothinkster/realworld) (Conduit) clone with auth, articles, comments, tags, favorites, follows. See [its README](examples/realworld/README.md) for a walkthrough.

## Contributing

### Prerequisites

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

Rally depends on [libero](https://hexdocs.pm/libero/). App projects should add both packages with `gleam add rally libero`.

### Running tests

```sh
gleam test                       # All Gleam tests
gleam run -m birdie              # Review snapshot test changes interactively
gleam run -m birdie accept       # Accept all new snapshots
test/js/run_auth_error_test.sh   # JS-side auth error detection (not part of gleam test)
```

Tests create temporary directories in `/tmp/rally_test_*` and clean up after themselves. Test-only fixture apps live under `fixtures/`; codec and wire tests use in-memory SQLite via `test_db.gleam`.

### Project layout

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

**Two module trees, two audiences.** `rally/internal/` is the codegen tool that app developers run at build time. `rally_runtime/` is the library that ships with every Rally app and runs at request time. Contributors working on routing or code generation stay in `rally/internal/`. Contributors working on WebSocket behavior, broadcasts, or database helpers stay in `rally_runtime/`.

### Where to start reading

If you're new to the codebase, read in this order:

1. **`src/rally/internal/types.gleam`**: the type vocabulary. Every pipeline type is documented here. Read this first so the rest of the code makes sense.
2. **`src/rally/internal/scanner.gleam`**: the simplest module in the pipeline. Walks the filesystem, returns routes. Good warmup.
3. **`src/rally/internal/parser.gleam`**: uses Glance AST to extract the page contract. Shows how Rally discovers what a page exports.
4. **`src/rally.gleam`**: the orchestrator. Long file, but it shows how scanner, parser, libero, generators, tree shaker, and dependency resolver connect.
5. **`src/rally_runtime/effect.gleam`**: the API that app developers call. Shows how server push, broadcast, and RPC work from the app's perspective.
6. **`examples/realworld/`**: a full app built with Rally. See `examples/realworld/README.md` for a walkthrough of the pages and patterns.

For the codegen generators (`internal/generator/*.gleam`): these files build Gleam/Erlang/JS source as strings. They're inherently harder to read than normal code. Start with `internal/generator.gleam` (route type and parse function), which is the simplest, before moving to `internal/generator/ws_handler.gleam` or `internal/generator/ssr_handler.gleam`.

## Influences and credits

- [Lamdera](https://lamdera.com): explicit server handler types as the client-server contract, TEA on both sides
- [Lustre](https://lustre.build/): TEA, effects, and the client-side UI runtime
- [elm-land](https://elm.land): file-based routing conventions, including `home_` for the root page
- [Libero](https://hexdocs.pm/libero/): wire protocol and RPC contract layer (type graph walking, ETF/JSON codec generation, `server_*` handler discovery)
- [Marmot](https://hexdocs.pm/marmot/): SQL-first codegen with live SQLite introspection

## Technical reference

[llms.txt](llms.txt) is the machine-readable framework contract: codegen modules, runtime library, wire protocol details, auth framework, configuration, and the full page module spec. It's maintained alongside the code and reflects the current state of the framework.
