# Lando Framework Design

A full-stack web framework for Gleam + Lustre with file-based routing, inspired by elm-land and Lamdera.

## Core Insight

The experiment was run: a 47k LOC SPA+RPC codebase dropped to 28k when converted to server components. The difference is the client-server boundary. Lando eliminates the boundary from the developer's perspective while keeping SPA responsiveness with ETF-over-WebSocket RPC.

The developer writes one page module. Lando generates the entire JavaScript client, the server dispatch, the routing, and the transport. The async boundary is framework-owned.

## Architecture

```
my_app/
├── src/                    # Erlang target — the only code you write
│   ├── app.gleam           # generated once, customizable
│   ├── app_config.gleam    # you write: DB path, port, session config
│   ├── pages/              # routes = filesystem (elm-land style)
│   │   ├── home.gleam
│   │   └── products/
│   │       ├── index.gleam
│   │       └── id_.gleam
│   ├── sql/                # marmot .sql files (one query per file)
│   └── generated/          # lando output (never edited)
├── gleam.toml              # target = erlang
├── client/                 # lando-generated, JS target (never edited by you)
│   ├── gleam.toml
│   └── src/generated/
└── bin/dev
```

No shared package. The server source is the single source of truth. Lando reads it and generates the client.

## Page Module Contract

A page file lives in `pages/` at the path matching its URL. Files use snake_case; trailing underscore marks a dynamic segment; `home_.gleam` at root is the home route.

```gleam
// pages/products/id_.gleam
// maps to /products/:id

import app_config.{type Context}
import marmot/generated/products_sql
import lando/effect

// -- Client state (no RpcData, no Loading — just data) --
pub type Model { Model(product: Option(Product), open: Bool) }

// -- Client UI events. GotServerMsg handles ALL server responses. --
pub type Msg {
  UserClickedToggle
  UserClickedSave(data: ProductData)
  GotServerMsg(ToFrontend)
}

// -- Messages to the server --
pub type ToBackend {
  LoadProduct(id: Int)           // fires on page init (client-nav path)
  SaveProduct(data: ProductData)
}

// -- Messages from the server --
pub type ToFrontend {
  ProductLoaded(Product)
  LoadError(String)
  ProductSaved(Product)
  SaveError(String)
}

// -- Initial model (no server data yet — SSR or RPC fills it in) --
pub fn init(id: Int) -> #(Model, Effect(Msg)) {
  #(Model(product: None, open: False),
    send_to_backend(LoadProduct(id)))
}
// SSR path: the framework calls `load` server-side, renders HTML with the
// result, and the generated client skips LoadProduct on hydration.
// Client-nav path: init fires LoadProduct over the wire; GotServerMsg
// delivers ProductLoaded or LoadError.

// -- Client-side update. Local mutations update instantly; server
// mutations go through send_to_backend. --
pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UserClickedToggle ->
      #(Model(..model, open: !model.open), effect.none())
    UserClickedSave(data) ->
      #(model, send_to_backend(SaveProduct(data)))
    GotServerMsg(ProductLoaded(p)) ->
      #(Model(..model, product: Some(p)), effect.none())
    GotServerMsg(ProductSaved(p)) ->
      #(Model(..model, product: Some(p)), effect.none())
    GotServerMsg(SaveError(_)) ->
      #(model, effect.none()) // framework shows generic error toast
  }
}

// -- View (pure function, runs server-side for SSR and client-side after) --
pub fn view(model: Model) -> Element(Msg) { ... }

// -- Server-side update. Receives ToBackend, returns ToFrontend effects. --
pub fn server_update(
  model: ServerModel,
  msg: ToBackend,
  ctx: Context,
) -> #(ServerModel, Effect(ToFrontend)) {
  case msg {
    LoadProduct(id) -> {
      case products_sql.get_by_id(ctx.db, id) {
        Ok(p) -> #(model, send_to_client(ProductLoaded(p)))
        Error(e) -> #(model, send_to_client(LoadError(format_error(e))))
      }
    }
    SaveProduct(data) -> {
      case products_sql.save(ctx.db, data) {
        Ok(product) -> #(model, send_to_client(ProductSaved(product)))
        Error(e) -> #(model, send_to_client(SaveError(format_error(e))))
      }
    }
  }
}

// -- SSR data loading. Runs once server-side before first HTML render.
// The result is serialized into the page; the generated client hydrates
// from it and skips the matching send_to_backend call in init. --
pub fn load(id: Int, ctx: Context) -> Result(Model, LoadError) {
  let product = products_sql.get_by_id(ctx.db, id)
  Ok(Model(product: Some(product), open: False))
}

// -- Per-session server state (optional, can be unit if stateless) --
pub type ServerModel { ServerModel }
```

### Conventions

- `Model` — client-side state. No `RpcData`, no `Loading` variant. Holds plain data.
- `Msg` — client UI events. Always includes `GotServerMsg(ToFrontend)` as the single receive path for server responses.
- `init` — runs on every page entry (SSR and client navigation). Returns initial model and effects (typically `send_to_backend` for data).
- `update` — runs on the client. Local mutations (toggles, input) stay here. Server-touching mutations fire `send_to_backend`. Server responses arrive via `GotServerMsg`.
- `view` — pure function of `Model`, compiles to both targets.
- `ToBackend` — explicit message type for client-to-server events. The developer writes it.
- `ToFrontend` — explicit message type for server-to-client events. The developer writes it.
- `server_update` — runs on the server. Receives `ToBackend`, has access to `ctx` (DB, session). Returns `ToFrontend` effects via `send_to_client` or `broadcast`.
- `load` — SSR-only: called server-side before first HTML render. Returns a `Model` that gets serialized into the page. The generated client uses it for hydration and skips the corresponding `send_to_backend` call.
- `ServerModel` — per-page server state, defined by the page. Can be a unit type if stateless.
- `Context` — defined by the app in `app_config.gleam`. Landocode threads it through every `server_update` and `load` call. Typically holds a DB connection and session.
- `send_to_backend(variant)` — lando-provided effect. On the client: serializes the variant and sends it over WebSocket. In generated code: becomes a WebSocket send.
- `send_to_client(variant)` / `broadcast(variant)` — lando-provided server-side effects. `send_to_client` responds to the requesting client; `broadcast` sends to all clients on the page.

## File-Based Routing

Same conventions as the existing lando prototype:

| Filesystem | URL segment | Route variant |
|---|---|---|
| `events.gleam` | `/events` (static) | `RegistrationEvents` |
| `id_.gleam` | `/:id` (dynamic Int) | `RegistrationEventsId(id: Int)` |
| `key_.gleam` | `/:key` (dynamic String) | `...Key(key: String)` |
| `home_.gleam` at root | `/` | `Home` |

Parameter type inference: names that are `id` or end in `_id` become `Int`, everything else `String`.

## What Lando Generates

### From the pages/ directory

**Server package (`src/generated/`):**
- `router.gleam` — Route type, parse_route, route_to_path, href
- `page_dispatch.gleam` — PageModel/PageMsg union types, init/update/view dispatch
- `server_dispatch.gleam` — WebSocket handler, routes incoming ToBackend to page.server_update
- `ssr_handler.gleam` — SSR entry: calls load, renders HTML, embeds serialized model

**Client package (`client/src/generated/`):**
- `app.gleam` — Lustre entry point, hydration, WebSocket transport
- `router.gleam` — client-side routing (mirrors server router)
- `types.gleam` — mirrored Model/Msg types from each page
- `views.gleam` — mirrored view functions from each page
- `codec.gleam` — ETF encode/decode for ToBackend/ToFrontend per page
- `transport.gleam` — WebSocket send/receive + auto-reconnect

### From the sql/ directory

Marmot generates type-safe query functions (one per .sql file) into `src/generated/sql/`.

## Transport

- **Wire format:** ETF (Erlang External Term Format), binary, not text
- **Transport:** WebSocket with auto-reconnect and exponential backoff
- **SSR:** first request renders HTML with serialized model embedded as flags
- **Hydration:** client reads flags, boots Lustre, takes over as SPA
- **Page navigation:** client-side routing, `init` called with route params, data loaded via SSR or RPC

## Framework-Owned Async

The page module never holds async wrapper types in its `Model`. Data is either present (loaded via SSR or RPC) or absent (the initial model before the response arrives). The model is always `List(Item)`, never `RpcData(List(Item), Error)`.

Transport-level concerns are framework-owned:
- Connection lost: framework shows a reconnecting indicator
- ETF decode failures: framework shows a generic error toast
- Page navigation loading: framework shows a thin progress bar or overlay

Domain errors (`SaveError`, `LoadError`) arrive as `ToFrontend` variants. The developer chooses: handle them for custom UX, or let them fall through to the framework's generic error toast.

## Data Layer (Marmot)

SQL queries live in `sql/` directories alongside pages. Marmot introspects a live SQLite database and generates type-safe functions.

Example `sql/products/get_by_id.sql`:
```sql
SELECT id, name, price FROM products WHERE id = @id
```

Generated usage in `server_update`:
```gleam
let product = products_sql.get_by_id(db: ctx.db, id:)
```

## CLI

- `bin/dev` — codegen + build client + start server
- `bin/gen` — run lando codegen only
- `bin/build` — generate client JS bundle

## Dependencies

- `lustre` — UI framework, SSR, server components infrastructure
- `mist` — HTTP/WebSocket server
- `sqlight` — SQLite NIF (via marmot)
- `marmot` — SQL-to-Gleam codegen
- `simplifile` — filesystem scanning
- libero codegen and ETF codec — reused internally, not a user-facing dependency

## What This Isn't

- Not a libero fork or wrapper. Lando has its own conventions and codegen.
- Not a Lamdera clone in Gleam. The message-type approach is shared; the implementation (codegen vs. compiler fork) is different.
- Not server components. The execution model is SPA+RPC; the developer experience mimics server components by generating the client and owning the async boundary.

## Prior Art and Context

- elm-land: file-based routing conventions
- Lamdera: explicit ToBackend/ToFrontend message types as the client-server contract
- libero: handler-as-contract codegen, ETF wire protocol, SSR + hydration patterns
- marmot: SQL-first codegen with live SQLite introspection
- Lustre server components: proved the ergonomic target (no async state in page modules)
