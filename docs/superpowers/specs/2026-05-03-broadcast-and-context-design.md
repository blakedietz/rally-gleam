# Broadcast, Topics, and Context: Lando Framework Design

## Overview

Add four-level server-to-client messaging, session management, ClientContext/ServerContext conventions, and custom topics to Lando. Demonstrate with an elm-land/lamdera-inspired "likes" example app.

## Messaging Primitives

Four scoped effects for server-to-client messaging:

```gleam
broadcast_to_app(msg)        // every connection in the app
broadcast_to_page(msg)       // every connection on the current page
broadcast_to_session(msg)    // every connection in this browser session
send_to_client(msg)          // this one connection
```

Plus custom topics for domain-specific needs:

```gleam
lando_effect.subscribe("room:123")
lando_effect.unsubscribe("room:123")
lando_effect.broadcast_to_topic("room:123", msg)
```

### Implementation

OTP `pg` process groups. Each WebSocket handler process auto-joins three groups on connect:

- `app` (global)
- `page:<page_name>` (page-scoped, rejoined on navigation)
- `session:<session_id>` (cookie-based)

Custom topics use the same pg machinery with user-managed join/leave.

### Session Management

Cookie-based session IDs. On first HTTP request, the server sets a session cookie if one doesn't exist. On WebSocket connect, the session ID is read from the cookie and the connection joins the session's pg group. A session is a browser session (same cookie), not a user identity. Multiple tabs in the same browser share a session. Different browsers or incognito windows are separate sessions.

## Context Types

### ClientContext (client-side, cross-page state)

Defined by the user in `src/client_context.gleam`. Holds state that persists across page navigations: auth, theme, etc.

```gleam
// src/client_context.gleam
pub type ClientContext {
  ClientContext(smashed_likes: Int)
}

pub type ClientContextMsg {
  UpdateLikes(count: Int)
}

pub fn init() -> #(ClientContext, Effect(ClientContextMsg)) {
  #(ClientContext(smashed_likes: 0), effect.none())
}

pub fn update(model: ClientContext, msg: ClientContextMsg) -> #(ClientContext, Effect(ClientContextMsg)) {
  case msg {
    UpdateLikes(count) -> #(ClientContext(smashed_likes: count), effect.none())
  }
}
```

Pages receive `ClientContext` as a parameter and can emit `ClientContextMsg` to update it:

```gleam
pub fn init(ctx: ClientContext) -> #(Model, Effect(Msg))
pub fn update(ctx: ClientContext, model: Model, msg: Msg) -> #(Model, Effect(Msg))
pub fn view(ctx: ClientContext, model: Model) -> Element(Msg)
```

### ServerContext (server-side, app-wide config)

Defined by the user in `src/server_context.gleam`. Holds server-side dependencies: db connection, secrets, config.

```gleam
// src/server_context.gleam
pub type ServerContext {
  ServerContext(db: sqlight.Connection)
}
```

Passed to page server functions:

```gleam
pub fn server_init(ctx: ServerContext) -> #(ServerModel, Effect(ToClient))
pub fn server_update(model: ServerModel, msg: ToServer, ctx: ServerContext) -> #(ServerModel, Effect(ToClient))
```

Replaces the existing `Context` in `app_config.gleam`.

## Per-Page Message Types

Each page defines its own `ToServer` and `ToClient` types. The wire protocol tags messages with the page name for routing. This differs from Lamdera where all pages share one global `ToBackend`/`ToFrontend`.

```gleam
// pages/home_.gleam
pub type ToServer { SmashLike }
pub type ToClient { NewSmashedLikes(count: Int) }

// pages/counter.gleam
pub type ToServer { Increment | Decrement }
pub type ToClient { CounterNewValue(value: Int) }
```

No collision, no giant union type, each page is self-contained.

Cross-page communication goes through the topic system: a page's `server_update` can call `broadcast_to_app(ClientContextMsg)` to reach all clients regardless of what page they're on. This updates the ClientContext, which all pages can read.

## Signature Changes

### server_init

Was: `fn server_init(ctx: ServerContext) -> ServerModel`
Now: `fn server_init(ctx: ServerContext) -> #(ServerModel, Effect(ToClient))`

Enables sending initial state (e.g., current like count) to the connecting client.

### Page init/update/view

All gain a `ClientContext` parameter as the first argument:

```gleam
pub fn init(ctx: ClientContext) -> #(Model, Effect(Msg))
pub fn update(ctx: ClientContext, model: Model, msg: Msg) -> #(Model, Effect(Msg))
pub fn view(ctx: ClientContext, model: Model) -> Element(Msg)
```

## Layout

Remains view-only. Wraps page content in shared chrome (header, footer, nav). Does not hold state or handle messages. Shared client state lives in ClientContext, not the layout.

## Example App: Likes

Adapts the elm-land/lamdera starter template to Lando conventions.

### Structure

```
examples/likes/
├── gleam.toml
├── bin/dev
├── src/
│   ├── app.gleam              # Mist server setup
│   ├── server_context.gleam   # ServerContext(db: sqlight.Connection)
│   ├── client_context.gleam   # ClientContext(smashed_likes: Int)
│   └── pages/
│       ├── layout.gleam       # visual chrome
│       └── home_.gleam        # like button page
```

### home_.gleam

```gleam
pub type Model { Model }
pub type Msg { SmashedLikeButton | GotServerMsg(ToClient) }
pub type ToServer { SmashLike }
pub type ToClient { NewSmashedLikes(count: Int) }
pub type ServerModel { ServerModel }

pub fn init(_ctx: ClientContext) -> #(Model, Effect(Msg)) {
  #(Model, effect.none())
}

pub fn update(ctx: ClientContext, model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    SmashedLikeButton -> #(model, lando_effect.send_to_server(SmashLike))
    GotServerMsg(NewSmashedLikes(count)) ->
      #(model, lando_effect.send_to_client_context(UpdateLikes(count)))
  }
}

pub fn view(ctx: ClientContext, model: Model) -> Element(Msg) {
  html.div([], [
    html.h1([], [html.text("Lando Likes")]),
    html.button([event.on_click(SmashedLikeButton)], [
      html.text("👍 " <> int.to_string(ctx.smashed_likes))
    ]),
  ])
}

pub fn server_init(ctx: ServerContext) -> #(ServerModel, Effect(ToClient)) {
  let count = get_likes(ctx.db)
  #(ServerModel, send_to_client(NewSmashedLikes(count)))
}

pub fn server_update(model: ServerModel, msg: ToServer, ctx: ServerContext) -> #(ServerModel, Effect(ToClient)) {
  case msg {
    SmashLike -> {
      let count = increment_likes(ctx.db)
      #(model, broadcast_to_page(NewSmashedLikes(count)))
    }
  }
}
```

### Database

SQLite via sqlight. Single table for the like count:

```sql
CREATE TABLE IF NOT EXISTS likes (id INTEGER PRIMARY KEY, count INTEGER DEFAULT 0);
INSERT OR IGNORE INTO likes (id, count) VALUES (1, 0);
```

Helper functions in `home_.gleam` or a shared `db` module for `get_likes` and `increment_likes`.

## Approach

Example-driven with TDD:

1. Write the example code as we want it to look (target API)
2. Write tests asserting the framework supports these patterns
3. Implement framework features until tests pass
4. Update the existing counter example to the new conventions
5. Update llms.txt to document the new architecture

## Differences from Lamdera

| Feature | Lamdera | Lando |
|---------|---------|-------|
| Messaging | broadcast (all) + sendToFrontend (one) | 4 levels + custom topics |
| Message types | One global ToBackend/ToFrontend | Per-page ToServer/ToClient |
| Shared client state | Shared.Model (split across 3 files) | ClientContext (single file) |
| Server config | Part of BackendModel | ServerContext (dedicated type) |
| Topic subscriptions | N/A | Implicit (app/page/session) + explicit (custom) |
| Session tracking | Built-in SessionId | Cookie-based, same concept |
| Server state | One global BackendModel | Per-page ServerModel + database for shared state |
