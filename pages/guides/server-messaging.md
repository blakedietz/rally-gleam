# Server messaging

Rally pages communicate with the server in two ways: RPC and stateful server pages. Start with RPC. It's simpler, and most pages only need it. Reach for the stateful server model when the server needs to remember per-connection state between messages.

## RPC

RPC lets a page call a server function and get a result back. Define a message type and a handler function in your page module:

```gleam
pub type ServerLoadArticle {
  ServerLoadArticle(slug: String)
}

pub fn server_load_article(
  msg msg: ServerLoadArticle,
  server_context server_context: ServerContext,
) -> Result(Article, List(String)) {
  // query database, return result
  todo
}
```

Then call it from the client:

```gleam
effect.rpc(ServerLoadArticle(slug: "hello"), on_response: GotArticle)
```

Libero (Rally's code generation layer) reads the handler's function signature and derives the wire contract from it. The message type becomes the request shape. The return type becomes the response shape. You don't write a separate API definition, route, or serializer. The Gleam types are the contract.

If you need to load data, validate a form, or run any one-shot server operation, RPC is the right choice.

## Stateful server pages

Some pages need the server to hold onto state between messages. An example: after loading an article, you want to toggle favorites and add comments without re-fetching the article ID each time. The server keeps the `article_id` in its own model so subsequent messages can use it for authorization and queries.

Define three types and two lifecycle functions:

```gleam
pub type ToServer {
  ToggleFavorite
  AddComment(body: String)
}

pub type ToClient {
  ArticleUpdated(Article)
  CommentAdded(Comment)
}

pub type ServerModel {
  ServerModel(article_id: Int)
}

pub fn server_init(
  slug: String,
  server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  // look up the article, initialize server state
  todo
}

pub fn server_update(
  model: ServerModel,
  msg: ToServer,
  server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  // handle incoming messages, update state, push responses
  todo
}
```

The client sends messages with `effect.send_to_server`:

```gleam
effect.send_to_server(ToggleFavorite)
```

The server processes the message in `server_update` and pushes `ToClient` messages back. The page's client-side `update` function receives those messages and updates the UI.

### When to use stateful vs. RPC

Use RPC when each call is independent. Use the stateful model when the server needs to remember something between calls. A common case: `server_init` loads a resource and stores its ID in `ServerModel`. Then `server_update` can authorize and act on subsequent messages using that stored ID without the client having to send it again.

If you find yourself passing the same context (an entity ID, a session token) on every RPC call, that's a sign the page wants server state.

## Broadcast

Stateful server pages can send messages beyond the originating connection:

| Effect | Who receives it |
| --- | --- |
| `send_to_client(msg)` | One specific connection |
| `broadcast_to_session(msg)` | Every tab in the same browser session |
| `broadcast_to_page(msg)` | Every connection viewing the same page |
| `broadcast_to_app(msg)` | Every connection to the app |

Connections auto-subscribe to their relevant topics when the WebSocket connects. Under the hood, broadcast uses OTP `pg` (process groups) for topic management, so it works across nodes in a cluster without extra configuration.
