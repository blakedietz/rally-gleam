# Client-Side Page TEA Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the generated client app run real per-page TEA loops so page interactions, server pushes, navigation, and layout rendering all work.

**Architecture:** The generated `app.gleam` stores per-page model state, dispatches page messages through real update functions, routes push messages as `GotServerMsg`, and uses modem for navigation. Layout wraps page content with ClientContext. The `views.gleam` codegen adapts the page's actual init/update/view (not generated defaults).

**Tech Stack:** Gleam, Lustre, modem (Lustre routing), Lando codegen generators

**Spec:** `docs/superpowers/specs/2026-05-04-client-tea-loop-design.md`

---

## File Structure

### Modified files

- `src/lando/generator/client.gleam` -- Generated app.gleam: page TEA loop, modem, layout, route param destructuring. Generated client gleam.toml: add modem dep. router_ffi.mjs: remove onPopstate (modem handles it).
- `src/lando/generator/codec.gleam` -- views.gleam: adapt real init/update from page source instead of generating defaults. Init accepts route params.
- `src/lando/generator/ssr_handler.gleam` -- Pass client/server context to layout.
- `src/lando/parser.gleam` -- Extract init and update source from page modules (like view_source).
- `src/lando/types.gleam` -- Add init_source and update_source to PageContract.
- `src/lando_runtime/effect.gleam` -- navigate function with JS FFI.

### New files

- `src/lando_runtime/lando_effect_ffi.mjs` -- JS implementations: navigate, set/get current page, send_to_server bridge.

### Example updates (after framework changes)

- `examples/realworld/src/pages/layout.gleam` -- Accept ClientContext param.
- `examples/realworld/src/pages/article/slug_.gleam` -- Init accepts slug, sends LoadArticle.
- `examples/realworld/src/pages/editor/slug_.gleam` -- Init accepts slug, sends LoadArticle.
- `examples/realworld/src/pages/profile/username_.gleam` -- Init accepts username, sends LoadProfile.
- `examples/realworld/src/pages/login.gleam` -- Use lando_effect.navigate after auth.
- `examples/realworld/src/pages/register.gleam` -- Use lando_effect.navigate after register.
- `examples/likes/src/pages/layout.gleam` -- Accept ClientContext param.

---

## Task 1: Extract init and update source from page modules

The parser currently extracts `view_source` from page modules. We need it to also extract `init_source` and `update_source` so the client codegen can adapt the real functions instead of generating defaults.

**Files:**
- Modify: `src/lando/types.gleam`
- Modify: `src/lando/parser.gleam`

- [ ] **Step 1: Add init_source and update_source to PageContract**

In `src/lando/types.gleam`, add two fields to PageContract:

```gleam
pub type PageContract {
  PageContract(
    to_server_variants: List(VariantInfo),
    to_client_variants: List(VariantInfo),
    model_variants: List(VariantInfo),
    msg_variants: List(VariantInfo),
    has_server_update: Bool,
    has_server_init: Bool,
    has_load: Bool,
    has_init: Bool,
    has_model: Bool,
    param_names: List(String),
    view_source: String,
    init_source: String,
    update_source: String,
  )
}
```

- [ ] **Step 2: Extract init and update source in parser**

In `src/lando/parser.gleam`, follow the same pattern as `extract_view_source` to create `extract_init_source` and `extract_update_source` functions. These extract the function body from the page source file.

Read the existing `extract_view_source` function to understand the pattern, then replicate it for `init` and `update`. Add the new fields to the PageContract construction.

- [ ] **Step 3: Fix all existing call sites**

Search for all places that construct or pattern-match PageContract (tests, generators) and add the new fields. For test fixtures, set `init_source: ""` and `update_source: ""`.

- [ ] **Step 4: Run tests**

```bash
gleam test
```

All 103 tests should pass. Update birdie snapshots if needed.

- [ ] **Step 5: Commit**

```bash
git add src/lando/types.gleam src/lando/parser.gleam
git commit -m "Extract init and update source from page modules"
```

---

## Task 2: Adapt real init/update in views.gleam codegen

Replace the generated default init/update in `codec.gleam` with adapted versions of the page's actual functions (same approach used for view_source).

**Files:**
- Modify: `src/lando/generator/codec.gleam`

- [ ] **Step 1: Replace emit_client_init with adapt_init_source**

In `codec.gleam`, create an `adapt_init_source` function following the same pattern as `adapt_view_source`. It should:
- Rename `fn init(` to `fn {fn_suffix}_init(`
- Replace `Model` type references with `{Prefix}Model`
- Replace `Msg` type references with `{Prefix}Msg`
- Replace `Effect(Msg)` with `Effect({Prefix}Msg)`

When `init_source` is empty (no init function found), fall back to the current `emit_client_init` default.

The init function signature variations to handle:
- `fn init(client_context: ClientContext)` -- no route params
- `fn init(client_context: ClientContext, slug: String)` -- with route params
- `fn init(_client_context: ClientContext)` -- unused context
- `fn init(_client_context: ClientContext, slug: String)` -- unused context + params

- [ ] **Step 2: Replace emit_client_update with adapt_update_source**

Same pattern. Create `adapt_update_source` that renames and prefixes types. When `update_source` is empty, fall back to the current default.

The update function signature variations:
- `fn update(client_context: ClientContext, model: Model, msg: Msg)`
- `fn update(_client_context: ClientContext, model: Model, msg: Msg)`

- [ ] **Step 3: Update emit_page_view_block to use the new functions**

Wire the new adaptation functions into `emit_page_view_block`.

- [ ] **Step 4: Run tests and update snapshots**

```bash
gleam test
gleam run -m birdie
```

- [ ] **Step 5: Commit**

```bash
git add src/lando/generator/codec.gleam
git commit -m "Adapt real page init/update in client views codegen"
```

---

## Task 3: Generate real page TEA loop in client app

Rewrite the generated `app.gleam` to store per-page model state, dispatch page messages through real update functions, and handle route changes by calling page init.

**Files:**
- Modify: `src/lando/generator/client.gleam`

- [ ] **Step 1: Generate PageModel and PageMsg union types**

Add functions to generate the PageModel and PageMsg union types from page contracts:

```gleam
// Generated types:
pub type PageModel {
  HomePageModel(views.HomeModel)
  ArticleSlugPageModel(views.ArticleSlugModel)
  // ...
  NoPageModel
}

pub type PageMsg {
  HomePageMsg(views.HomeMsg)
  ArticleSlugPageMsg(views.ArticleSlugMsg)
  // ...
}
```

- [ ] **Step 2: Add PageModel and PageMsg to app Model/Msg**

Replace the current `render_page` approach. The app Model stores `page_model: PageModel`. The app Msg has `PageMsg(PageMsg)` instead of `Noop`.

- [ ] **Step 3: Generate init_page function**

Generate a function that matches the current route and calls the appropriate page init:

```gleam
fn init_page(route: router.Route, client_context: client_context.ClientContext) -> #(PageModel, Effect(Msg)) {
  case route {
    router.Home -> {
      let #(m, e) = views.home_init(client_context)
      #(HomePageModel(m), effect.map(e, fn(msg) { PageMsg(HomePageMsg(msg)) }))
    }
    router.ArticleSlug(slug) -> {
      let #(m, e) = views.article_slug_init(client_context, slug)
      #(ArticleSlugPageModel(m), effect.map(e, fn(msg) { PageMsg(ArticleSlugPageMsg(msg)) }))
    }
    // ...
    router.NotFound(_) -> #(NoPageModel, effect.none())
  }
}
```

Note: route params are destructured and passed to init.

- [ ] **Step 4: Generate update_page function**

```gleam
fn update_page(page_model: PageModel, page_msg: PageMsg, client_context: client_context.ClientContext) -> #(PageModel, Effect(Msg)) {
  case page_model, page_msg {
    HomePageModel(m), HomePageMsg(msg) -> {
      let #(new_m, e) = views.home_update(client_context, m, msg)
      #(HomePageModel(new_m), effect.map(e, fn(msg) { PageMsg(HomePageMsg(msg)) }))
    }
    // ...
    _, _ -> #(page_model, effect.none())
  }
}
```

- [ ] **Step 5: Generate render_page function**

```gleam
fn render_page(page_model: PageModel, client_context: client_context.ClientContext) -> Element(Msg) {
  case page_model {
    HomePageModel(m) ->
      element.map(views.home_view(client_context, m), fn(msg) { PageMsg(HomePageMsg(msg)) })
    // ...
    NoPageModel -> html.div([], [html.text("Page not found")])
  }
}
```

- [ ] **Step 6: Update app init to call init_page**

The app init calls `init_page(route, client_context)` and stores the result in `page_model`.

- [ ] **Step 7: Update app update for PageMsg and UrlChanged**

`PageMsg(page_msg)` dispatches through `update_page`. `UrlChanged(route)` calls `init_page` for the new route (reinitializing page state on navigation).

- [ ] **Step 8: Update app view to use render_page with page_model**

The view calls `render_page(model.page_model, model.client_context)`.

- [ ] **Step 9: Run tests and update snapshots**

```bash
gleam test
gleam run -m birdie
```

- [ ] **Step 10: Commit**

```bash
git add src/lando/generator/client.gleam
git commit -m "Generate real page TEA loop in client app"
```

---

## Task 4: Wire push handlers to page update

The generated push handler registrations currently discard messages. Wire them to dispatch `GotServerMsg` through the page update.

**Files:**
- Modify: `src/lando/generator/client.gleam`

- [ ] **Step 1: Update push registrations in generated main()**

Change push handler registration from:
```gleam
let _ = transport.register_push_handler("Home", fn(_msg) { Nil })
```

To dispatch through Lustre:
```gleam
// In the init effect, after getting the dispatch function:
let _ = transport.register_push_handler("Home", fn(msg) {
  dispatch(PageMsg(HomePageMsg(views.HomeGotServerMsg(msg))))
})
```

Wait, this won't work because the push handler is registered in `main()` before the Lustre app starts. We need the push handlers to dispatch into the running Lustre app.

Alternative approach: register push handlers inside `init_transport` effect which has access to `dispatch`:

```gleam
fn init_transport() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    let _ = transport.init("/ws")
    let _ = transport.register_on_connect(fn() { dispatch(TransportConnected) })
    let _ = transport.register_on_disconnect(fn(reason) { dispatch(TransportDisconnected(reason)) })
    // Push handlers:
    let _ = transport.register_push_handler("Home", fn(msg) {
      dispatch(PageMsg(HomePageMsg(views.HomeGotServerMsg(msg))))
    })
    // ...
    Nil
  })
}
```

The `views.HomeGotServerMsg` is the `GotServerMsg` variant from the page's Msg type, prefixed. This constructs the right page message from the push data.

But `GotServerMsg` takes a `ToClient` value, and the push msg is a raw `Dynamic`. We need to decode it first. The generated `codec.gleam` has decode functions. So:

```gleam
let _ = transport.register_push_handler("Home", fn(raw_msg) {
  let decoded = codec.decode_home_to_frontend(transport.encode(raw_msg))
  dispatch(PageMsg(HomePageMsg(views.HomeGotServerMsg(decoded))))
})
```

Actually, the raw_msg from the push handler is already decoded by rpc_ffi.mjs. It comes as a Dynamic Gleam value. So casting it should work:

```gleam
let _ = transport.register_push_handler("Home", fn(msg) {
  // msg is the decoded ToClient value
  dispatch(PageMsg(HomePageMsg(views.HomeGotServerMsg(msg))))
})
```

Check what `rpc_ffi.mjs` `registerPushHandler` actually provides. The handler receives the decoded push value.

- [ ] **Step 2: Move push registrations from main() to init_transport()**

Update the generated code so push registrations happen inside the `init_transport` effect.

- [ ] **Step 3: Import codec module in generated app**

Add `import generated/codec` to the generated app imports.

- [ ] **Step 4: Run tests and update snapshots**

```bash
gleam test
gleam run -m birdie
```

- [ ] **Step 5: Commit**

```bash
git add src/lando/generator/client.gleam
git commit -m "Wire push handlers to dispatch page messages"
```

---

## Task 5: Add modem for navigation

Replace custom popstate/navigate handling with the modem package.

**Files:**
- Modify: `src/lando/generator/client.gleam`
- Modify: `src/lando_runtime/effect.gleam`
- Create: `src/lando_runtime/lando_effect_ffi.mjs`

- [ ] **Step 1: Add modem to generated client gleam.toml**

In `client_gleam_toml()`, add modem:

```gleam
fn client_gleam_toml() -> String {
  "name = \"client\"
version = \"0.1.0\"
target = \"javascript\"

[dependencies]
gleam_stdlib = \">= 0.60.0 and < 2.0.0\"
lustre = \">= 5.6.0 and < 7.0.0\"
modem = \">= 2.0.0 and < 3.0.0\"
"
}
```

Check modem's actual version range on hex.pm and adjust.

- [ ] **Step 2: Replace onPopstate with modem.init in generated app**

In the generated app's init, replace the custom popstate handling with modem:

```gleam
import modem

fn init(_flags: Nil) -> #(Model, Effect(Msg)) {
  let route = router.parse_route_from_url()
  let #(page_model, page_effects) = init_page(route, client_context)
  #(Model(route:, page_model:, ...), effect.batch([
    modem.init(fn(uri) { UrlChanged(router.parse_route(uri)) }),
    init_transport(),
    page_effects,
  ]))
}
```

Remove `router.on_popstate(...)` from `init_transport()`.

- [ ] **Step 3: Remove onPopstate from router_ffi.mjs and client_router**

In `router_ffi_mjs()`, remove the `onPopstate` export.
In `client_router()`, remove the `on_popstate` FFI declaration.

Keep `navigate` and `currentUrl` since they're still useful.

- [ ] **Step 4: Add navigate to lando_runtime/effect.gleam**

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

- [ ] **Step 5: Create lando_effect_ffi.mjs**

Create `src/lando_runtime/lando_effect_ffi.mjs`:

```javascript
export function navigate(path) {
  globalThis.history?.pushState(null, "", path);
  globalThis.dispatchEvent(new PopStateEvent("popstate"));
}
```

- [ ] **Step 6: Run tests and update snapshots**

```bash
gleam test
gleam run -m birdie
```

- [ ] **Step 7: Commit**

```bash
git add src/lando/generator/client.gleam src/lando_runtime/effect.gleam src/lando_runtime/lando_effect_ffi.mjs
git commit -m "Add modem for navigation, add lando_effect.navigate"
```

---

## Task 6: Layout gets ClientContext

Change the layout function call to pass ClientContext when available.

**Files:**
- Modify: `src/lando/generator/client.gleam`
- Modify: `src/lando/generator/ssr_handler.gleam`

- [ ] **Step 1: Wrap page view with layout in generated client app**

In the generated app's `view` function, wrap the page content with layout:

```gleam
fn view(model: Model) -> Element(Msg) {
  let page_view = render_page(model.page_model, model.client_context)
  html.div([attr.class("lando-app")], [
    layout.layout(model.client_context, page_view),
    connection_banner(model.connection),
    toast_container(model.toasts),
  ])
}
```

Add `import pages/layout` to the generated imports. Only add the `client_context` argument when `has_client_context` is true. When false, call `layout.layout(page_view)` as before.

- [ ] **Step 2: Update SSR handler to pass context to layout**

In `src/lando/generator/ssr_handler.gleam`, change the layout call from:
```gleam
layout <> ".layout(page_view)"
```
to:
```gleam
layout <> ".layout(server_context, page_view)"
```

Wait, the SSR handler has ServerContext, not ClientContext. The layout signature needs to work for both. Since SSR is server-side, the layout might need a different signature there, or we skip the context for SSR and just render with an empty/default context.

For now: keep the SSR handler as-is (layout without context). The SSR handler is for initial page loads, and the nav will be rendered correctly once the client TEA takes over. This is a minor visual flash but avoids complicating the layout type signature.

- [ ] **Step 3: Run tests and update snapshots**

```bash
gleam test
gleam run -m birdie
```

- [ ] **Step 4: Commit**

```bash
git add src/lando/generator/client.gleam
git commit -m "Wrap page views with layout, pass ClientContext"
```

---

## Task 7: send_to_server works on client

Make `lando_runtime/effect.send_to_server` actually send over WebSocket on the JavaScript target.

**Files:**
- Modify: `src/lando_runtime/effect.gleam`
- Modify: `src/lando_runtime/lando_effect_ffi.mjs`

- [ ] **Step 1: Add current page tracking to JS FFI**

In `lando_effect_ffi.mjs`, add a module-level variable for the current page and a send function:

```javascript
let _currentPage = "";
let _sendFn = null;

export function setCurrentPage(page) {
  _currentPage = page;
}

export function getCurrentPage() {
  return _currentPage;
}

export function setSendFn(fn) {
  _sendFn = fn;
}

export function sendToServer(msg) {
  if (_sendFn && _currentPage) {
    _sendFn(_currentPage, msg);
  }
}
```

- [ ] **Step 2: Update effect.gleam send_to_server**

```gleam
pub fn send_to_server(msg: a) -> Effect(b) {
  do_send_to_server(msg)
  effect.none()
}

@external(javascript, "./lando_effect_ffi.mjs", "sendToServer")
fn do_send_to_server(_msg: a) -> Nil {
  Nil
}
```

- [ ] **Step 3: Wire current page and send function in generated app**

In the generated app's `init_page` or route change handler, call `setCurrentPage` with the variant name string. In `init_transport`, call `setSendFn` with `transport.send_to_server`.

Add to `lando_effect_ffi.mjs`:
```javascript
export function navigate(path) { ... }
export function setCurrentPage(page) { ... }
export function getCurrentPage() { ... }
export function setSendFn(fn) { ... }
export function sendToServer(msg) { ... }
```

The generated `init_transport` sets up the send function:
```gleam
// In init_transport effect:
let _ = lando_effect_ffi.set_send_fn(transport.send_to_server)
```

And route changes update the current page:
```gleam
// In init_page or UrlChanged handler:
let _ = lando_effect_ffi.set_current_page(page_name_string)
```

The FFI imports in the generated app need the right paths. Since `lando_effect_ffi.mjs` is in the `lando_runtime` package, the import path in the generated app would be through the lando dependency.

- [ ] **Step 4: Run tests**

```bash
gleam test
```

- [ ] **Step 5: Commit**

```bash
git add src/lando_runtime/effect.gleam src/lando_runtime/lando_effect_ffi.mjs src/lando/generator/client.gleam
git commit -m "Make send_to_server work on JavaScript target"
```

---

## Task 8: Update realworld example

Update the realworld example pages to use the new framework features. Remove TODO workarounds.

**Files:**
- Modify: `examples/realworld/src/pages/layout.gleam`
- Modify: `examples/realworld/src/pages/article/slug_.gleam`
- Modify: `examples/realworld/src/pages/editor/slug_.gleam`
- Modify: `examples/realworld/src/pages/profile/username_.gleam`
- Modify: `examples/realworld/src/pages/login.gleam`
- Modify: `examples/realworld/src/pages/register.gleam`
- Modify: `examples/likes/src/pages/layout.gleam`

- [ ] **Step 1: Update realworld layout to accept ClientContext**

```gleam
import gleam/option.{None, Some}
import client_context.{type ClientContext}
import lustre/attribute as attr
import lustre/element.{type Element}
import lustre/element/html

pub fn layout(client_context: ClientContext, content: Element(msg)) -> Element(msg) {
  html.div([], [
    nav(client_context),
    content,
    footer_view(),
  ])
}

fn nav(client_context: ClientContext) -> Element(msg) {
  html.nav([attr.class("navbar navbar-light")], [
    html.div([attr.class("container")], [
      html.a([attr.class("navbar-brand"), attr.href("/")], [html.text("conduit")]),
      html.ul([attr.class("nav navbar-nav pull-xs-right")],
        case client_context.current_user {
          None -> [
            nav_link("/", "Home"),
            nav_link("/login", "Sign in"),
            nav_link("/register", "Sign up"),
          ]
          Some(user) -> [
            nav_link("/", "Home"),
            nav_link("/editor", "New Article"),
            nav_link("/settings", "Settings"),
            nav_link("/profile/" <> user.username, user.username),
          ]
        }),
    ]),
  ])
}

fn nav_link(href: String, label: String) -> Element(msg) {
  html.li([attr.class("nav-item")], [
    html.a([attr.class("nav-link"), attr.href(href)], [html.text(label)]),
  ])
}

fn footer_view() -> Element(msg) {
  html.footer([], [
    html.div([attr.class("container")], [
      html.a([attr.class("logo-font"), attr.href("/")], [html.text("conduit")]),
      html.span([attr.class("attribution")], [
        html.text("Built with "),
        html.a([attr.href("https://github.com/lando")], [html.text("Lando")]),
      ]),
    ]),
  ])
}
```

- [ ] **Step 2: Update article/slug_.gleam init to accept slug**

Change init from `init(_client_context: ClientContext)` to `init(_client_context: ClientContext, slug: String)` and send `LoadArticle(slug)` immediately. Remove the TODO comments.

- [ ] **Step 3: Update editor/slug_.gleam init to accept slug**

Same pattern: accept slug param, send `LoadArticle(slug)` in init.

- [ ] **Step 4: Update profile/username_.gleam init to accept username**

Accept username param, send `LoadProfile(username)` in init.

- [ ] **Step 5: Update login.gleam and register.gleam with navigate**

Replace the no-op `navigate_effect` with `lando_effect.navigate("/")`:

```gleam
import lando_runtime/effect as lando_effect

// In update for GotServerMsg(Authenticated(...)):
GotServerMsg(Authenticated(username, image)) -> #(model,
  effect.batch([
    lando_effect.send_to_client_context(SignedIn(User(username:, image:))),
    lando_effect.navigate("/"),
  ]))
```

- [ ] **Step 6: Update likes layout**

Add `client_context: ClientContext` as first param to `examples/likes/src/pages/layout.gleam`.

- [ ] **Step 7: Commit**

```bash
git add examples/realworld/src/pages/ examples/likes/src/pages/layout.gleam
git commit -m "Update examples with route params, navigation, and layout context"
```

---

## Task 9: Update llms.txt and run full test suite

**Files:**
- Modify: `llms.txt`

- [ ] **Step 1: Update llms.txt**

Update the page module contract to show init with route params. Add modem to the dependencies section. Note the layout convention change.

- [ ] **Step 2: Run full test suite**

```bash
gleam test
```

All tests should pass. Update birdie snapshots if needed.

- [ ] **Step 3: Commit and push**

```bash
git add llms.txt
git commit -m "Update llms.txt for client TEA loop changes"
git push
```

---

## Deferred Items

These items are out of scope for this plan and should be tracked in beans:

1. **send_to_client_context on JS target** -- Currently a server-side no-op. For the full client TEA loop, it should dispatch `ClientContextUpdate` messages through Lustre. The generated app's push handler or page update function needs to intercept effects that contain `send_to_client_context` calls and translate them to `ClientContextUpdate` messages. This is complex because Lustre effects are opaque. Defer until we test the example end-to-end and confirm it's needed.

2. **SSR layout with context** -- The SSR handler calls `layout(page_view)` without context. For server-rendered pages, the nav bar won't show login state on first load (it corrects after the client TEA takes over). A proper fix would pass a pre-populated context based on the session. Defer until SSR is a priority.

3. **Route params in server_init** -- server_init still doesn't receive route params. The pattern of client init sending a Load message via send_to_server works, but adds a round-trip. A future optimization could include route params in the first WebSocket message. Defer until performance is a concern.
