# Client-Side Page TEA Loop

Wire up the generated client app to run real per-page TEA loops, pass route params to page init, enable programmatic navigation via modem, and give layouts access to ClientContext.

## Problem

The generated client app currently:
- Creates a default page model and maps all page messages to `Noop`
- Doesn't run the page's actual init/update functions on the client
- Discards route params when pattern-matching routes
- Has no working navigation mechanism
- Doesn't call layout or pass it ClientContext

This means: clicking buttons does nothing, server push messages aren't handled, pages with route params can't load their data, and the nav bar can't show login state.

## Changes

### 1. Generated client runs real page TEA

The generated `app.gleam` stores per-page model state and dispatches page messages through the page's real update function.

**Generated app Model changes:**
```gleam
pub type Model {
  Model(
    route: router.Route,
    page_model: PageModel,
    connection: Connection,
    client_context: client_context.ClientContext,
  )
}

pub type PageModel {
  HomeModel(pages_home_.Model)
  ArticleSlugModel(pages_article_slug_.Model)
  // ... one variant per page
}
```

**Generated app Msg changes:**
```gleam
pub type Msg {
  UrlChanged(router.Route)
  PageMsg(PageMsgUnion)
  TransportConnected
  TransportDisconnected(String)
  ClientContextUpdate(client_context.ClientContextMsg)
}

pub type PageMsgUnion {
  HomeMsg(pages_home_.Msg)
  ArticleSlugMsg(pages_article_slug_.Msg)
  // ... one variant per page
}
```

**On route change:** call the page's real `init` with route params, store the returned model.

**On PageMsg:** dispatch through the page's real `update`, store the returned model, process returned effects.

**On push message:** decode the ToClient value, wrap as `GotServerMsg(value)`, dispatch as PageMsg.

### 2. Route params passed to page init

The generated route pattern match destructures params:

```gleam
// Before:
router.ArticleSlug -> { ... }

// After:
router.ArticleSlug(slug) -> {
  let #(model, effects) = article_slug.init(client_context, slug)
  ...
}
```

Page modules with dynamic segments accept params after client_context:
- `pages/article/slug_.gleam`: `init(client_context, slug: String)`
- `pages/editor/slug_.gleam`: `init(client_context, slug: String)`
- `pages/profile/username_.gleam`: `init(client_context, username: String)`

Pages without params keep the current signature: `init(client_context)`

The codegen already knows which pages have params (from the scanner's `route.params` field).

### 3. send_to_server works on client

`lando_runtime/effect.send_to_server` must actually send over WebSocket on the JavaScript target.

Approach: the generated `rpc_ffi.mjs` (already copied to the client package) exposes a `send` function. We add a JavaScript FFI binding in effect.gleam:

```gleam
pub fn send_to_server(msg: a) -> Effect(b) {
  effect.from(fn(_dispatch) {
    do_send(current_page(), msg)
    Nil
  })
}
```

Where `do_send` and `current_page` are:
- On Erlang: no-ops (server_update is called directly by the ws_handler)
- On JavaScript: call `rpc_ffi.send(url, page, msg, callback)`

The "current page" (variant name string like "ArticleSlug") needs to be available. Options:
- Store it in a module-level mutable ref (JS global)  
- The generated app sets it on each route change
- Pass it through the effect chain

Simplest: store it in a JS global that the generated app sets on route change. The `rpc_ffi.mjs` already manages WebSocket state globally.

### 4. Navigation via modem

Add `modem` as a dependency to the generated client package. Use it for:
- Intercepting `<a href="...">` clicks (client-side navigation)
- Listening for popstate (browser back/forward)
- Programmatic navigation (`modem.push`)

In the generated client app's init:
```gleam
fn init(_flags) {
  let route = router.parse_route_from_url()
  let #(page_model, page_effects) = init_page(route, client_context)
  #(Model(route:, page_model:, ...), effect.batch([
    modem.init(fn(uri) { UrlChanged(router.parse_route(uri)) }),
    page_effects,
  ]))
}
```

For programmatic navigation from page modules, add to `lando_runtime/effect`:
```gleam
pub fn navigate(path: String) -> Effect(a) {
  effect.from(fn(_dispatch) {
    do_navigate(path)
    Nil
  })
}

@external(javascript, "./lando_effect_ffi.mjs", "navigate")
fn do_navigate(_path: String) -> Nil {
  Nil
}
```

The JS FFI (`lando_effect_ffi.mjs`, placed in the lando_runtime source so it's available to the client):
```javascript
export function navigate(path) {
  globalThis.history?.pushState(null, "", path);
  globalThis.dispatchEvent(new PopStateEvent("popstate"));
}
```

This removes our custom `onPopstate` and `navigate` from `router_ffi.mjs`.

### 5. Layout gets ClientContext

Change the layout function signature convention from `layout(content)` to `layout(client_context, content)` when a `client_context.gleam` exists.

The generated client app wraps the page view with layout:
```gleam
fn view(model: Model) -> Element(Msg) {
  let page_view = render_page(model)
  layout.layout(model.client_context, page_view)
}
```

The SSR handler also passes server_context to layout (for initial HTML render, if SSR is used).

The codegen detects whether the layout module accepts a client_context parameter by checking if `client_context.gleam` exists in the project (same heuristic already used for page functions).

## What doesn't change

- Page types: Model, Msg, ToServer, ToClient, ServerModel
- Server functions: server_init, server_update (signatures unchanged)
- Effect API: send_to_client, broadcast_to_page, broadcast_to_app, broadcast_to_session, send_to_client_context
- Wire format: ETF call/push frames unchanged
- ServerContext: unchanged
- ClientContext user-defined type: unchanged (user still defines their own fields)

## Migration for existing examples

The likes example needs:
- `layout.gleam`: add `client_context: ClientContext` param
- Page modules: no change (home_ has no route params)
- `gleam.toml` client section: add modem dependency (handled by generator)

The realworld example needs:
- `layout.gleam`: add `client_context: ClientContext` param (already has the view code for nav)
- `article/slug_.gleam`, `editor/slug_.gleam`, `profile/username_.gleam`: add route param to init, send Load message
- Remove TODO comments and workaround LoadArticle/LoadProfile client-sends
- `login.gleam`, `register.gleam`: use `lando_effect.navigate("/")` after auth success

## Generator files affected

- `src/lando/generator/client.gleam` - complete rewrite of `app_gleam()` to generate real page TEA loop, modem init, layout wrapping
- `src/lando/generator/codec.gleam` - `emit_client_init` accepts route params; `emit_client_update` generates real update dispatch (not no-op)
- `src/lando/generator/client.gleam` - `client_gleam_toml()` adds modem dependency
- `src/lando/generator/client.gleam` - remove custom onPopstate/navigate from router_ffi.mjs
- `src/lando/generator/ssr_handler.gleam` - layout call passes context
- `src/lando_runtime/effect.gleam` - send_to_server and navigate with JS FFI
- New: `src/lando_runtime/lando_effect_ffi.mjs` - JS implementations of navigate and send
