# Pages

Rally pages are Lustre TEA modules under `src/<namespace>/pages/`. Each page owns its browser model, messages, update function, and view.

## Required exports

| Export | Purpose |
|---|---|
| `pub type Model` | Browser state for the page |
| `pub type Msg` | Browser messages for the page |
| `pub fn init(...)` | Create the first model and effect |
| `pub fn update(...)` | Handle browser messages |
| `pub fn view(...)` | Render Lustre elements |

Apps that define a `client_context.gleam` file receive `ClientContext` as the first argument to `init`, `update`, and `view`. Apps without a client context use shorter signatures:

```gleam
// With client context
pub fn init(client_context: ClientContext) -> #(Model, Effect(Msg))
pub fn update(client_context: ClientContext, model: Model, msg: Msg) -> #(Model, Effect(Msg))
pub fn view(client_context: ClientContext, model: Model) -> Element(Msg)

// Without client context
pub fn init() -> #(Model, Effect(Msg))
pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg))
pub fn view(model: Model) -> Element(Msg)
```

Dynamic route pages also receive their params. For example, a page at `products/id_.gleam` adds the param after the context argument (or as the first argument when there is no context):

```gleam
pub fn init(client_context: ClientContext, id: Int) -> #(Model, Effect(Msg))
```

## File-based routing

| File | URL | Route variant |
|---|---|---|
| `home_.gleam` or `index.gleam` | `/` | `Home` |
| `about.gleam` | `/about` | `About` |
| `products/id_.gleam` | `/products/:id` | `ProductsId(id: Int)` |
| `settings/profile.gleam` | `/settings/profile` | `SettingsProfile` |

`home_.gleam` is reserved for the root path `/`. `index.gleam` maps to whatever directory it sits in. Outside those root-page cases, a file or directory segment ending in `_` becomes a dynamic parameter.

Params named `id` or ending in `_id` parse as `Int`. Other params parse as `String`. For instance, `profile/username_.gleam` produces `ProfileUsername(username: String)`, while `article/id_.gleam` produces `ArticleId(id: Int)`.

Rally generates a typed `Route` variant for each page. The generated router handles URL parsing, path building, and `href` helpers.

## SSR loading

Pages can pre-fetch server data so the first render arrives fully populated. Two optional exports control this:

- `pub fn load(...)` runs on the server before the first render. It receives `ServerContext` (and route params for dynamic pages) and returns data the page needs.
- `pub fn init_loaded(...)` runs on the client at boot. It receives the data from `load` (decoded from embedded flags) and returns a `#(Model, Effect(Msg))` pair, replacing the normal `init`.

The flow works like this:

1. Browser requests a page.
2. The server calls `load`, which fetches data (from a database, an API, wherever).
3. Rally renders the page HTML using that data, and embeds the model as flags in the response.
4. The client boots, decodes the flags, and calls `init_loaded` to build the initial model and effect.

When a page defines `load` without `init_loaded`, the return value of `load` is the `Model` itself, and Rally uses it directly for both server-side rendering and client hydration.

Here is a simplified example from `examples/realworld/src/public/pages/home_.gleam`:

```gleam
// load runs on the server before the HTML response
pub fn load(server_context: ServerContext) -> Model {
  let assert Ok(rows) =
    articles_sql.list_global(db: server_context.db, limit: 10, offset: 0)
  let assert Ok(tag_rows) = tags_sql.list_popular(db: server_context.db)
  Model(
    articles: list.map(rows, to_preview),
    tags: list.map(tag_rows, fn(r) { r.name }),
    active_tab: GlobalFeed,
    page: 1,
    total: 0,
  )
}
```

In this case, `load` returns a `Model` directly. The client boots with that model already populated, so the user sees articles and tags on the first paint with no loading spinner.

When `load` returns a separate data type (not `Model`), define `init_loaded` to transform it:

```gleam
pub fn load(server_context: ServerContext) -> SomeData {
  // fetch and return server data
}

pub fn init_loaded(client_context: ClientContext, data: SomeData) -> #(Model, Effect(Msg)) {
  // build the client model from the pre-fetched data
  #(model_from_data(data), effect.none())
}
```

See `examples/realworld/` for working SSR loading patterns across several pages.

## Layouts

`layout.gleam` files provide shared page chrome (navigation bars, footers, wrappers). Rally assigns the nearest `layout.gleam` above a page's route, walking up from the page's directory.

A layout exports a single `layout` function:

```gleam
pub fn layout(
  client_context: ClientContext,
  _on_context_msg: fn(ClientContextMsg) -> msg,
  content: Element(msg),
) -> Element(msg) {
  html.div([], [
    nav(client_context),
    content,
    footer_view(),
  ])
}
```

The `content` argument is the rendered page element. The `on_context_msg` callback lets the layout dispatch messages that update the client context (for example, logging out from a nav bar).

Place a `layout.gleam` at any directory level. Pages in that directory and its subdirectories will use it. A deeper `layout.gleam` overrides a shallower one for the pages beneath it.
