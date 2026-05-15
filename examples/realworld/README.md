# Realworld (Conduit)

A [RealWorld](https://github.com/gothinkster/realworld) implementation built with Rally. Users can publish articles, comment, follow authors, and favorite posts. The app demonstrates most of Rally's features: file-based routing, SSR with hydration, session auth, the shared ClientContext pattern, and both of Rally's server communication models.

## Running it

```sh
gleam run -m rally migrate
gleam run -m rally build
gleam run
# => http://localhost:8080
```

`rally migrate` applies migrations to `db/realworld.db` and runs Marmot SQL codegen. `rally build` runs Rally codegen (routes, handlers, client) and builds the ignored JS client in `.generated_clients/public`. Runtime database files live under `db/`, including Rally's `db/system.db`. To use a different port, set `PORT` in `.env` or run `PORT=8081 gleam run`.

## What's here

### Pages

| File | Route | What it does | Server model |
|------|-------|-------------|--------------|
| `home_.gleam` | `/` | Global feed, your feed, tag filtering. SSR with `load`. | RPC |
| `login.gleam` | `/login` | Email/password login, creates session | RPC |
| `register.gleam` | `/register` | New user registration | RPC |
| `editor.gleam` | `/editor` | Create article | RPC |
| `editor/slug_.gleam` | `/editor/:slug` | Edit existing article | Stateful |
| `article/slug_.gleam` | `/article/:slug` | Article view with comments, favorites, follows | Stateful |
| `profile/username_.gleam` | `/profile/:username` | User profile with their articles | Stateful |
| `settings.gleam` | `/settings` | Update bio, image, password | RPC |
| `layout.gleam` | (all pages) | Navbar + footer, auth-aware navigation | -- |

### Two server communication models

Rally supports two ways for pages to talk to the server. This app uses both, so you can compare them side by side.

**RPC (stateless request-response).** Define a single-variant message type and a `server_*` handler function. The client calls it with `rally_effect.rpc`, the server runs the function and returns the result. No server-side state between calls. Used by `login.gleam`, `register.gleam`, `home_.gleam`, `editor.gleam`, `settings.gleam`.

```gleam
// in login.gleam

// The type is both the handler's input and the client's constructor
pub type ServerLogin { ServerLogin(email: String, password: String) }

// Libero discovers this handler automatically
pub fn server_login(msg msg: ServerLogin, server_context server_context: ServerContext)
  -> Result(#(String, String), List(String))

// Client calls it directly
rally_effect.rpc(ServerLogin(email: model.email, password: model.password), on_response: GotLogin)
```

**Stateful (bidirectional messaging).** Define `ToServer`/`ToClient` message types and a `ServerModel`. The server keeps a `ServerModel` per connection via `server_init`/`server_update`. The server can push `ToClient` messages to the client at any time. Used by `article/slug_.gleam`, `editor/slug_.gleam`, `profile/username_.gleam`, where the server tracks entity ownership for authorization between actions.

```gleam
// in article/slug_.gleam

pub type ToServer { ToggleFavorite; AddComment(body: String); DeleteComment(id: Int) }
pub type ToClient { ArticleUpdated(Article); CommentAdded(Comment); CommentDeleted(Int) }
pub type ServerModel { ServerModel(article_id: Int, author_id: Int); ServerModelEmpty }

pub fn server_init(slug, server_context) -> #(ServerModel, Effect(ToClient))
pub fn server_update(model, msg, server_context) -> #(ServerModel, Effect(ToClient))
```

**When to use which:** Start with RPC. It's simpler, stateless, and covers most cases. Use stateful when you need the server to remember something between calls (like an entity ID for authorization) or push messages to the client without a request.

### Database

SQLite with marmot-generated query modules. Tables: `users`, `articles`, `tags`, `article_tags`, `comments`, `favorites`, `follows`, `sessions`.

SQL files live in `src/sql/` organized by domain (`auth/`, `articles/`, `comments/`, `tags/`, `users/`, `favorites/`, `follows/`). Migrations live in `migrations/`. Local database files live in ignored `db/`.

### Server context

`server_context.gleam` holds the database connection. Passed to all `server_*` handlers and `load` functions.

### Client context

`client_context.gleam` holds `current_user: Option(User)` (username + image). Two things worth noting:

- **`from_session`**: the SSR handler calls `client_context.from_session(server_context, session_id)` to look up the authenticated user before rendering. This means server-rendered pages show the correct nav links without a client round-trip.
- **`update`**: handles `SignedIn`/`SignedOut` messages. Pages trigger these via `send_to_client_context` after login/logout, which updates the navbar across all pages.

## Architecture

Each page has a client side (standard Lustre TEA) and optionally a server side:

1. **Client types**: `Model`, `Msg` (all pages)
2. **Client functions**: `init`, `update`, `view`, all receiving `ClientContext` (all pages)
3. **SSR** (optional): `load` returns initial `Model` from the database
4. **Server handlers** (one of):
   - **RPC**: `ServerX` message type + `server_x` function per endpoint
   - **Stateful**: `ToServer`/`ToClient`/`ServerModel` + `server_init`/`server_update`

The login flow shows how RPC pages work: the client calls `rally_effect.rpc(ServerLogin(email, password), on_response: GotLogin)`. `server_login` validates credentials and creates a session. On success, the client receives `Ok(#(username, image))`, sends `send_to_client_context(SignedIn(user))` to update the navbar, and calls `navigate("/")`.

The article page shows how stateful pages work: `server_init` loads the article and stores its ID in `ServerModel`. When the client sends `ToggleFavorite` via the `ToServer` channel, `server_update` uses the stored `article_id` for the database query and pushes an `ArticleUpdated` message back as `ToClient`.

## What Rally provides vs. what's hand-written

**Generated** (`src/generated/public/`, `.generated_clients/public/src/generated/`): router, SSR handler, WebSocket handler, client app shell, transport layer, codec, type mirrors. The client package lives under ignored `.generated_clients/public` so generated SPA code stays out of the repository.

**Hand-written**: everything in `src/public/pages/`, `src/sql/`, `src/server_context.gleam`, `src/public/client_context.gleam`, `src/realworld.gleam`, and supporting modules like `password.gleam` and `datetime.gleam`.
