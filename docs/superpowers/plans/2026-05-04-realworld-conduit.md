# Realworld (Conduit) Example Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a full Conduit (Medium clone) example app demonstrating Lando's capabilities with auth, articles, comments, favorites, follows, tags, pagination, and real-time broadcasts.

**Architecture:** Flat page modules with no shared domain layer. SQLite tables are the data model, each page defines its own marmot SQL queries. Auth is session-based with bcrypt password hashing. Real-time updates via broadcast_to_page/broadcast_to_app after mutations. Conduit CSS via CDN for styling.

**Tech Stack:** Gleam, Lustre, Mist, SQLite (sqlight), Marmot (SQL codegen), Lando (framework + codegen), Erlang crypto (password hashing), Birdie (snapshot tests)

**Spec:** `docs/superpowers/specs/2026-05-04-realworld-example-design.md`

**Reference app:** https://github.com/elm-land/realworld-app

---

## File Structure

### Framework changes (in lando core)

- Modify: `src/lando_runtime/effect.gleam` -- make `get_ws_session` public
- Modify: `src/lando/generator/client.gleam` -- add popstate routing listener

### New example: `examples/realworld/`

```
examples/realworld/
├── migrations/
│   └── 001_init.sql
├── src/
│   ├── app.gleam
│   ├── server_context.gleam
│   ├── client_context.gleam
│   ├── password.gleam
│   ├── slug.gleam
│   ├── password_ffi.erl
│   ├── pages/
│   │   ├── layout.gleam
│   │   ├── home_.gleam
│   │   ├── login.gleam
│   │   ├── register.gleam
│   │   ├── settings.gleam
│   │   ├── editor.gleam
│   │   ├── editor/
│   │   │   └── slug_.gleam
│   │   ├── article/
│   │   │   └── slug_.gleam
│   │   └── profile/
│   │       └── username_.gleam
│   └── sql/
│       ├── auth/
│       │   ├── register_user.sql
│       │   ├── find_user_by_email.sql
│       │   ├── find_user_by_session.sql
│       │   ├── create_session.sql
│       │   └── delete_session.sql
│       ├── home/
│       │   ├── get_articles_global.sql
│       │   ├── get_articles_feed.sql
│       │   ├── get_articles_by_tag.sql
│       │   ├── count_articles_global.sql
│       │   ├── count_articles_feed.sql
│       │   ├── count_articles_by_tag.sql
│       │   └── get_popular_tags.sql
│       ├── article/
│       │   ├── get_article.sql
│       │   ├── get_article_tags.sql
│       │   ├── get_comments.sql
│       │   ├── create_comment.sql
│       │   ├── delete_comment.sql
│       │   ├── is_favorited.sql
│       │   ├── favorite_count.sql
│       │   ├── add_favorite.sql
│       │   ├── remove_favorite.sql
│       │   ├── is_following.sql
│       │   ├── add_follow.sql
│       │   ├── remove_follow.sql
│       │   └── delete_article.sql
│       ├── editor/
│       │   ├── create_article.sql
│       │   ├── update_article.sql
│       │   ├── get_article_for_edit.sql
│       │   ├── create_tag.sql
│       │   ├── get_tag_id.sql
│       │   ├── link_article_tag.sql
│       │   └── clear_article_tags.sql
│       ├── profile/
│       │   ├── get_profile.sql
│       │   ├── get_user_articles.sql
│       │   ├── get_favorited_articles.sql
│       │   ├── is_following.sql
│       │   ├── add_follow.sql
│       │   └── remove_follow.sql
│       └── settings/
│           ├── get_current_user.sql
│           ├── update_user.sql
│           └── update_user_password.sql
├── test/
│   ├── realworld_test.gleam
│   ├── auth_test.gleam
│   └── article_test.gleam
├── gleam.toml
├── bin/dev
└── .gitignore
```

---

## Task 1: Framework -- expose get_ws_session and add client routing

Page modules need the session ID to look up the current user. Currently `get_ws_session` is private in `effect.gleam`. The generated client app also needs a popstate listener for SPA navigation.

**Files:**
- Modify: `src/lando_runtime/effect.gleam:113`
- Modify: `src/lando/generator/client.gleam`
- Modify: `examples/likes/client/src/generated/app.gleam` (will be regenerated)

- [ ] **Step 1: Make get_ws_session public**

In `src/lando_runtime/effect.gleam`, change line 113 from `fn` to `pub fn`:

```gleam
@external(erlang, "lando_runtime_ffi", "get_ws_session")
pub fn get_ws_session() -> String {
  panic as "get_ws_session: server-side only"
}
```

- [ ] **Step 2: Add popstate routing to client generator**

In `src/lando/generator/client.gleam`, add a `register_on_popstate` FFI to the generated `router_ffi.mjs` and wire it into init:

In `router_ffi_mjs()`, add:

```javascript
export function onPopstate(callback) {
  globalThis.addEventListener("popstate", () => callback());
}
```

In `app_gleam()`, update `init_transport()` (the generated code string) to also set up the popstate listener. Add after the `register_on_disconnect` line:

```gleam
    let _ = router.on_popstate(fn() { dispatch(UrlChanged(router.parse_route_from_url())) })
```

In `client_router()`, add a Gleam FFI declaration:

```gleam
@external(javascript, "./router_ffi.mjs", "onPopstate")
pub fn on_popstate(callback: fn() -> Nil) -> Nil
```

- [ ] **Step 3: Run tests**

Run: `gleam test`
Expected: All 103 tests pass. Update any birdie snapshots that reference the generated client app code.

- [ ] **Step 4: Commit**

```bash
git add src/lando_runtime/effect.gleam src/lando/generator/client.gleam
git commit -m "Expose get_ws_session and add client-side popstate routing"
```

---

## Task 2: Project scaffolding

Create the realworld example directory structure, gleam.toml, dev script, and .gitignore.

**Files:**
- Create: `examples/realworld/gleam.toml`
- Create: `examples/realworld/bin/dev`
- Create: `examples/realworld/.gitignore`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p examples/realworld/{src/{pages/editor,pages/article,pages/profile,sql/{auth,home,article,editor,profile,settings},generated},migrations,test,bin,client/src/generated}
```

- [ ] **Step 2: Write gleam.toml**

Create `examples/realworld/gleam.toml`:

```toml
name = "realworld"
version = "0.1.0"
target = "erlang"

[dependencies]
gleam_erlang = ">= 1.0.0 and < 2.0.0"
gleam_http = ">= 4.0.0 and < 5.0.0"
gleam_stdlib = ">= 0.60.0 and < 2.0.0"
lando = { path = "../.." }
lustre = ">= 5.6.0 and < 7.0.0"
marmot = { path = "../../../marmot" }
mist = ">= 6.0.0 and < 7.0.0"
sqlight = ">= 1.0.0 and < 2.0.0"
simplifile = ">= 2.0.0 and < 3.0.0"

[dev-dependencies]
gleeunit = ">= 1.0.0 and < 2.0.0"
birdie = ">= 1.0.0 and < 2.0.0"

[tools.lando]
pages_root = "src/pages"
output_route = "src/generated/router.gleam"
output_dispatch = "src/generated/page_dispatch.gleam"
output_server_dispatch = "src/generated/server_dispatch.gleam"
output_ssr = "src/generated/ssr_handler.gleam"
output_ws = "src/generated/ws_handler.gleam"
sql_dir = "src/sql"
client_root = "client"

[tools.marmot]
database = "app.db"
sql_dir = "src/sql"
output = "src/generated/sql"
```

- [ ] **Step 3: Write bin/dev**

Create `examples/realworld/bin/dev`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "==> Running migrations..."
gleam run -m lando -- migrate
echo "==> Running marmot codegen..."
gleam run -m marmot
echo "==> Running lando codegen..."
gleam run -m lando
echo "==> Building client..."
cd client && gleam build --target javascript && cd ..
echo "==> Starting server on http://localhost:8080"
gleam run
```

```bash
chmod +x examples/realworld/bin/dev
```

Note: if `lando -- migrate` isn't supported, replace with `gleam run` (which calls `app.main()` which runs migrations in `start_db()`). Adjust to match actual CLI.

- [ ] **Step 4: Write .gitignore**

Create `examples/realworld/.gitignore`:

```
build/
manifest.toml
client/manifest.toml
app.db
```

- [ ] **Step 5: Commit**

```bash
git add examples/realworld/gleam.toml examples/realworld/bin/dev examples/realworld/.gitignore
git commit -m "Scaffold realworld example project"
```

---

## Task 3: Database migration

Create the full schema in a single migration file.

**Files:**
- Create: `examples/realworld/migrations/001_init.sql`

- [ ] **Step 1: Write the migration**

Create `examples/realworld/migrations/001_init.sql`:

```sql
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  bio TEXT NOT NULL DEFAULT '',
  image TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS articles (
  id INTEGER PRIMARY KEY,
  slug TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  body TEXT NOT NULL,
  author_id INTEGER NOT NULL REFERENCES users(id),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tags (
  id INTEGER PRIMARY KEY,
  name TEXT UNIQUE NOT NULL
);

CREATE TABLE IF NOT EXISTS article_tags (
  article_id INTEGER NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
  tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (article_id, tag_id)
);

CREATE TABLE IF NOT EXISTS favorites (
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  article_id INTEGER NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, article_id)
);

CREATE TABLE IF NOT EXISTS follows (
  follower_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  followed_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  PRIMARY KEY (follower_id, followed_id)
);

CREATE TABLE IF NOT EXISTS comments (
  id INTEGER PRIMARY KEY,
  body TEXT NOT NULL,
  article_id INTEGER NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
  author_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
  session_id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_articles_author ON articles(author_id);
CREATE INDEX IF NOT EXISTS idx_articles_slug ON articles(slug);
CREATE INDEX IF NOT EXISTS idx_articles_created ON articles(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_comments_article ON comments(article_id);
CREATE INDEX IF NOT EXISTS idx_article_tags_article ON article_tags(article_id);
CREATE INDEX IF NOT EXISTS idx_article_tags_tag ON article_tags(tag_id);
CREATE INDEX IF NOT EXISTS idx_favorites_article ON favorites(article_id);
CREATE INDEX IF NOT EXISTS idx_follows_follower ON follows(follower_id);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);
```

- [ ] **Step 2: Verify migration runs**

```bash
cd examples/realworld
sqlite3 app.db < migrations/001_init.sql
sqlite3 app.db ".tables"
```

Expected output: `article_tags  articles  comments  favorites  follows  schema_migrations  sessions  tags  users` (or similar, minus schema_migrations if running raw SQL)

- [ ] **Step 3: Commit**

```bash
git add examples/realworld/migrations/001_init.sql
git commit -m "Add realworld database schema migration"
```

---

## Task 4: Password hashing FFI

Implement password hashing using Erlang's `crypto` module (PBKDF2-SHA256). No external dependencies needed.

**Files:**
- Create: `examples/realworld/src/password_ffi.erl`
- Create: `examples/realworld/src/password.gleam`

- [ ] **Step 1: Write the Erlang FFI**

Create `examples/realworld/src/password_ffi.erl`:

```erlang
-module(password_ffi).
-export([hash/1, verify/2]).

-define(ITERATIONS, 100000).
-define(KEY_LENGTH, 32).

hash(Password) ->
    Salt = crypto:strong_rand_bytes(16),
    Hash = crypto:pbkdf2_hmac(sha256, Password, Salt, ?ITERATIONS, ?KEY_LENGTH),
    SaltB64 = base64:encode(Salt),
    HashB64 = base64:encode(Hash),
    <<"pbkdf2_sha256$", (integer_to_binary(?ITERATIONS))/binary, "$",
      SaltB64/binary, "$", HashB64/binary>>.

verify(Password, Stored) ->
    case binary:split(Stored, <<"$">>, [global]) of
        [<<"pbkdf2_sha256">>, IterBin, SaltB64, HashB64] ->
            Iterations = binary_to_integer(IterBin),
            Salt = base64:decode(SaltB64),
            Expected = base64:decode(HashB64),
            Computed = crypto:pbkdf2_hmac(sha256, Password, Salt, Iterations, byte_size(Expected)),
            Computed =:= Expected;
        _ ->
            false
    end.
```

- [ ] **Step 2: Write the Gleam wrapper**

Create `examples/realworld/src/password.gleam`:

```gleam
@external(erlang, "password_ffi", "hash")
pub fn hash(password: String) -> String

@external(erlang, "password_ffi", "verify")
pub fn verify(password: String, hash: String) -> Bool
```

- [ ] **Step 3: Commit**

```bash
git add examples/realworld/src/password_ffi.erl examples/realworld/src/password.gleam
git commit -m "Add password hashing via PBKDF2-SHA256"
```

---

## Task 5: SQL queries for auth

Write marmot SQL files for user registration, login, session management. These are shared across register, login, and settings pages.

**Files:**
- Create: `examples/realworld/src/sql/auth/register_user.sql`
- Create: `examples/realworld/src/sql/auth/find_user_by_email.sql`
- Create: `examples/realworld/src/sql/auth/find_user_by_session.sql`
- Create: `examples/realworld/src/sql/auth/create_session.sql`
- Create: `examples/realworld/src/sql/auth/delete_session.sql`

- [ ] **Step 1: Write register_user.sql**

```sql
INSERT INTO users (username, email, password_hash, bio, image, created_at, updated_at)
VALUES (:username, :email, :password_hash, '', '', :now, :now)
RETURNING id, username, email, bio, image
```

- [ ] **Step 2: Write find_user_by_email.sql**

```sql
SELECT id, username, email, password_hash, bio, image
FROM users
WHERE email = :email
```

- [ ] **Step 3: Write find_user_by_session.sql**

```sql
SELECT u.id, u.username, u.email, u.bio, u.image
FROM users u
JOIN sessions s ON u.id = s.user_id
WHERE s.session_id = :session_id
```

- [ ] **Step 4: Write create_session.sql**

```sql
INSERT OR REPLACE INTO sessions (session_id, user_id, created_at)
VALUES (:session_id, :user_id, :now)
```

- [ ] **Step 5: Write delete_session.sql**

```sql
DELETE FROM sessions WHERE session_id = :session_id
```

- [ ] **Step 6: Run marmot to generate query modules**

Ensure the database exists with tables (run migration first), then run marmot:

```bash
cd examples/realworld
sqlite3 app.db < migrations/001_init.sql
gleam run -m marmot
```

Verify `src/generated/sql/auth_sql.gleam` was generated with functions for each query.

- [ ] **Step 7: Commit**

```bash
git add examples/realworld/src/sql/auth/
git commit -m "Add auth SQL queries"
```

---

## Task 6: Context types, layout, and app entry point

Set up ServerContext, ClientContext (with current user for nav), the Conduit layout, and the app.gleam entry point with Conduit CSS in the HTML shell.

**Files:**
- Create: `examples/realworld/src/server_context.gleam`
- Create: `examples/realworld/src/client_context.gleam`
- Create: `examples/realworld/src/slug.gleam`
- Create: `examples/realworld/src/pages/layout.gleam`
- Create: `examples/realworld/src/app.gleam`

- [ ] **Step 1: Write server_context.gleam**

```gleam
import sqlight

pub type ServerContext {
  ServerContext(db: sqlight.Connection)
}
```

- [ ] **Step 2: Write client_context.gleam**

```gleam
import gleam/option.{type Option, None, Some}
import lustre/effect.{type Effect}

pub type ClientContext {
  ClientContext(current_user: Option(User))
}

pub type User {
  User(username: String, image: String)
}

pub type ClientContextMsg {
  SignedIn(User)
  SignedOut
}

pub fn init() -> #(ClientContext, Effect(ClientContextMsg)) {
  #(ClientContext(current_user: None), effect.none())
}

pub fn update(
  _model: ClientContext,
  msg: ClientContextMsg,
) -> #(ClientContext, Effect(ClientContextMsg)) {
  case msg {
    SignedIn(user) -> #(
      ClientContext(current_user: Some(user)),
      effect.none(),
    )
    SignedOut -> #(ClientContext(current_user: None), effect.none())
  }
}
```

- [ ] **Step 3: Write slug.gleam**

```gleam
import gleam/string
import gleam/regex

pub fn from_title(title: String) -> String {
  let assert Ok(re) = regex.from_string("[^a-z0-9]+")
  title
  |> string.lowercase
  |> regex.replace(re, _, "-")
  |> string.trim_start("-")
  |> string.trim_end("-")
}
```

- [ ] **Step 4: Write layout.gleam with Conduit nav and footer**

```gleam
import gleam/option.{None, Some}
import client_context.{type ClientContext}
import lustre/attribute as attr
import lustre/element.{type Element}
import lustre/element/html

pub fn layout(
  client_context: ClientContext,
  content: Element(msg),
) -> Element(msg) {
  html.div([], [
    nav(client_context),
    content,
    footer_view(),
  ])
}

fn nav(client_context: ClientContext) -> Element(msg) {
  html.nav([attr.class("navbar navbar-light")], [
    html.div([attr.class("container")], [
      html.a([attr.class("navbar-brand"), attr.href("/")], [
        html.text("conduit"),
      ]),
      html.ul([attr.class("nav navbar-nav pull-xs-right")], case
        client_context.current_user
      {
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
      html.a([attr.class("logo-font"), attr.href("/")], [
        html.text("conduit"),
      ]),
      html.span([attr.class("attribution")], [
        html.text("Built with "),
        html.a([attr.href("https://github.com/lando")], [
          html.text("Lando"),
        ]),
      ]),
    ]),
  ])
}
```

Note: The layout takes `client_context` as a parameter. The framework's layout system currently calls `layout(content)` with one argument. This means the layout signature needs to match what the codegen expects. Check the `ssr_handler` and `page_dispatch` generators to see how layout is called. If the layout can only take one arg (`content`), the ClientContext will need to be threaded differently (e.g., layout reads it from a global or the nav is rendered inside each page view instead). Adjust based on what the codegen supports.

- [ ] **Step 5: Write app.gleam with Conduit HTML shell**

```gleam
import generated/router
import generated/ssr_handler
import generated/ws_handler
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http.{Get}
import gleam/http/request.{type Request, Request}
import gleam/http/response.{type Response}
import gleam/string
import lando_runtime/migrate
import lando_runtime/session
import mist.{type Connection, type ResponseData}
import server_context.{ServerContext}
import simplifile
import sqlight

const client_build_root = "client/build/dev/javascript"

pub fn main() {
  let db = start_db()
  let server_context = ServerContext(db:)

  let handler = fn(req: Request(Connection)) -> Response(ResponseData) {
    let Request(path: path, method: method, ..) = req
    case path {
      "/ws" -> {
        let session_id = case request.get_header(req, "cookie") {
          Ok(cookie) ->
            case session.extract_session_id(cookie) {
              Ok(id) -> id
              Error(_) -> session.generate_id()
            }
          Error(_) -> session.generate_id()
        }
        mist.websocket(
          req,
          ws_handler.handler,
          fn(conn) {
            ws_handler.on_init(conn, server_context, session_id)
          },
          ws_handler.on_close,
        )
      }
      _ -> {
        case string.starts_with(path, "/_build/") {
          True -> serve_static(string.drop_start(path, 8))
          False ->
            case method {
              Get -> {
                let resp = serve_html_shell()
                case request.get_header(req, "cookie") {
                  Ok(cookie) ->
                    case session.extract_session_id(cookie) {
                      Ok(_) -> resp
                      Error(_) ->
                        response.set_header(
                          resp,
                          "set-cookie",
                          session.set_cookie_header(session.generate_id()),
                        )
                    }
                  Error(_) ->
                    response.set_header(
                      resp,
                      "set-cookie",
                      session.set_cookie_header(session.generate_id()),
                    )
                }
              }
              _ ->
                response.new(405)
                |> response.set_body(
                  mist.Bytes(bytes_tree.from_string("Not found")),
                )
            }
        }
      }
    }
  }

  let assert Ok(_) =
    mist.new(handler)
    |> mist.port(8080)
    |> mist.start
  process.sleep_forever()
}

fn serve_html_shell() -> Response(ResponseData) {
  let html =
    "<!DOCTYPE html>
<html>
<head>
  <meta charset='utf-8'>
  <meta name='viewport' content='width=device-width, initial-scale=1.0'>
  <title>Conduit</title>
  <link href='https://code.ionicframework.com/ionicons/2.0.1/css/ionicons.min.css' rel='stylesheet' type='text/css'>
  <link href='https://fonts.googleapis.com/css?family=Titillium+Web:700|Source+Serif+Pro:400,700|Merriweather+Sans:400,700|Source+Sans+Pro:400,300,600,700,300italic,400italic,600italic,700italic' rel='stylesheet' type='text/css'>
  <link rel='stylesheet' href='https://demo.productionready.io/main.css'>
</head>
<body>
  <div id='app'></div>
  <script type='module' src='/_build/client/generated/app.mjs'></script>
</body>
</html>"
  response.new(200)
  |> response.set_header("content-type", "text/html")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(html)))
}

fn serve_static(path: String) -> Response(ResponseData) {
  let file_path = client_build_root <> "/" <> path
  case string.contains(path, "..") {
    True ->
      response.new(403)
      |> response.set_body(mist.Bytes(bytes_tree.from_string("Forbidden")))
    False ->
      case simplifile.read(file_path) {
        Ok(content) -> {
          let content_type = case string.ends_with(path, ".mjs") {
            True -> "application/javascript"
            False ->
              case string.ends_with(path, ".js") {
                True -> "application/javascript"
                False -> "application/octet-stream"
              }
          }
          response.new(200)
          |> response.set_header("content-type", content_type)
          |> response.set_body(mist.Bytes(bytes_tree.from_string(content)))
        }
        Error(_) ->
          response.new(404)
          |> response.set_body(
            mist.Bytes(bytes_tree.from_string("Not found")),
          )
      }
  }
}

fn start_db() -> sqlight.Connection {
  let assert Ok(conn) = sqlight.open("app.db")
  let assert Ok(_) = migrate.run(conn:, dir: "migrations")
  conn
}
```

Note: This serves its own HTML shell with Conduit CSS instead of using the generated `ssr_handler`. All routes get the same shell and the Lustre SPA handles routing client-side.

- [ ] **Step 6: Commit**

```bash
git add examples/realworld/src/server_context.gleam examples/realworld/src/client_context.gleam examples/realworld/src/slug.gleam examples/realworld/src/pages/layout.gleam examples/realworld/src/app.gleam
git commit -m "Add context types, Conduit layout, and app entry point"
```

---

## Task 7: Register page

**Files:**
- Create: `examples/realworld/src/pages/register.gleam`

- [ ] **Step 1: Write register.gleam**

```gleam
import client_context.{type ClientContext, type User, SignedIn, User}
import generated/sql/auth_sql
import gleam/list
import gleam/option.{None}
import gleam/string
import lando_runtime/effect as lando_effect
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import password
import server_context.{type ServerContext}

pub type Model {
  Model(username: String, email: String, password: String, errors: List(String))
}

pub type Msg {
  UpdatedUsername(String)
  UpdatedEmail(String)
  UpdatedPassword(String)
  ClickedRegister
  GotServerMsg(ToClient)
}

pub type ToServer {
  SubmitRegister(username: String, email: String, password: String)
}

pub type ToClient {
  Registered(username: String, image: String)
  RegisterError(errors: List(String))
}

pub type ServerModel {
  ServerModel
}

pub fn init(_client_context: ClientContext) -> #(Model, Effect(Msg)) {
  #(Model(username: "", email: "", password: "", errors: []), effect.none())
}

pub fn update(
  _client_context: ClientContext,
  model: Model,
  msg: Msg,
) -> #(Model, Effect(Msg)) {
  case msg {
    UpdatedUsername(val) -> #(Model(..model, username: val), effect.none())
    UpdatedEmail(val) -> #(Model(..model, email: val), effect.none())
    UpdatedPassword(val) -> #(Model(..model, password: val), effect.none())
    ClickedRegister -> #(
      model,
      lando_effect.send_to_server(SubmitRegister(
        model.username,
        model.email,
        model.password,
      )),
    )
    GotServerMsg(Registered(username, image)) -> #(
      model,
      effect.batch([
        lando_effect.send_to_client_context(SignedIn(User(username:, image:))),
        // Navigate to home after register
        navigate_effect("/"),
      ]),
    )
    GotServerMsg(RegisterError(errors)) -> #(
      Model(..model, errors:),
      effect.none(),
    )
  }
}

pub fn view(_client_context: ClientContext, model: Model) -> Element(Msg) {
  html.div([attr.class("auth-page")], [
    html.div([attr.class("container page")], [
      html.div([attr.class("row")], [
        html.div(
          [attr.class("col-md-6 offset-md-3 col-xs-12")],
          [
            html.h1([attr.class("text-xs-center")], [
              html.text("Sign up"),
            ]),
            html.p([attr.class("text-xs-center")], [
              html.a([attr.href("/login")], [
                html.text("Have an account?"),
              ]),
            ]),
            error_list(model.errors),
            html.form([event.on_submit(ClickedRegister)], [
              fieldset_input(
                "text",
                "Your Name",
                model.username,
                UpdatedUsername,
              ),
              fieldset_input(
                "text",
                "Email",
                model.email,
                UpdatedEmail,
              ),
              fieldset_input(
                "password",
                "Password",
                model.password,
                UpdatedPassword,
              ),
              html.button(
                [
                  attr.class(
                    "btn btn-lg btn-primary pull-xs-right",
                  ),
                  attr.type_("submit"),
                ],
                [html.text("Sign up")],
              ),
            ]),
          ],
        ),
      ]),
    ]),
  ])
}

pub fn server_init(
  _server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  #(ServerModel, lando_effect.none())
}

pub fn server_update(
  _model: ServerModel,
  msg: ToServer,
  server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  case msg {
    SubmitRegister(username, email, password_text) -> {
      let errors = validate_register(username, email, password_text)
      case errors {
        [] -> {
          let session_id = lando_effect.get_ws_session()
          let now = now_iso8601()
          let hash = password.hash(password_text)
          case
            auth_sql.register_user(
              db: server_context.db,
              username:,
              email:,
              password_hash: hash,
              now:,
            )
          {
            Ok([row]) -> {
              let _ =
                auth_sql.create_session(
                  db: server_context.db,
                  session_id:,
                  user_id: row.id,
                  now:,
                )
              #(
                ServerModel,
                lando_effect.send_to_client(Registered(
                  username: row.username,
                  image: row.image,
                )),
              )
            }
            _ -> #(
              ServerModel,
              lando_effect.send_to_client(RegisterError([
                "Username or email already taken",
              ])),
            )
          }
        }
        _ -> #(
          ServerModel,
          lando_effect.send_to_client(RegisterError(errors)),
        )
      }
    }
  }
}

fn validate_register(
  username: String,
  email: String,
  password: String,
) -> List(String) {
  []
  |> fn(errs) {
    case string.is_empty(username) {
      True -> ["Username is required", ..errs]
      False -> errs
    }
  }
  |> fn(errs) {
    case string.is_empty(email) {
      True -> ["Email is required", ..errs]
      False -> errs
    }
  }
  |> fn(errs) {
    case string.length(password) < 8 {
      True -> ["Password must be at least 8 characters", ..errs]
      False -> errs
    }
  }
}

fn error_list(errors: List(String)) -> Element(Msg) {
  case errors {
    [] -> html.text("")
    _ ->
      html.ul([attr.class("error-messages")], {
        list.map(errors, fn(e) { html.li([], [html.text(e)]) })
      })
  }
}

fn fieldset_input(
  type_: String,
  placeholder: String,
  value: String,
  on_input: fn(String) -> Msg,
) -> Element(Msg) {
  html.fieldset([attr.class("form-group")], [
    html.input([
      attr.class("form-control form-control-lg"),
      attr.type_(type_),
      attr.placeholder(placeholder),
      attr.value(value),
      event.on_input(on_input),
    ]),
  ])
}

@external(erlang, "erlang", "system_time")
fn system_time_seconds() -> Int

fn now_iso8601() -> String {
  // Simplified: use erlang system time. In production, use a proper datetime library.
  // For now, store as Unix timestamp string.
  let _ = system_time_seconds()
  // TODO: implement proper ISO 8601 formatting or use a library
  "2026-01-01T00:00:00Z"
}

fn navigate_effect(path: String) -> Effect(Msg) {
  effect.from(fn(_dispatch) {
    // Client-side navigation. On the server this is a no-op.
    // The client import of router.navigate handles this.
    Nil
  })
}
```

**Important notes for implementation:**
- The `now_iso8601()` function needs a proper implementation. Use `gleam/erlang` calendar functions or a datetime library. The placeholder above should be replaced with working code.
- The `navigate_effect` needs to call `router.navigate(path)` on the client side. Since this page module compiles for both server (Erlang) and client (JS), the navigate call needs to be conditional or handled via the generated transport layer. Check how the elm-land app handles post-login navigation and adapt.
- The `auth_sql` import depends on running marmot codegen first.

- [ ] **Step 2: Commit**

```bash
git add examples/realworld/src/pages/register.gleam
git commit -m "Add register page"
```

---

## Task 8: Login page

Very similar to register but authenticates against existing credentials.

**Files:**
- Create: `examples/realworld/src/pages/login.gleam`

- [ ] **Step 1: Write login.gleam**

```gleam
import client_context.{type ClientContext, type User, SignedIn, User}
import generated/sql/auth_sql
import gleam/list
import gleam/option.{None}
import gleam/string
import lando_runtime/effect as lando_effect
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import password
import server_context.{type ServerContext}

pub type Model {
  Model(email: String, password: String, errors: List(String))
}

pub type Msg {
  UpdatedEmail(String)
  UpdatedPassword(String)
  ClickedLogin
  GotServerMsg(ToClient)
}

pub type ToServer {
  SubmitLogin(email: String, password: String)
}

pub type ToClient {
  Authenticated(username: String, image: String)
  AuthError(errors: List(String))
}

pub type ServerModel {
  ServerModel
}

pub fn init(_client_context: ClientContext) -> #(Model, Effect(Msg)) {
  #(Model(email: "", password: "", errors: []), effect.none())
}

pub fn update(
  _client_context: ClientContext,
  model: Model,
  msg: Msg,
) -> #(Model, Effect(Msg)) {
  case msg {
    UpdatedEmail(val) -> #(Model(..model, email: val), effect.none())
    UpdatedPassword(val) -> #(Model(..model, password: val), effect.none())
    ClickedLogin -> #(
      model,
      lando_effect.send_to_server(SubmitLogin(model.email, model.password)),
    )
    GotServerMsg(Authenticated(username, image)) -> #(
      model,
      effect.batch([
        lando_effect.send_to_client_context(SignedIn(User(username:, image:))),
        navigate_effect("/"),
      ]),
    )
    GotServerMsg(AuthError(errors)) -> #(
      Model(..model, errors:),
      effect.none(),
    )
  }
}

pub fn view(_client_context: ClientContext, model: Model) -> Element(Msg) {
  html.div([attr.class("auth-page")], [
    html.div([attr.class("container page")], [
      html.div([attr.class("row")], [
        html.div(
          [attr.class("col-md-6 offset-md-3 col-xs-12")],
          [
            html.h1([attr.class("text-xs-center")], [
              html.text("Sign in"),
            ]),
            html.p([attr.class("text-xs-center")], [
              html.a([attr.href("/register")], [
                html.text("Need an account?"),
              ]),
            ]),
            error_list(model.errors),
            html.form([event.on_submit(ClickedLogin)], [
              fieldset_input("text", "Email", model.email, UpdatedEmail),
              fieldset_input(
                "password",
                "Password",
                model.password,
                UpdatedPassword,
              ),
              html.button(
                [
                  attr.class("btn btn-lg btn-primary pull-xs-right"),
                  attr.type_("submit"),
                ],
                [html.text("Sign in")],
              ),
            ]),
          ],
        ),
      ]),
    ]),
  ])
}

pub fn server_init(
  _server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  #(ServerModel, lando_effect.none())
}

pub fn server_update(
  _model: ServerModel,
  msg: ToServer,
  server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  case msg {
    SubmitLogin(email, password_text) -> {
      case string.is_empty(email) || string.is_empty(password_text) {
        True -> #(
          ServerModel,
          lando_effect.send_to_client(AuthError([
            "Email and password are required",
          ])),
        )
        False ->
          case
            auth_sql.find_user_by_email(db: server_context.db, email:)
          {
            Ok([user]) ->
              case password.verify(password_text, user.password_hash) {
                True -> {
                  let session_id = lando_effect.get_ws_session()
                  let _ =
                    auth_sql.create_session(
                      db: server_context.db,
                      session_id:,
                      user_id: user.id,
                      now: now_iso8601(),
                    )
                  #(
                    ServerModel,
                    lando_effect.send_to_client(Authenticated(
                      username: user.username,
                      image: user.image,
                    )),
                  )
                }
                False -> #(
                  ServerModel,
                  lando_effect.send_to_client(AuthError([
                    "Invalid email or password",
                  ])),
                )
              }
            _ -> #(
              ServerModel,
              lando_effect.send_to_client(AuthError([
                "Invalid email or password",
              ])),
            )
          }
      }
    }
  }
}

fn error_list(errors: List(String)) -> Element(Msg) {
  case errors {
    [] -> html.text("")
    _ ->
      html.ul([attr.class("error-messages")], {
        list.map(errors, fn(e) { html.li([], [html.text(e)]) })
      })
  }
}

fn fieldset_input(
  type_: String,
  placeholder: String,
  value: String,
  on_input: fn(String) -> Msg,
) -> Element(Msg) {
  html.fieldset([attr.class("form-group")], [
    html.input([
      attr.class("form-control form-control-lg"),
      attr.type_(type_),
      attr.placeholder(placeholder),
      attr.value(value),
      event.on_input(on_input),
    ]),
  ])
}

@external(erlang, "erlang", "system_time")
fn system_time_seconds() -> Int

fn now_iso8601() -> String {
  let _ = system_time_seconds()
  "2026-01-01T00:00:00Z"
}

fn navigate_effect(path: String) -> Effect(Msg) {
  effect.from(fn(_dispatch) { Nil })
}
```

- [ ] **Step 2: Commit**

```bash
git add examples/realworld/src/pages/login.gleam
git commit -m "Add login page"
```

---

## Task 9: Home page with feeds, tags, and pagination

The home page is the most complex page: global feed, personal feed (for logged-in users), tag filtering, popular tags sidebar, and pagination.

**Files:**
- Create: `examples/realworld/src/sql/home/get_articles_global.sql`
- Create: `examples/realworld/src/sql/home/get_articles_feed.sql`
- Create: `examples/realworld/src/sql/home/get_articles_by_tag.sql`
- Create: `examples/realworld/src/sql/home/count_articles_global.sql`
- Create: `examples/realworld/src/sql/home/count_articles_feed.sql`
- Create: `examples/realworld/src/sql/home/count_articles_by_tag.sql`
- Create: `examples/realworld/src/sql/home/get_popular_tags.sql`
- Create: `examples/realworld/src/pages/home_.gleam`

- [ ] **Step 1: Write SQL queries**

`src/sql/home/get_articles_global.sql`:
```sql
SELECT a.slug, a.title, a.description, a.created_at,
       u.username, u.image,
       (SELECT COUNT(*) FROM favorites WHERE article_id = a.id) as favorites_count
FROM articles a
JOIN users u ON a.author_id = u.id
ORDER BY a.created_at DESC
LIMIT :per_page OFFSET :offset
```

`src/sql/home/get_articles_feed.sql`:
```sql
SELECT a.slug, a.title, a.description, a.created_at,
       u.username, u.image,
       (SELECT COUNT(*) FROM favorites WHERE article_id = a.id) as favorites_count
FROM articles a
JOIN users u ON a.author_id = u.id
WHERE a.author_id IN (SELECT followed_id FROM follows WHERE follower_id = :user_id)
ORDER BY a.created_at DESC
LIMIT :per_page OFFSET :offset
```

`src/sql/home/get_articles_by_tag.sql`:
```sql
SELECT a.slug, a.title, a.description, a.created_at,
       u.username, u.image,
       (SELECT COUNT(*) FROM favorites WHERE article_id = a.id) as favorites_count
FROM articles a
JOIN users u ON a.author_id = u.id
JOIN article_tags at_ ON a.id = at_.article_id
JOIN tags t ON at_.tag_id = t.id
WHERE t.name = :tag
ORDER BY a.created_at DESC
LIMIT :per_page OFFSET :offset
```

`src/sql/home/count_articles_global.sql`:
```sql
SELECT COUNT(*) as count FROM articles
```

`src/sql/home/count_articles_feed.sql`:
```sql
SELECT COUNT(*) as count FROM articles
WHERE author_id IN (SELECT followed_id FROM follows WHERE follower_id = :user_id)
```

`src/sql/home/count_articles_by_tag.sql`:
```sql
SELECT COUNT(*) as count FROM articles a
JOIN article_tags at_ ON a.id = at_.article_id
JOIN tags t ON at_.tag_id = t.id
WHERE t.name = :tag
```

`src/sql/home/get_popular_tags.sql`:
```sql
SELECT t.name FROM tags t
JOIN article_tags at_ ON t.id = at_.tag_id
GROUP BY t.id
ORDER BY COUNT(*) DESC
LIMIT 10
```

- [ ] **Step 2: Run marmot to generate query modules**

```bash
cd examples/realworld && gleam run -m marmot
```

- [ ] **Step 3: Write home_.gleam**

The home page has three feed tabs (Your Feed, Global Feed, Tag), a popular tags sidebar, and pagination. The `server_init` sends the initial data. Tab/page/tag changes go through ToServer.

```gleam
import client_context.{type ClientContext}
import generated/sql/auth_sql
import generated/sql/home_sql
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lando_runtime/effect as lando_effect
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import server_context.{type ServerContext}

const per_page = 10

pub type Model {
  Model(
    articles: List(ArticlePreview),
    tags: List(String),
    active_tab: Tab,
    page: Int,
    total: Int,
  )
}

pub type ArticlePreview {
  ArticlePreview(
    slug: String,
    title: String,
    description: String,
    created_at: String,
    author_username: String,
    author_image: String,
    favorites_count: Int,
  )
}

pub type Tab {
  GlobalFeed
  YourFeed
  TagFeed(tag: String)
}

pub type Msg {
  ClickedTab(Tab)
  ClickedPage(Int)
  ClickedTag(String)
  GotServerMsg(ToClient)
}

pub type ToServer {
  SwitchTab(tab_name: String, tag: String)
  ChangePage(page: Int, tab_name: String, tag: String)
}

pub type ToClient {
  HomeData(
    articles: List(ArticlePreview),
    tags: List(String),
    total: Int,
  )
  ArticleListUpdated(articles: List(ArticlePreview), total: Int)
}

pub type ServerModel {
  ServerModel
}

pub fn init(_client_context: ClientContext) -> #(Model, Effect(Msg)) {
  #(
    Model(articles: [], tags: [], active_tab: GlobalFeed, page: 1, total: 0),
    effect.none(),
  )
}

pub fn update(
  _client_context: ClientContext,
  model: Model,
  msg: Msg,
) -> #(Model, Effect(Msg)) {
  case msg {
    ClickedTab(tab) -> {
      let #(tab_name, tag) = tab_to_wire(tab)
      #(
        Model(..model, active_tab: tab, page: 1),
        lando_effect.send_to_server(SwitchTab(tab_name:, tag:)),
      )
    }
    ClickedPage(page) -> {
      let #(tab_name, tag) = tab_to_wire(model.active_tab)
      #(
        Model(..model, page:),
        lando_effect.send_to_server(ChangePage(page:, tab_name:, tag:)),
      )
    }
    ClickedTag(tag) -> {
      #(
        Model(..model, active_tab: TagFeed(tag:), page: 1),
        lando_effect.send_to_server(SwitchTab(tab_name: "tag", tag:)),
      )
    }
    GotServerMsg(HomeData(articles, tags, total)) -> #(
      Model(..model, articles:, tags:, total:),
      effect.none(),
    )
    GotServerMsg(ArticleListUpdated(articles, total)) -> #(
      Model(..model, articles:, total:),
      effect.none(),
    )
  }
}

fn tab_to_wire(tab: Tab) -> #(String, String) {
  case tab {
    GlobalFeed -> #("global", "")
    YourFeed -> #("feed", "")
    TagFeed(tag:) -> #("tag", tag)
  }
}

pub fn view(client_context: ClientContext, model: Model) -> Element(Msg) {
  html.div([attr.class("home-page")], [
    banner(),
    html.div([attr.class("container page")], [
      html.div([attr.class("row")], [
        html.div([attr.class("col-md-9")], [
          feed_toggle(model.active_tab, client_context),
          articles_list(model.articles),
          pagination_view(model.page, model.total),
        ]),
        html.div([attr.class("col-md-3")], [
          sidebar(model.tags),
        ]),
      ]),
    ]),
  ])
}

fn banner() -> Element(Msg) {
  html.div([attr.class("banner")], [
    html.div([attr.class("container")], [
      html.h1([attr.class("logo-font")], [html.text("conduit")]),
      html.p([], [html.text("A place to share your knowledge.")]),
    ]),
  ])
}

fn feed_toggle(active: Tab, client_context: ClientContext) -> Element(Msg) {
  html.div([attr.class("feed-toggle")], [
    html.ul([attr.class("nav nav-pills outline-active")], {
      let your_feed = case client_context.current_user {
        Some(_) -> [
          tab_item("Your Feed", YourFeed, active),
        ]
        None -> []
      }
      let global = [tab_item("Global Feed", GlobalFeed, active)]
      let tag_tab = case active {
        TagFeed(tag:) -> [
          html.li([attr.class("nav-item")], [
            html.a([attr.class("nav-link active")], [
              html.text("# " <> tag),
            ]),
          ]),
        ]
        _ -> []
      }
      list.concat([your_feed, global, tag_tab])
    }),
  ])
}

fn tab_item(label: String, tab: Tab, active: Tab) -> Element(Msg) {
  let class = case tab == active {
    True -> "nav-link active"
    False -> "nav-link"
  }
  html.li([attr.class("nav-item")], [
    html.a([attr.class(class), event.on_click(ClickedTab(tab))], [
      html.text(label),
    ]),
  ])
}

fn articles_list(articles: List(ArticlePreview)) -> Element(Msg) {
  case articles {
    [] ->
      html.div([attr.class("article-preview")], [
        html.text("No articles are here... yet."),
      ])
    _ -> html.div([], list.map(articles, article_preview))
  }
}

fn article_preview(article: ArticlePreview) -> Element(Msg) {
  html.div([attr.class("article-preview")], [
    html.div([attr.class("article-meta")], [
      html.a([attr.href("/profile/" <> article.author_username)], [
        html.img([attr.src(article.author_image)]),
      ]),
      html.div([attr.class("info")], [
        html.a(
          [
            attr.href("/profile/" <> article.author_username),
            attr.class("author"),
          ],
          [html.text(article.author_username)],
        ),
        html.span([attr.class("date")], [
          html.text(article.created_at),
        ]),
      ]),
      html.button(
        [attr.class("btn btn-outline-primary btn-sm pull-xs-right")],
        [
          html.i([attr.class("ion-heart")], []),
          html.text(" " <> int.to_string(article.favorites_count)),
        ],
      ),
    ]),
    html.a([attr.href("/article/" <> article.slug), attr.class("preview-link")], [
      html.h1([], [html.text(article.title)]),
      html.p([], [html.text(article.description)]),
      html.span([], [html.text("Read more...")]),
    ]),
  ])
}

fn sidebar(tags: List(String)) -> Element(Msg) {
  html.div([attr.class("sidebar")], [
    html.p([], [html.text("Popular Tags")]),
    html.div(
      [attr.class("tag-list")],
      list.map(tags, fn(tag) {
        html.a(
          [
            attr.class("tag-pill tag-default"),
            event.on_click(ClickedTag(tag)),
          ],
          [html.text(tag)],
        )
      }),
    ),
  ])
}

fn pagination_view(current_page: Int, total: Int) -> Element(Msg) {
  let total_pages = { total + per_page - 1 } / per_page
  case total_pages <= 1 {
    True -> html.text("")
    False ->
      html.nav([], [
        html.ul(
          [attr.class("pagination")],
          list.range(1, total_pages)
            |> list.map(fn(p) {
              let class = case p == current_page {
                True -> "page-item active"
                False -> "page-item"
              }
              html.li([attr.class(class)], [
                html.a(
                  [
                    attr.class("page-link"),
                    event.on_click(ClickedPage(p)),
                  ],
                  [html.text(int.to_string(p))],
                ),
              ])
            }),
        ),
      ])
  }
}

pub fn server_init(
  server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  let assert Ok(articles) =
    home_sql.get_articles_global(
      db: server_context.db,
      per_page:,
      offset: 0,
    )
  let assert Ok([count_row]) =
    home_sql.count_articles_global(db: server_context.db)
  let assert Ok(tag_rows) =
    home_sql.get_popular_tags(db: server_context.db)

  let previews =
    list.map(articles, fn(row) {
      ArticlePreview(
        slug: row.slug,
        title: row.title,
        description: row.description,
        created_at: row.created_at,
        author_username: row.username,
        author_image: row.image,
        favorites_count: row.favorites_count,
      )
    })
  let tags = list.map(tag_rows, fn(row) { row.name })

  #(
    ServerModel,
    lando_effect.send_to_client(HomeData(
      articles: previews,
      tags:,
      total: count_row.count,
    )),
  )
}

pub fn server_update(
  _model: ServerModel,
  msg: ToServer,
  server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  case msg {
    SwitchTab(tab_name, tag) -> {
      let #(articles, total) =
        fetch_articles(server_context, tab_name, tag, 0)
      #(
        ServerModel,
        lando_effect.send_to_client(ArticleListUpdated(articles:, total:)),
      )
    }
    ChangePage(page, tab_name, tag) -> {
      let offset = { page - 1 } * per_page
      let #(articles, total) =
        fetch_articles(server_context, tab_name, tag, offset)
      #(
        ServerModel,
        lando_effect.send_to_client(ArticleListUpdated(articles:, total:)),
      )
    }
  }
}

fn fetch_articles(
  server_context: ServerContext,
  tab_name: String,
  tag: String,
  offset: Int,
) -> #(List(ArticlePreview), Int) {
  let #(rows, count) = case tab_name {
    "feed" -> {
      let session_id = lando_effect.get_ws_session()
      case
        auth_sql.find_user_by_session(
          db: server_context.db,
          session_id:,
        )
      {
        Ok([user]) -> {
          let assert Ok(rows) =
            home_sql.get_articles_feed(
              db: server_context.db,
              user_id: user.id,
              per_page:,
              offset:,
            )
          let assert Ok([c]) =
            home_sql.count_articles_feed(
              db: server_context.db,
              user_id: user.id,
            )
          #(rows, c.count)
        }
        _ -> #([], 0)
      }
    }
    "tag" -> {
      let assert Ok(rows) =
        home_sql.get_articles_by_tag(
          db: server_context.db,
          tag:,
          per_page:,
          offset:,
        )
      let assert Ok([c]) =
        home_sql.count_articles_by_tag(db: server_context.db, tag:)
      #(rows, c.count)
    }
    _ -> {
      let assert Ok(rows) =
        home_sql.get_articles_global(
          db: server_context.db,
          per_page:,
          offset:,
        )
      let assert Ok([c]) =
        home_sql.count_articles_global(db: server_context.db)
      #(rows, c.count)
    }
  }
  let previews =
    list.map(rows, fn(row) {
      ArticlePreview(
        slug: row.slug,
        title: row.title,
        description: row.description,
        created_at: row.created_at,
        author_username: row.username,
        author_image: row.image,
        favorites_count: row.favorites_count,
      )
    })
  #(previews, count)
}
```

Note: the `auth_sql` import is used here for resolving the current user (for "Your Feed"). This is intentional -- each page queries what it needs.

- [ ] **Step 4: Run codegen and verify**

```bash
cd examples/realworld
gleam run -m marmot
gleam run -m lando
cd client && gleam build --target javascript && cd ..
gleam build
```

- [ ] **Step 5: Commit**

```bash
git add examples/realworld/src/sql/home/ examples/realworld/src/pages/home_.gleam
git commit -m "Add home page with feeds, tags, and pagination"
```

---

## Task 10: Editor pages (new article and edit article)

**Files:**
- Create: `examples/realworld/src/sql/editor/*.sql` (7 files)
- Create: `examples/realworld/src/pages/editor.gleam`
- Create: `examples/realworld/src/pages/editor/slug_.gleam`

- [ ] **Step 1: Write editor SQL queries**

`src/sql/editor/create_article.sql`:
```sql
INSERT INTO articles (slug, title, description, body, author_id, created_at, updated_at)
VALUES (:slug, :title, :description, :body, :author_id, :now, :now)
RETURNING id, slug
```

`src/sql/editor/update_article.sql`:
```sql
UPDATE articles
SET title = :title, description = :description, body = :body, slug = :new_slug, updated_at = :now
WHERE slug = :slug AND author_id = :author_id
RETURNING id, slug
```

`src/sql/editor/get_article_for_edit.sql`:
```sql
SELECT a.slug, a.title, a.description, a.body
FROM articles a
WHERE a.slug = :slug AND a.author_id = :author_id
```

`src/sql/editor/create_tag.sql`:
```sql
INSERT OR IGNORE INTO tags (name) VALUES (:name)
```

`src/sql/editor/get_tag_id.sql`:
```sql
SELECT id FROM tags WHERE name = :name
```

`src/sql/editor/link_article_tag.sql`:
```sql
INSERT OR IGNORE INTO article_tags (article_id, tag_id) VALUES (:article_id, :tag_id)
```

`src/sql/editor/clear_article_tags.sql`:
```sql
DELETE FROM article_tags WHERE article_id = :article_id
```

- [ ] **Step 2: Write editor.gleam (new article)**

```gleam
import client_context.{type ClientContext}
import generated/sql/auth_sql
import generated/sql/editor_sql
import gleam/list
import gleam/string
import lando_runtime/effect as lando_effect
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import server_context.{type ServerContext}
import slug as slug_mod

pub type Model {
  Model(
    title: String,
    description: String,
    body: String,
    tag_input: String,
    tags: List(String),
    errors: List(String),
  )
}

pub type Msg {
  UpdatedTitle(String)
  UpdatedDescription(String)
  UpdatedBody(String)
  UpdatedTagInput(String)
  AddedTag
  RemovedTag(String)
  ClickedPublish
  GotServerMsg(ToClient)
}

pub type ToServer {
  PublishArticle(
    title: String,
    description: String,
    body: String,
    tags: List(String),
  )
}

pub type ToClient {
  ArticlePublished(slug: String)
  EditorErrors(errors: List(String))
}

pub type ServerModel {
  ServerModel
}

pub fn init(_client_context: ClientContext) -> #(Model, Effect(Msg)) {
  #(
    Model(
      title: "",
      description: "",
      body: "",
      tag_input: "",
      tags: [],
      errors: [],
    ),
    effect.none(),
  )
}

pub fn update(
  _client_context: ClientContext,
  model: Model,
  msg: Msg,
) -> #(Model, Effect(Msg)) {
  case msg {
    UpdatedTitle(val) -> #(Model(..model, title: val), effect.none())
    UpdatedDescription(val) -> #(
      Model(..model, description: val),
      effect.none(),
    )
    UpdatedBody(val) -> #(Model(..model, body: val), effect.none())
    UpdatedTagInput(val) -> #(
      Model(..model, tag_input: val),
      effect.none(),
    )
    AddedTag -> {
      let tag = string.trim(model.tag_input)
      case string.is_empty(tag) || list.contains(model.tags, tag) {
        True -> #(model, effect.none())
        False -> #(
          Model(..model, tags: [tag, ..model.tags], tag_input: ""),
          effect.none(),
        )
      }
    }
    RemovedTag(tag) -> #(
      Model(
        ..model,
        tags: list.filter(model.tags, fn(t) { t != tag }),
      ),
      effect.none(),
    )
    ClickedPublish -> #(
      model,
      lando_effect.send_to_server(PublishArticle(
        model.title,
        model.description,
        model.body,
        model.tags,
      )),
    )
    GotServerMsg(ArticlePublished(slug)) -> #(
      model,
      navigate_effect("/article/" <> slug),
    )
    GotServerMsg(EditorErrors(errors)) -> #(
      Model(..model, errors:),
      effect.none(),
    )
  }
}

pub fn view(_client_context: ClientContext, model: Model) -> Element(Msg) {
  html.div([attr.class("editor-page")], [
    html.div([attr.class("container page")], [
      html.div([attr.class("row")], [
        html.div([attr.class("col-md-10 offset-md-1 col-xs-12")], [
          error_list(model.errors),
          editor_form(model),
        ]),
      ]),
    ]),
  ])
}

fn editor_form(model: Model) -> Element(Msg) {
  html.form([event.on_submit(ClickedPublish)], [
    html.fieldset([], [
      html.fieldset([attr.class("form-group")], [
        html.input([
          attr.class("form-control form-control-lg"),
          attr.type_("text"),
          attr.placeholder("Article Title"),
          attr.value(model.title),
          event.on_input(UpdatedTitle),
        ]),
      ]),
      html.fieldset([attr.class("form-group")], [
        html.input([
          attr.class("form-control"),
          attr.type_("text"),
          attr.placeholder("What's this article about?"),
          attr.value(model.description),
          event.on_input(UpdatedDescription),
        ]),
      ]),
      html.fieldset([attr.class("form-group")], [
        html.textarea(
          [
            attr.class("form-control"),
            attr.rows(8),
            attr.placeholder("Write your article (in markdown)"),
            event.on_input(UpdatedBody),
          ],
          model.body,
        ),
      ]),
      html.fieldset([attr.class("form-group")], [
        html.input([
          attr.class("form-control"),
          attr.type_("text"),
          attr.placeholder("Enter tags"),
          attr.value(model.tag_input),
          event.on_input(UpdatedTagInput),
          on_enter(AddedTag),
        ]),
        html.div(
          [attr.class("tag-list")],
          list.map(model.tags, fn(tag) {
            html.span([attr.class("tag-default tag-pill")], [
              html.i(
                [
                  attr.class("ion-close-round"),
                  event.on_click(RemovedTag(tag)),
                ],
                [],
              ),
              html.text(" " <> tag),
            ])
          }),
        ),
      ]),
      html.button(
        [
          attr.class("btn btn-lg pull-xs-right btn-primary"),
          attr.type_("submit"),
        ],
        [html.text("Publish Article")],
      ),
    ]),
  ])
}

pub fn server_init(
  _server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  #(ServerModel, lando_effect.none())
}

pub fn server_update(
  _model: ServerModel,
  msg: ToServer,
  server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  case msg {
    PublishArticle(title, description, body, tags) -> {
      case validate_article(title, body) {
        [] -> {
          let session_id = lando_effect.get_ws_session()
          case
            auth_sql.find_user_by_session(
              db: server_context.db,
              session_id:,
            )
          {
            Ok([user]) -> {
              let article_slug = slug_mod.from_title(title)
              let now = now_iso8601()
              case
                editor_sql.create_article(
                  db: server_context.db,
                  slug: article_slug,
                  title:,
                  description:,
                  body:,
                  author_id: user.id,
                  now:,
                )
              {
                Ok([article]) -> {
                  save_tags(server_context, article.id, tags)
                  #(
                    ServerModel,
                    lando_effect.send_to_client(ArticlePublished(
                      slug: article.slug,
                    )),
                  )
                }
                _ -> #(
                  ServerModel,
                  lando_effect.send_to_client(EditorErrors([
                    "Failed to create article",
                  ])),
                )
              }
            }
            _ -> #(
              ServerModel,
              lando_effect.send_to_client(EditorErrors([
                "You must be logged in",
              ])),
            )
          }
        }
        errors -> #(
          ServerModel,
          lando_effect.send_to_client(EditorErrors(errors)),
        )
      }
    }
  }
}

fn save_tags(server_context: ServerContext, article_id: Int, tags: List(String)) -> Nil {
  list.each(tags, fn(tag) {
    let _ = editor_sql.create_tag(db: server_context.db, name: tag)
    case editor_sql.get_tag_id(db: server_context.db, name: tag) {
      Ok([row]) -> {
        let _ =
          editor_sql.link_article_tag(
            db: server_context.db,
            article_id:,
            tag_id: row.id,
          )
        Nil
      }
      _ -> Nil
    }
  })
}

fn validate_article(title: String, body: String) -> List(String) {
  let errs = []
  let errs = case string.is_empty(title) {
    True -> ["Title is required", ..errs]
    False -> errs
  }
  case string.is_empty(body) {
    True -> ["Body is required", ..errs]
    False -> errs
  }
}

fn error_list(errors: List(String)) -> Element(Msg) {
  case errors {
    [] -> html.text("")
    _ ->
      html.ul(
        [attr.class("error-messages")],
        list.map(errors, fn(e) { html.li([], [html.text(e)]) }),
      )
  }
}

fn on_enter(_msg: Msg) -> attr.Attribute(Msg) {
  // Placeholder: implement keydown handler for Enter key
  // This may require a custom event decoder
  attr.none()
}

fn navigate_effect(path: String) -> Effect(Msg) {
  effect.from(fn(_dispatch) { Nil })
}

@external(erlang, "erlang", "system_time")
fn system_time_seconds() -> Int

fn now_iso8601() -> String {
  let _ = system_time_seconds()
  "2026-01-01T00:00:00Z"
}
```

- [ ] **Step 3: Write editor/slug_.gleam (edit article)**

Similar to `editor.gleam` but loads the existing article in `server_init` and uses `update_article` instead of `create_article`. The slug parameter comes from the route.

The page should:
- In `server_init`: load the article by slug (verifying the current user is the author), send `ArticleLoaded` to client
- In `server_update` for `UpdateArticle`: clear old tags, update article, re-save tags
- The `Model` includes the same editor fields, pre-populated from `ArticleLoaded`

Follow the same pattern as `editor.gleam` with these differences:
- Add `ArticleLoaded(title, description, body, tags)` to ToClient
- Add `UpdateArticle(slug, title, description, body, tags)` to ToServer
- `server_init` loads the article using `editor_sql.get_article_for_edit` and article tags
- `server_update` uses `editor_sql.update_article`, `editor_sql.clear_article_tags`, then `save_tags`

- [ ] **Step 4: Run codegen and verify build**

```bash
cd examples/realworld
gleam run -m marmot
gleam run -m lando
gleam build
```

- [ ] **Step 5: Commit**

```bash
git add examples/realworld/src/sql/editor/ examples/realworld/src/pages/editor.gleam examples/realworld/src/pages/editor/slug_.gleam
git commit -m "Add editor pages for creating and editing articles"
```

---

## Task 11: Article detail page

The article page shows the full article, comments, and provides favorite/follow/comment interactions. Broadcasts updates to all viewers.

**Files:**
- Create: `examples/realworld/src/sql/article/*.sql` (13 files)
- Create: `examples/realworld/src/pages/article/slug_.gleam`

- [ ] **Step 1: Write article SQL queries**

`src/sql/article/get_article.sql`:
```sql
SELECT a.id, a.slug, a.title, a.description, a.body, a.created_at, a.updated_at,
       u.username, u.image, u.bio
FROM articles a
JOIN users u ON a.author_id = u.id
WHERE a.slug = :slug
```

`src/sql/article/get_article_tags.sql`:
```sql
SELECT t.name FROM tags t
JOIN article_tags at_ ON t.id = at_.tag_id
WHERE at_.article_id = :article_id
```

`src/sql/article/get_comments.sql`:
```sql
SELECT c.id, c.body, c.created_at, u.username, u.image
FROM comments c
JOIN users u ON c.author_id = u.id
WHERE c.article_id = :article_id
ORDER BY c.created_at DESC
```

`src/sql/article/create_comment.sql`:
```sql
INSERT INTO comments (body, article_id, author_id, created_at)
VALUES (:body, :article_id, :author_id, :now)
RETURNING id, body, created_at
```

`src/sql/article/delete_comment.sql`:
```sql
DELETE FROM comments WHERE id = :id AND author_id = :author_id
```

`src/sql/article/is_favorited.sql`:
```sql
SELECT COUNT(*) as count FROM favorites WHERE user_id = :user_id AND article_id = :article_id
```

`src/sql/article/favorite_count.sql`:
```sql
SELECT COUNT(*) as count FROM favorites WHERE article_id = :article_id
```

`src/sql/article/add_favorite.sql`:
```sql
INSERT OR IGNORE INTO favorites (user_id, article_id) VALUES (:user_id, :article_id)
```

`src/sql/article/remove_favorite.sql`:
```sql
DELETE FROM favorites WHERE user_id = :user_id AND article_id = :article_id
```

`src/sql/article/is_following.sql`:
```sql
SELECT COUNT(*) as count FROM follows
WHERE follower_id = :follower_id
AND followed_id = (SELECT id FROM users WHERE username = :username)
```

`src/sql/article/add_follow.sql`:
```sql
INSERT OR IGNORE INTO follows (follower_id, followed_id)
VALUES (:follower_id, (SELECT id FROM users WHERE username = :username))
```

`src/sql/article/remove_follow.sql`:
```sql
DELETE FROM follows
WHERE follower_id = :follower_id
AND followed_id = (SELECT id FROM users WHERE username = :username)
```

`src/sql/article/delete_article.sql`:
```sql
DELETE FROM articles WHERE slug = :slug AND author_id = :author_id
```

- [ ] **Step 2: Write article/slug_.gleam**

This is the largest page. Types:

```gleam
pub type Model {
  Model(
    article: Option(Article),
    comments: List(Comment),
    is_favorited: Bool,
    is_following: Bool,
    favorites_count: Int,
    comment_body: String,
    errors: List(String),
  )
}

pub type Article {
  Article(
    id: Int, slug: String, title: String, description: String,
    body: String, created_at: String, tags: List(String),
    author_username: String, author_image: String, author_bio: String,
  )
}

pub type Comment {
  Comment(id: Int, body: String, created_at: String, username: String, image: String)
}

pub type ToServer {
  ToggleFavorite
  ToggleFollow(username: String)
  SubmitComment(body: String)
  DeleteComment(id: Int)
  DeleteArticle
}

pub type ToClient {
  ArticleData(article: Article, comments: List(Comment), is_favorited: Bool, is_following: Bool, favorites_count: Int)
  FavoriteUpdated(count: Int, is_favorited: Bool)
  FollowUpdated(is_following: Bool)
  CommentAdded(comment: Comment)
  CommentRemoved(id: Int)
  ArticleDeleted
  ArticleError(message: String)
}
```

Key server logic:
- `server_init`: load article by slug (from route param), load comments, check if current user has favorited/is following. Send `ArticleData` via `send_to_client`.
- `ToggleFavorite`: add/remove favorite, `broadcast_to_page(FavoriteUpdated(...))` so all viewers see the count change
- `SubmitComment`: validate, insert, `broadcast_to_page(CommentAdded(...))` so all viewers see the new comment
- `DeleteComment`: delete if owner, `broadcast_to_page(CommentRemoved(id))`
- `ToggleFollow`: add/remove follow, `send_to_client(FollowUpdated(...))` (follow state is per-user, not broadcast)
- `DeleteArticle`: delete if owner, `send_to_client(ArticleDeleted)`, client navigates to home

The view renders: article banner with author info and favorite/follow buttons, article body, tag list, comment form (if logged in), comment list.

Write the complete page module following the patterns established in earlier tasks. Reference the elm-land app's `Article/Slug_` page for the Conduit CSS structure.

- [ ] **Step 3: Run codegen and verify**

```bash
cd examples/realworld
gleam run -m marmot
gleam run -m lando
gleam build
```

- [ ] **Step 4: Commit**

```bash
git add examples/realworld/src/sql/article/ examples/realworld/src/pages/article/
git commit -m "Add article detail page with comments, favorites, and follows"
```

---

## Task 12: Profile page

**Files:**
- Create: `examples/realworld/src/sql/profile/*.sql` (6 files)
- Create: `examples/realworld/src/pages/profile/username_.gleam`

- [ ] **Step 1: Write profile SQL queries**

`src/sql/profile/get_profile.sql`:
```sql
SELECT u.username, u.bio, u.image FROM users u WHERE u.username = :username
```

`src/sql/profile/get_user_articles.sql`:
```sql
SELECT a.slug, a.title, a.description, a.created_at,
       u.username, u.image,
       (SELECT COUNT(*) FROM favorites WHERE article_id = a.id) as favorites_count
FROM articles a
JOIN users u ON a.author_id = u.id
WHERE u.username = :username
ORDER BY a.created_at DESC
LIMIT :per_page OFFSET :offset
```

`src/sql/profile/get_favorited_articles.sql`:
```sql
SELECT a.slug, a.title, a.description, a.created_at,
       u.username, u.image,
       (SELECT COUNT(*) FROM favorites WHERE article_id = a.id) as favorites_count
FROM articles a
JOIN users u ON a.author_id = u.id
WHERE a.id IN (
  SELECT f.article_id FROM favorites f
  JOIN users fu ON f.user_id = fu.id
  WHERE fu.username = :username
)
ORDER BY a.created_at DESC
LIMIT :per_page OFFSET :offset
```

`src/sql/profile/is_following.sql`:
```sql
SELECT COUNT(*) as count FROM follows
WHERE follower_id = :follower_id
AND followed_id = (SELECT id FROM users WHERE username = :username)
```

`src/sql/profile/add_follow.sql`:
```sql
INSERT OR IGNORE INTO follows (follower_id, followed_id)
VALUES (:follower_id, (SELECT id FROM users WHERE username = :username))
```

`src/sql/profile/remove_follow.sql`:
```sql
DELETE FROM follows
WHERE follower_id = :follower_id
AND followed_id = (SELECT id FROM users WHERE username = :username)
```

- [ ] **Step 2: Write profile/username_.gleam**

Types:

```gleam
pub type Model {
  Model(
    profile: Option(Profile),
    articles: List(ArticlePreview),
    active_tab: ProfileTab,
    is_following: Bool,
  )
}

pub type Profile {
  Profile(username: String, bio: String, image: String)
}

pub type ProfileTab {
  MyArticles
  FavoritedArticles
}

pub type ToServer {
  ToggleFollow
  SwitchTab(tab_name: String)
}

pub type ToClient {
  ProfileData(profile: Profile, articles: List(ArticlePreview), is_following: Bool)
  FollowUpdated(is_following: Bool)
  ProfileArticles(articles: List(ArticlePreview))
}
```

Key server logic:
- `server_init`: load profile by username (from route param), load user's articles, check if current user follows. Send `ProfileData`.
- `SwitchTab("my_articles")`: load user's articles
- `SwitchTab("favorited")`: load user's favorited articles
- `ToggleFollow`: add/remove follow, `send_to_client(FollowUpdated(...))`

The view renders: profile banner with user info and follow button, tab toggle (My Articles / Favorited Articles), article list (reuse the article preview pattern from home page).

Reuse the `ArticlePreview` type definition from the home page (or define it locally since each page is self-contained).

- [ ] **Step 3: Commit**

```bash
git add examples/realworld/src/sql/profile/ examples/realworld/src/pages/profile/
git commit -m "Add profile page with articles and follow"
```

---

## Task 13: Settings page

**Files:**
- Create: `examples/realworld/src/sql/settings/*.sql` (3 files)
- Create: `examples/realworld/src/pages/settings.gleam`

- [ ] **Step 1: Write settings SQL queries**

`src/sql/settings/get_current_user.sql`:
```sql
SELECT username, email, bio, image FROM users WHERE id = :user_id
```

`src/sql/settings/update_user.sql`:
```sql
UPDATE users SET username = :username, email = :email, bio = :bio, image = :image, updated_at = :now
WHERE id = :user_id
```

`src/sql/settings/update_user_password.sql`:
```sql
UPDATE users SET username = :username, email = :email, bio = :bio, image = :image,
  password_hash = :password_hash, updated_at = :now
WHERE id = :user_id
```

- [ ] **Step 2: Write settings.gleam**

```gleam
import client_context.{type ClientContext, type User, SignedOut, SignedIn, User}
import generated/sql/auth_sql
import generated/sql/settings_sql
import gleam/list
import gleam/string
import lando_runtime/effect as lando_effect
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import password
import server_context.{type ServerContext}

pub type Model {
  Model(
    image: String,
    username: String,
    bio: String,
    email: String,
    password: String,
    errors: List(String),
  )
}

pub type Msg {
  UpdatedImage(String)
  UpdatedUsername(String)
  UpdatedBio(String)
  UpdatedEmail(String)
  UpdatedPassword(String)
  ClickedUpdate
  ClickedLogout
  GotServerMsg(ToClient)
}

pub type ToServer {
  UpdateSettings(
    image: String,
    username: String,
    bio: String,
    email: String,
    password: String,
  )
  Logout
}

pub type ToClient {
  SettingsLoaded(
    image: String,
    username: String,
    bio: String,
    email: String,
  )
  SettingsUpdated(username: String, image: String)
  SettingsError(errors: List(String))
  LoggedOut
}

pub type ServerModel {
  ServerModel
}

pub fn init(_client_context: ClientContext) -> #(Model, Effect(Msg)) {
  #(
    Model(
      image: "",
      username: "",
      bio: "",
      email: "",
      password: "",
      errors: [],
    ),
    effect.none(),
  )
}

pub fn update(
  _client_context: ClientContext,
  model: Model,
  msg: Msg,
) -> #(Model, Effect(Msg)) {
  case msg {
    UpdatedImage(val) -> #(Model(..model, image: val), effect.none())
    UpdatedUsername(val) -> #(
      Model(..model, username: val),
      effect.none(),
    )
    UpdatedBio(val) -> #(Model(..model, bio: val), effect.none())
    UpdatedEmail(val) -> #(Model(..model, email: val), effect.none())
    UpdatedPassword(val) -> #(
      Model(..model, password: val),
      effect.none(),
    )
    ClickedUpdate -> #(
      model,
      lando_effect.send_to_server(UpdateSettings(
        model.image,
        model.username,
        model.bio,
        model.email,
        model.password,
      )),
    )
    ClickedLogout -> #(model, lando_effect.send_to_server(Logout))
    GotServerMsg(SettingsLoaded(image, username, bio, email)) -> #(
      Model(..model, image:, username:, bio:, email:),
      effect.none(),
    )
    GotServerMsg(SettingsUpdated(username, image)) -> #(
      model,
      lando_effect.send_to_client_context(SignedIn(User(username:, image:))),
    )
    GotServerMsg(SettingsError(errors)) -> #(
      Model(..model, errors:),
      effect.none(),
    )
    GotServerMsg(LoggedOut) -> #(
      model,
      effect.batch([
        lando_effect.send_to_client_context(SignedOut),
        navigate_effect("/"),
      ]),
    )
  }
}

pub fn view(_client_context: ClientContext, model: Model) -> Element(Msg) {
  html.div([attr.class("settings-page")], [
    html.div([attr.class("container page")], [
      html.div([attr.class("row")], [
        html.div([attr.class("col-md-6 offset-md-3 col-xs-12")], [
          html.h1([attr.class("text-xs-center")], [
            html.text("Your Settings"),
          ]),
          error_list(model.errors),
          html.form([event.on_submit(ClickedUpdate)], [
            html.fieldset([], [
              html.fieldset([attr.class("form-group")], [
                html.input([
                  attr.class("form-control"),
                  attr.type_("text"),
                  attr.placeholder("URL of profile picture"),
                  attr.value(model.image),
                  event.on_input(UpdatedImage),
                ]),
              ]),
              html.fieldset([attr.class("form-group")], [
                html.input([
                  attr.class("form-control form-control-lg"),
                  attr.type_("text"),
                  attr.placeholder("Your Name"),
                  attr.value(model.username),
                  event.on_input(UpdatedUsername),
                ]),
              ]),
              html.fieldset([attr.class("form-group")], [
                html.textarea(
                  [
                    attr.class("form-control form-control-lg"),
                    attr.rows(8),
                    attr.placeholder("Short bio about you"),
                    event.on_input(UpdatedBio),
                  ],
                  model.bio,
                ),
              ]),
              html.fieldset([attr.class("form-group")], [
                html.input([
                  attr.class("form-control form-control-lg"),
                  attr.type_("text"),
                  attr.placeholder("Email"),
                  attr.value(model.email),
                  event.on_input(UpdatedEmail),
                ]),
              ]),
              html.fieldset([attr.class("form-group")], [
                html.input([
                  attr.class("form-control form-control-lg"),
                  attr.type_("password"),
                  attr.placeholder("New Password"),
                  attr.value(model.password),
                  event.on_input(UpdatedPassword),
                ]),
              ]),
              html.button(
                [
                  attr.class("btn btn-lg btn-primary pull-xs-right"),
                  attr.type_("submit"),
                ],
                [html.text("Update Settings")],
              ),
            ]),
          ]),
          html.hr([]),
          html.button(
            [
              attr.class("btn btn-outline-danger"),
              event.on_click(ClickedLogout),
            ],
            [html.text("Or click here to logout.")],
          ),
        ]),
      ]),
    ]),
  ])
}

pub fn server_init(
  server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  let session_id = lando_effect.get_ws_session()
  case
    auth_sql.find_user_by_session(db: server_context.db, session_id:)
  {
    Ok([user]) ->
      case
        settings_sql.get_current_user(
          db: server_context.db,
          user_id: user.id,
        )
      {
        Ok([row]) -> #(
          ServerModel,
          lando_effect.send_to_client(SettingsLoaded(
            image: row.image,
            username: row.username,
            bio: row.bio,
            email: row.email,
          )),
        )
        _ -> #(ServerModel, lando_effect.none())
      }
    _ -> #(ServerModel, lando_effect.none())
  }
}

pub fn server_update(
  _model: ServerModel,
  msg: ToServer,
  server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  case msg {
    UpdateSettings(image, username, bio, email, password_text) -> {
      let session_id = lando_effect.get_ws_session()
      case
        auth_sql.find_user_by_session(
          db: server_context.db,
          session_id:,
        )
      {
        Ok([user]) -> {
          let now = now_iso8601()
          let result = case string.is_empty(password_text) {
            True ->
              settings_sql.update_user(
                db: server_context.db,
                username:,
                email:,
                bio:,
                image:,
                now:,
                user_id: user.id,
              )
            False -> {
              let hash = password.hash(password_text)
              settings_sql.update_user_password(
                db: server_context.db,
                username:,
                email:,
                bio:,
                image:,
                password_hash: hash,
                now:,
                user_id: user.id,
              )
            }
          }
          case result {
            Ok(_) -> #(
              ServerModel,
              lando_effect.send_to_client(SettingsUpdated(username:, image:)),
            )
            Error(_) -> #(
              ServerModel,
              lando_effect.send_to_client(SettingsError([
                "Failed to update settings",
              ])),
            )
          }
        }
        _ -> #(
          ServerModel,
          lando_effect.send_to_client(SettingsError([
            "You must be logged in",
          ])),
        )
      }
    }
    Logout -> {
      let session_id = lando_effect.get_ws_session()
      let _ =
        auth_sql.delete_session(db: server_context.db, session_id:)
      #(ServerModel, lando_effect.send_to_client(LoggedOut))
    }
  }
}

fn error_list(errors: List(String)) -> Element(Msg) {
  case errors {
    [] -> html.text("")
    _ ->
      html.ul(
        [attr.class("error-messages")],
        list.map(errors, fn(e) { html.li([], [html.text(e)]) }),
      )
  }
}

fn navigate_effect(path: String) -> Effect(Msg) {
  effect.from(fn(_dispatch) { Nil })
}

@external(erlang, "erlang", "system_time")
fn system_time_seconds() -> Int

fn now_iso8601() -> String {
  let _ = system_time_seconds()
  "2026-01-01T00:00:00Z"
}
```

- [ ] **Step 3: Commit**

```bash
git add examples/realworld/src/sql/settings/ examples/realworld/src/pages/settings.gleam
git commit -m "Add settings page with profile update and logout"
```

---

## Task 14: Tests

Write birdie snapshot tests for auth flows and article operations.

**Files:**
- Create: `examples/realworld/test/realworld_test.gleam`
- Create: `examples/realworld/test/auth_test.gleam`
- Create: `examples/realworld/test/article_test.gleam`

- [ ] **Step 1: Write test helper (realworld_test.gleam)**

```gleam
import gleeunit

pub fn main() {
  gleeunit.main()
}
```

- [ ] **Step 2: Write auth_test.gleam**

```gleam
import birdie
import gleam/string
import lando_runtime/migrate
import password
import sqlight

fn test_db() -> sqlight.Connection {
  let assert Ok(conn) = sqlight.open(":memory:")
  let assert Ok(_) = migrate.run(conn:, dir: "migrations")
  conn
}

pub fn password_hash_and_verify_test() {
  let hash = password.hash("mysecretpassword")
  let result = password.verify("mysecretpassword", hash)
  birdie.snap(string.inspect(result), "password_verify_correct")
}

pub fn password_verify_wrong_test() {
  let hash = password.hash("mysecretpassword")
  let result = password.verify("wrongpassword", hash)
  birdie.snap(string.inspect(result), "password_verify_wrong")
}

pub fn register_user_test() {
  let db = test_db()
  let assert Ok(rows) =
    sqlight.query(
      "INSERT INTO users (username, email, password_hash, bio, image, created_at, updated_at)
       VALUES ('testuser', 'test@example.com', 'hash123', '', '', '2026-01-01', '2026-01-01')
       RETURNING id, username, email",
      on: db,
      with: [],
      expecting: fn(row) {
        // Use appropriate decoder
        row
      },
    )
  birdie.snap(string.inspect(rows), "register_user_returns_row")
}

pub fn session_create_and_lookup_test() {
  let db = test_db()
  // Insert a user first
  let assert Ok(_) =
    sqlight.exec(
      "INSERT INTO users (username, email, password_hash, bio, image, created_at, updated_at)
       VALUES ('testuser', 'test@example.com', 'hash', '', '', '2026-01-01', '2026-01-01')",
      on: db,
    )
  // Create session
  let assert Ok(_) =
    sqlight.exec(
      "INSERT INTO sessions (session_id, user_id, created_at)
       VALUES ('sess123', 1, '2026-01-01')",
      on: db,
    )
  // Look up session
  let assert Ok(rows) =
    sqlight.query(
      "SELECT u.username, u.email FROM users u
       JOIN sessions s ON u.id = s.user_id
       WHERE s.session_id = 'sess123'",
      on: db,
      with: [],
      expecting: fn(row) { row },
    )
  birdie.snap(string.inspect(rows), "session_lookup_finds_user")
}

pub fn session_delete_test() {
  let db = test_db()
  let assert Ok(_) =
    sqlight.exec(
      "INSERT INTO users (username, email, password_hash, bio, image, created_at, updated_at)
       VALUES ('testuser', 'test@example.com', 'hash', '', '', '2026-01-01', '2026-01-01')",
      on: db,
    )
  let assert Ok(_) =
    sqlight.exec(
      "INSERT INTO sessions (session_id, user_id, created_at)
       VALUES ('sess123', 1, '2026-01-01')",
      on: db,
    )
  let assert Ok(_) =
    sqlight.exec("DELETE FROM sessions WHERE session_id = 'sess123'", on: db)
  let assert Ok(rows) =
    sqlight.query(
      "SELECT COUNT(*) as count FROM sessions WHERE session_id = 'sess123'",
      on: db,
      with: [],
      expecting: fn(row) { row },
    )
  birdie.snap(string.inspect(rows), "session_deleted")
}
```

Note: The exact decoder signatures depend on how sqlight works in the project. The tests above use raw SQL to test the schema and query patterns independently of marmot. Adjust decoders to match sqlight's API (likely using `gleam/dynamic/decode`).

- [ ] **Step 3: Write article_test.gleam**

```gleam
import birdie
import gleam/string
import lando_runtime/migrate
import sqlight

fn test_db() -> sqlight.Connection {
  let assert Ok(conn) = sqlight.open(":memory:")
  let assert Ok(_) = migrate.run(conn:, dir: "migrations")
  conn
}

fn seed_user(db: sqlight.Connection) -> Nil {
  let assert Ok(_) =
    sqlight.exec(
      "INSERT INTO users (username, email, password_hash, bio, image, created_at, updated_at)
       VALUES ('author', 'author@example.com', 'hash', 'A bio', '', '2026-01-01', '2026-01-01')",
      on: db,
    )
  Nil
}

fn seed_article(db: sqlight.Connection) -> Nil {
  seed_user(db)
  let assert Ok(_) =
    sqlight.exec(
      "INSERT INTO articles (slug, title, description, body, author_id, created_at, updated_at)
       VALUES ('test-article', 'Test Article', 'A description', 'Article body', 1, '2026-01-01', '2026-01-01')",
      on: db,
    )
  Nil
}

pub fn create_article_test() {
  let db = test_db()
  seed_user(db)
  let assert Ok(rows) =
    sqlight.query(
      "INSERT INTO articles (slug, title, description, body, author_id, created_at, updated_at)
       VALUES ('my-article', 'My Article', 'desc', 'body text', 1, '2026-01-01', '2026-01-01')
       RETURNING slug, title",
      on: db,
      with: [],
      expecting: fn(row) { row },
    )
  birdie.snap(string.inspect(rows), "create_article")
}

pub fn favorite_toggle_test() {
  let db = test_db()
  seed_article(db)
  // Add favorite
  let assert Ok(_) =
    sqlight.exec(
      "INSERT OR IGNORE INTO favorites (user_id, article_id) VALUES (1, 1)",
      on: db,
    )
  let assert Ok(rows) =
    sqlight.query(
      "SELECT COUNT(*) as count FROM favorites WHERE article_id = 1",
      on: db,
      with: [],
      expecting: fn(row) { row },
    )
  birdie.snap(string.inspect(rows), "favorite_count_after_add")
  // Remove favorite
  let assert Ok(_) =
    sqlight.exec(
      "DELETE FROM favorites WHERE user_id = 1 AND article_id = 1",
      on: db,
    )
  let assert Ok(rows2) =
    sqlight.query(
      "SELECT COUNT(*) as count FROM favorites WHERE article_id = 1",
      on: db,
      with: [],
      expecting: fn(row) { row },
    )
  birdie.snap(string.inspect(rows2), "favorite_count_after_remove")
}

pub fn comment_create_and_delete_test() {
  let db = test_db()
  seed_article(db)
  let assert Ok(rows) =
    sqlight.query(
      "INSERT INTO comments (body, article_id, author_id, created_at)
       VALUES ('Great article!', 1, 1, '2026-01-01')
       RETURNING id, body",
      on: db,
      with: [],
      expecting: fn(row) { row },
    )
  birdie.snap(string.inspect(rows), "comment_created")
  // Delete
  let assert Ok(_) =
    sqlight.exec("DELETE FROM comments WHERE id = 1 AND author_id = 1", on: db)
  let assert Ok(count) =
    sqlight.query(
      "SELECT COUNT(*) FROM comments WHERE article_id = 1",
      on: db,
      with: [],
      expecting: fn(row) { row },
    )
  birdie.snap(string.inspect(count), "comment_deleted")
}

pub fn follow_toggle_test() {
  let db = test_db()
  // Create two users
  let assert Ok(_) =
    sqlight.exec(
      "INSERT INTO users (username, email, password_hash, bio, image, created_at, updated_at)
       VALUES ('user1', 'u1@example.com', 'hash', '', '', '2026-01-01', '2026-01-01'),
              ('user2', 'u2@example.com', 'hash', '', '', '2026-01-01', '2026-01-01')",
      on: db,
    )
  // Follow
  let assert Ok(_) =
    sqlight.exec(
      "INSERT OR IGNORE INTO follows (follower_id, followed_id) VALUES (1, 2)",
      on: db,
    )
  let assert Ok(rows) =
    sqlight.query(
      "SELECT COUNT(*) FROM follows WHERE follower_id = 1 AND followed_id = 2",
      on: db,
      with: [],
      expecting: fn(row) { row },
    )
  birdie.snap(string.inspect(rows), "follow_established")
}

pub fn tags_and_article_tags_test() {
  let db = test_db()
  seed_article(db)
  let assert Ok(_) =
    sqlight.exec("INSERT OR IGNORE INTO tags (name) VALUES ('gleam'), ('web')", on: db)
  let assert Ok(_) =
    sqlight.exec(
      "INSERT INTO article_tags (article_id, tag_id) VALUES (1, 1), (1, 2)",
      on: db,
    )
  let assert Ok(rows) =
    sqlight.query(
      "SELECT t.name FROM tags t
       JOIN article_tags at_ ON t.id = at_.tag_id
       WHERE at_.article_id = 1
       ORDER BY t.name",
      on: db,
      with: [],
      expecting: fn(row) { row },
    )
  birdie.snap(string.inspect(rows), "article_tags")
}
```

- [ ] **Step 4: Run tests and accept snapshots**

```bash
cd examples/realworld
gleam test
gleam run -m birdie
```

Review and accept the snapshot files.

- [ ] **Step 5: Commit**

```bash
git add examples/realworld/test/ examples/realworld/birdie_snapshots/
git commit -m "Add auth and article tests with birdie snapshots"
```

---

## Implementation Notes

### Things to resolve during implementation

1. **`now_iso8601()` helper**: The placeholder in several page modules needs a real implementation. Use `gleam/erlang` time functions or write an FFI that returns ISO 8601 formatted timestamps. Consider creating a shared `datetime.gleam` utility in the example.

2. **Client-side navigation**: The `navigate_effect` placeholder in page modules needs to call `router.navigate(path)` on the client side. Since page modules compile for both server (Erlang) and client (JavaScript), this needs to be target-conditional or handled through the generated transport layer. One approach: add a `navigate` function to `lando_runtime/effect` that's a no-op on the server and calls `router.navigate` on the client via JS FFI.

3. **Layout and ClientContext**: The current layout system calls `layout(content)` with one argument. But the Conduit layout needs `client_context` to render the nav. Options:
   - Modify the layout codegen to pass `client_context` as a second argument when `client_context.gleam` exists
   - Render the nav inside each page's view instead of in the layout
   - Have the generated app render nav separately from page content

4. **Marmot query signatures**: The exact function signatures generated by marmot depend on how it introspects the SQL. The SQL queries in this plan use named parameters (`:name`), but verify marmot's actual parameter naming convention. Adjust SQL files if marmot expects a different format.

5. **Route parameters**: The `article/slug_.gleam` and `editor/slug_.gleam` pages receive their slug parameter from the route. Verify how the lando codegen passes route parameters to `server_init`. Currently `server_init` takes just `server_context` -- if route params need to be available server-side, the framework may need to pass them through `ServerContext` or via a separate mechanism.

### Update llms.txt

After completing the implementation, update `llms.txt` to add the realworld example to the examples section.
