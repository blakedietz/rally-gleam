# Realworld (Conduit)

A [RealWorld](https://github.com/gothinkster/realworld) implementation built with Rally. Users can publish articles, comment, follow authors, and favorite posts. The app demonstrates most of Rally's features: file-based routing, SSR with hydration, bidirectional WebSocket messaging, session auth, and the shared ClientContext pattern.

## Running it

```sh
bin/dev
# => http://localhost:8080
```

This runs marmot codegen (SQL), Rally codegen (routes, handlers, client), builds the JS client, and starts the server.

## What's here

### Pages

| File | Route | What it does |
|------|-------|-------------|
| `home_.gleam` | `/` | Global feed, your feed, tag filtering. SSR with `load`. |
| `login.gleam` | `/login` | Email/password login, creates session |
| `register.gleam` | `/register` | New user registration |
| `editor.gleam` | `/editor` | Create article |
| `editor/slug_.gleam` | `/editor/:slug` | Edit existing article |
| `article/slug_.gleam` | `/article/:slug` | Article view with comments, favorites, follows |
| `profile/username_.gleam` | `/profile/:username` | User profile with their articles |
| `settings.gleam` | `/settings` | Update bio, image, password |
| `layout.gleam` | (all pages) | Navbar + footer, auth-aware navigation |

### Database

SQLite with marmot-generated query modules. Tables: `users`, `articles`, `tags`, `article_tags`, `comments`, `favorites`, `follows`, `sessions`.

SQL files live in `src/sql/` organized by domain (`auth/`, `articles/`, `comments/`, `tags/`, `users/`, `favorites/`, `follows/`). Migrations in `migrations/`.

### Server context

`server_context.gleam` holds the database connection. Passed to all `server_update` and `load` functions.

### Client context

`client_context.gleam` holds `current_user: Option(User)` (username + image). Two things worth noting:

- **`from_session`**: the SSR handler calls `client_context.from_session(server_context, session_id)` to look up the authenticated user before rendering. This means server-rendered pages show the correct nav links without a client round-trip.
- **`update`**: handles `SignedIn`/`SignedOut` messages. Pages trigger these via `send_to_client_context` after login/logout, which updates the navbar across all pages.

## Architecture

Each page follows the same pattern:

1. **Client types**: `Model`, `Msg`, `ToServer`, `ToClient`
2. **Client functions**: `init`, `update`, `view` (all receive `ClientContext`)
3. **Server types**: `ServerModel`
4. **Server functions**: `server_init`, `server_update` (receive `ServerContext`)
5. **SSR** (optional): `load` returns initial `Model` from the database

The login flow is a good example of how the pieces connect: the client sends `SubmitLogin(email, password)` as a `ToServer` message, `server_update` validates credentials and creates a session, then sends back `LoginSuccess(token)` as a `ToClient` message plus `send_to_client_context(SignedIn(user))` to update the navbar, and the client calls `navigate("/")` to go home.

## What Rally provides vs. what's hand-written

**Generated** (`src/generated/`, `client/src/generated/`): router, SSR handler, WebSocket handler, client app shell, transport layer, codec, type mirrors. These are regenerated on every `bin/dev` run.

**Hand-written**: everything in `src/pages/`, `src/sql/`, `server_context.gleam`, `client_context.gleam`, `app.gleam`, and supporting modules like `password.gleam` and `datetime.gleam`.
