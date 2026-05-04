# Realworld (Conduit) Example App

A full implementation of the [RealWorld](https://github.com/gothinkster/realworld) "Conduit" spec as a Lando example app. Based on the [elm-land/realworld-app](https://github.com/elm-land/realworld-app) but replacing the external API layer with Lando's server-side state, SQLite persistence, and ToServer/ToClient messaging.

## Goals

- Prove Lando can handle a real, non-trivial app with auth, CRUD, pagination, and social features
- Showcase real-time broadcasts (live favorites, comments, feed updates) as a natural extension of Lando's messaging model
- Serve as a reference architecture for Lando apps
- Use the Conduit CSS template for a recognizable look

## Approach

Flat pages, no shared domain/service layer. SQLite tables are the shared data model. Each page defines its own marmot SQL queries shaped to what it needs. Auth lives in the page modules for now (designed for eventual extraction into the framework).

## Pages & Routes

| Page | File | Route | Auth required |
|---|---|---|---|
| Home | `pages/home_.gleam` | `/` | No |
| Login | `pages/login.gleam` | `/login` | No |
| Register | `pages/register.gleam` | `/register` | No |
| Settings | `pages/settings.gleam` | `/settings` | Yes |
| New article | `pages/editor.gleam` | `/editor` | Yes |
| Edit article | `pages/editor/slug_.gleam` | `/editor/:slug` | Yes |
| Article detail | `pages/article/slug_.gleam` | `/article/:slug` | No |
| User profile | `pages/profile/username_.gleam` | `/profile/:username` | No |

Plus `pages/layout.gleam` wrapping all pages with the Conduit header and footer.

## Database Schema

```sql
users (
  id INTEGER PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  bio TEXT DEFAULT '',
  image TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)

articles (
  id INTEGER PRIMARY KEY,
  slug TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  body TEXT NOT NULL,
  author_id INTEGER NOT NULL REFERENCES users,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)

tags (
  id INTEGER PRIMARY KEY,
  name TEXT UNIQUE NOT NULL
)

article_tags (
  article_id INTEGER NOT NULL REFERENCES articles,
  tag_id INTEGER NOT NULL REFERENCES tags,
  PRIMARY KEY (article_id, tag_id)
)

favorites (
  user_id INTEGER NOT NULL REFERENCES users,
  article_id INTEGER NOT NULL REFERENCES articles,
  PRIMARY KEY (user_id, article_id)
)

follows (
  follower_id INTEGER NOT NULL REFERENCES users,
  followed_id INTEGER NOT NULL REFERENCES users,
  PRIMARY KEY (follower_id, followed_id)
)

comments (
  id INTEGER PRIMARY KEY,
  body TEXT NOT NULL,
  article_id INTEGER NOT NULL REFERENCES articles,
  author_id INTEGER NOT NULL REFERENCES users,
  created_at TEXT NOT NULL
)

sessions (
  session_id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users,
  created_at TEXT NOT NULL
)
```

Slugs generated from article titles on creation. Timestamps stored as ISO 8601 text. Password hashes via bcrypt (Erlang NIF).

## ServerContext & ClientContext

**ServerContext:**

```gleam
pub type ServerContext {
  ServerContext(db: sqlight.Connection)
}
```

The `session_id` is stored separately by the framework via `effect.put_ws_session()` / `effect.get_ws_session()`. Pages retrieve it in `server_init` and `server_update` to query the `sessions` table and resolve the current user.

**ClientContext:**

```gleam
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
```

Layout reads `client_context.current_user` to render the correct nav (login/register links vs. username/settings/new article links).

All generated code and page modules use `server_context` and `client_context` as parameter names, never abbreviated to `ctx`. The generators have been updated to emit these full names.

## Auth Flow

**Login:**
1. Client sends `Submit(email, password)` via ToServer
2. `server_update` queries `users` by email, verifies bcrypt hash
3. Success: inserts into `sessions` table (linking session ID to user), sends `Authenticated(user)` via `send_to_client`
4. Failure: sends `AuthError(messages)` via `send_to_client`

**Auth checks:**
- `server_init` queries `sessions` with the current session ID to resolve the user (or `None`)
- Auth-required pages (editor, settings) send an error/redirect if no user found
- Optional-auth pages (home, article, profile) adjust behavior based on presence of user

**Logout:**
- Deletes the `sessions` row server-side
- Client sends `send_to_client_context(SignedOut)` to clear nav state

## Messaging Patterns

Each page uses ToServer/ToClient for client-server communication. The pattern for mutations:

- **Success:** persist to SQLite, then `broadcast_to_page` (or `broadcast_to_app`) so all viewers see the update in real time
- **Failure:** skip persistence, `send_to_client` the error back to the requesting client only

### Per-page messaging

**Home (feeds, tags, pagination):**
- `server_init`: sends initial article list + popular tags
- ToServer: `SwitchTab(tab)`, `SelectTag(name)`, `ChangePage(page_num)`
- ToClient: `ArticleList(articles, count)`, `TagList(tags)`
- `broadcast_to_app` after article create/delete to refresh feeds

**Login / Register:**
- ToServer: `SubmitLogin(email, password)`, `SubmitRegister(username, email, password)`
- ToClient: `Authenticated(user)`, `AuthError(List(String))`
- On success: client triggers `send_to_client_context(SignedIn(user))` and navigates to home

**Settings:**
- ToServer: `UpdateSettings(image, username, bio, email, password)`, `Logout`
- ToClient: `SettingsUpdated(user)`, `SettingsError(List(String))`, `LoggedOut`
- On logout: client triggers `send_to_client_context(SignedOut)` and navigates to home

**Editor (new & edit):**
- ToServer: `PublishArticle(title, description, body, tags)` / `UpdateArticle(slug, title, description, body, tags)`
- ToClient: `ArticlePublished(slug)`, `EditorErrors(List(String))`, `ArticleLoaded(article)` (edit only)
- On success: client navigates to the new/updated article page

**Article detail:**
- `server_init`: sends article + comments + favorite/follow state
- ToServer: `ToggleFavorite`, `ToggleFollow(author_username)`, `SubmitComment(body)`, `DeleteComment(id)`, `DeleteArticle`
- ToClient: `ArticleData(article, comments, is_favorited, is_following)`, `FavoriteUpdated(count, is_favorited)`, `FollowUpdated(is_following)`, `CommentAdded(comment)`, `CommentRemoved(id)`, `ArticleDeleted`, `CommentError(String)`
- `broadcast_to_page` after favorite/comment changes so all viewers see updates

**Profile:**
- `server_init`: sends profile info + articles
- ToServer: `ToggleFollow`, `SwitchTab(my_articles | favorited)`
- ToClient: `ProfileData(profile, articles, is_following)`, `FollowUpdated(is_following)`, `ArticleList(articles, count)`

## Styling

Uses the Conduit CSS template via CDN link in the HTML shell. View functions use the Conduit class names directly. No custom CSS.

## Project Structure

```
examples/realworld/
├── migrations/
│   └── 001_init.sql
├── src/
│   ├── app.gleam
│   ├── server_context.gleam
│   ├── client_context.gleam
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
│       ├── home.sql
│       ├── article.sql
│       ├── auth.sql
│       ├── editor.sql
│       ├── settings.sql
│       ├── profile.sql
│       └── comments.sql
├── gleam.toml
├── bin/dev
└── .gitignore
```

## Real-time Behavior

Real-time updates come for free from Lando's broadcast primitives:

- New comments appear for all viewers of an article page (`broadcast_to_page`)
- Favorite count updates for all viewers of an article page (`broadcast_to_page`)
- New/deleted articles update home feeds (`broadcast_to_app`)
- Validation errors and auth failures go only to the requesting client (`send_to_client`)

## Testing

Use birdie snapshot tests for the example app (birdie should also be included as a dependency in `lando new` generated apps). Testing strategy:

- **Server logic tests:** Test `server_update` and `server_init` functions directly by calling them with a test SQLite database and asserting on returned models and effects. Snapshot the results with birdie for readable, reviewable test output.
- **SQL query tests:** Test marmot-generated queries against a seeded test database. Snapshot query results to catch regressions in data shape.
- **Auth flow tests:** Test the full register/login/session lifecycle: register a user, verify session creation, verify session lookup, verify logout clears session.
- **Validation tests:** Test error paths (empty comment, blank title, duplicate username) and snapshot the error responses.
