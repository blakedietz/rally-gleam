![Rally](https://github.com/pairshaped/rally/blob/master/rally.png?raw=true)

# Rally

[![Package Version](https://img.shields.io/hexpm/v/rally)](https://hex.pm/packages/rally)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/rally/)

Rally is a full-stack web framework for Gleam on the BEAM. You write Lustre page modules and `server_*` handler functions. Rally generates routing, server-side rendering, WebSocket transport, and typed client-server messaging.

The page file is the contract. Client state, server calls, and the message types that cross the wire all live together until you choose to extract shared code.

## What Rally replaces

In a typical full-stack app you write routes, server handlers, client fetch calls, request encoders, response decoders, SSR boot code, hydration flags, and WebSocket glue by hand.

Rally generates that plumbing from page modules. You still own your UI, SQL, auth policy, and server logic.

## Create an app

```sh
gleam new my_app
cd my_app
gleam add rally libero
gleam run -m rally init
bin/dev
```

`rally init` writes the starter app into the current Gleam project. `bin/dev` runs codegen, builds the JS client, and starts the server on port 8080. SQLite is the database; no separate service to install.

## Writing a page

A page file in `src/<namespace>/pages/` is a Lustre component with server calls:

```gleam
import gleam/int
import lustre/element.{type Element, text}
import lustre/element/html
import rally_runtime/effect.{type Effect}
import rally_runtime/effect
import server_context.{type ServerContext}

pub type Model {
  Model(count: Int)
}

pub type Msg {
  Increment
  GotIncrement(Result(Int, List(String)))
}

pub type ServerIncrement {
  ServerIncrement(amount: Int)
}

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model(count: 0), effect.none())
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    Increment ->
      #(model, effect.rpc(ServerIncrement(amount: 1), on_response: GotIncrement))

    GotIncrement(Ok(amount)) ->
      #(Model(count: model.count + amount), effect.none())

    GotIncrement(Error(_)) ->
      #(model, effect.none())
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.button([], [text("Count: " <> int.to_string(model.count))])
}

pub fn server_increment(
  msg msg: ServerIncrement,
  server_context _server_context: ServerContext,
) -> Result(Int, List(String)) {
  Ok(msg.amount)
}
```

`Model`, `Msg`, `init`, `update`, and `view` are normal Lustre TEA. `ServerIncrement` and `server_increment` define the server call. The client sends the typed message with `effect.rpc`.

There is no separate API schema. [Libero](https://hexdocs.pm/libero/) scans the handler signature and Rally wires it into the generated client and server code.

## File-based routing

The filename determines the URL:

| File | URL | Route variant |
|------|-----|--------------|
| `home_.gleam` or `index.gleam` | `/` | `Home` |
| `about.gleam` | `/about` | `About` |
| `products/id_.gleam` | `/products/:id` | `ProductsId(id: Int)` |
| `settings/profile.gleam` | `/settings/profile` | `SettingsProfile` |

A trailing `_` makes the segment dynamic. Params named `id` or ending in `_id` parse as `Int`; others parse as `String`.

## What to import

Most Rally apps use only a few modules directly:

| Module | Use it for |
|---|---|
| `rally_runtime/effect` | Page effects: RPC, server messages, navigation, broadcast, client context updates |
| `rally_runtime/db` | SQLite open, timed queries, nested transactions, SQL value helpers |
| `rally_runtime/system` | App startup, message logging, background jobs |
| `rally_runtime/session` | Session cookie generation, parsing, response headers |
| `rally_runtime/auth` | Auth policy and load result types |
| `rally_runtime/env` | `APP_ENV` parsing and production cookie policy |
| `rally_runtime/migrate` | Numbered SQLite migrations |
| `rally_runtime/test_db` | Fast in-memory SQLite for tests |

The `rally/internal/...` modules are codegen implementation. App code should treat them as private. The generated files under `src/generated/` are the stable boundary between Rally's internals and your app.

## Generated files

Running `gleam run -m rally` reads `[[tools.rally.clients]]` from gleam.toml and produces:

**Server-side** (in `src/generated/<namespace>/`): router, page dispatch, RPC dispatch, SSR handler, WebSocket handler, HTTP handler, protocol wire facade.

**Client-side** (in `.generated_clients/<namespace>/`): Lustre SPA entry, WebSocket transport, tree-shaken page modules, codec, effect shim.

The client package is a standalone Gleam project. The server project is the single source of truth.

## Examples

- `examples/realworld/`: [RealWorld](https://github.com/gothinkster/realworld) (Conduit) clone with auth, articles, comments, tags, favorites, follows. Uses both RPC and stateful server models. See [its README](examples/realworld/README.md).

## More docs

- [Pages](https://hexdocs.pm/rally/guides/pages.html): routing, page lifecycle, SSR loading, and layouts
- [Server messaging](https://hexdocs.pm/rally/guides/server-messaging.html): RPC, stateful server pages, and broadcast
- [Runtime](https://hexdocs.pm/rally/guides/runtime.html): the `rally_runtime/*` modules app code imports
- [Configuration](https://hexdocs.pm/rally/guides/configuration.html): `gleam.toml`, generated paths, and protocols
- [Comparisons](https://hexdocs.pm/rally/reference/comparisons.html): Rally, Lustre server components, and Lamdera-style apps
- [Internals](https://hexdocs.pm/rally/reference/internals.html): codegen pipeline and contributor reading order
- [llms.txt](https://raw.githubusercontent.com/pairshaped/rally-gleam/refs/heads/master/llms.txt): raw context for language models

## Contributing

Rally is a Gleam project targeting Erlang. You need Gleam (v1.x), Erlang/OTP 26+, SQLite3, and Node.js.

```sh
git clone <repo-url>
cd rally
gleam build
gleam test
```

Rally depends on [Libero](https://hexdocs.pm/libero/). App projects should add both packages with `gleam add rally libero`.

## Influences

- [Lamdera](https://lamdera.com): explicit server handler types as the contract, TEA on both sides
- [Lustre](https://lustre.build/): TEA, effects, and the client-side UI runtime
- [elm-land](https://elm.land): file-based routing conventions
- [Libero](https://hexdocs.pm/libero/): wire protocol and RPC contract layer
- [Marmot](https://hexdocs.pm/marmot/): SQL-first codegen with live SQLite introspection

## License

MIT. See [LICENSE](LICENSE).
