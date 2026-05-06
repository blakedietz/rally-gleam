import birdie
import gleam/dynamic/decode
import gleam/string
import simplifile
import sqlight

fn setup_db() -> sqlight.Connection {
  let assert Ok(db) = sqlight.open(":memory:")
  let assert Ok(sql) = simplifile.read("migrations/001_init.sql")
  // Enable foreign keys
  let assert Ok(Nil) = sqlight.exec("PRAGMA foreign_keys = ON;", on: db)
  let assert Ok(Nil) = sqlight.exec(sql, on: db)
  db
}

fn insert_user(db: sqlight.Connection, username: String, email: String) {
  let assert Ok(_) =
    sqlight.query(
      "INSERT INTO users (username, email, password_hash, created_at, updated_at)
       VALUES (?, ?, 'hash123', 1735689600, 1735689600)
       RETURNING id, username, email, bio, image",
      on: db,
      with: [sqlight.text(username), sqlight.text(email)],
      expecting: {
        use id <- decode.field(0, decode.int)
        use uname <- decode.field(1, decode.string)
        use mail <- decode.field(2, decode.string)
        use bio <- decode.field(3, decode.string)
        use image <- decode.field(4, decode.string)
        decode.success(#(id, uname, mail, bio, image))
      },
    )
}

pub fn create_user_test() {
  let db = setup_db()
  let assert Ok(rows) =
    sqlight.query(
      "INSERT INTO users (username, email, password_hash, created_at, updated_at)
       VALUES ('jake', 'jake@example.com', 'hash123', 1735689600, 1735689600)
       RETURNING id, username, email, bio, image",
      on: db,
      with: [],
      expecting: {
        use id <- decode.field(0, decode.int)
        use username <- decode.field(1, decode.string)
        use email <- decode.field(2, decode.string)
        use bio <- decode.field(3, decode.string)
        use image <- decode.field(4, decode.string)
        decode.success(#(id, username, email, bio, image))
      },
    )
  birdie.snap(string.inspect(rows), "create_user")
}

pub fn unique_username_test() {
  let db = setup_db()
  let assert Ok(_) = insert_user(db, "jake", "jake@example.com")
  let result =
    sqlight.query(
      "INSERT INTO users (username, email, password_hash, created_at, updated_at)
       VALUES ('jake', 'other@example.com', 'hash456', 1735689600, 1735689600)
       RETURNING id",
      on: db,
      with: [],
      expecting: decode.field(0, decode.int, decode.success),
    )
  birdie.snap(string.inspect(result), "unique_username_violation")
}

pub fn unique_email_test() {
  let db = setup_db()
  let assert Ok(_) = insert_user(db, "jake", "jake@example.com")
  let result =
    sqlight.query(
      "INSERT INTO users (username, email, password_hash, created_at, updated_at)
       VALUES ('other', 'jake@example.com', 'hash456', 1735689600, 1735689600)
       RETURNING id",
      on: db,
      with: [],
      expecting: decode.field(0, decode.int, decode.success),
    )
  birdie.snap(string.inspect(result), "unique_email_violation")
}

pub fn create_article_test() {
  let db = setup_db()
  let assert Ok(_) = insert_user(db, "jake", "jake@example.com")
  let assert Ok(rows) =
    sqlight.query(
      "INSERT INTO articles (slug, title, description, body, author_id, created_at, updated_at)
       VALUES ('hello-world', 'Hello World', 'A description', 'Article body', 1, 1735689600, 1735689600)
       RETURNING id, slug, title, author_id",
      on: db,
      with: [],
      expecting: {
        use id <- decode.field(0, decode.int)
        use slug <- decode.field(1, decode.string)
        use title <- decode.field(2, decode.string)
        use author_id <- decode.field(3, decode.int)
        decode.success(#(id, slug, title, author_id))
      },
    )
  birdie.snap(string.inspect(rows), "create_article")
}

pub fn favorite_toggle_test() {
  let db = setup_db()
  let assert Ok(_) = insert_user(db, "jake", "jake@example.com")
  let assert Ok(Nil) =
    sqlight.exec(
      "INSERT INTO articles (slug, title, description, body, author_id, created_at, updated_at)
       VALUES ('hello-world', 'Hello World', 'Desc', 'Body', 1, 1735689600, 1735689600)",
      on: db,
    )

  // Add favorite
  let assert Ok(Nil) =
    sqlight.exec(
      "INSERT INTO favorites (user_id, article_id) VALUES (1, 1)",
      on: db,
    )

  let assert Ok(count_after_add) =
    sqlight.query(
      "SELECT COUNT(*) FROM favorites WHERE article_id = 1",
      on: db,
      with: [],
      expecting: decode.field(0, decode.int, decode.success),
    )

  // Remove favorite
  let assert Ok(Nil) =
    sqlight.exec(
      "DELETE FROM favorites WHERE user_id = 1 AND article_id = 1",
      on: db,
    )

  let assert Ok(count_after_remove) =
    sqlight.query(
      "SELECT COUNT(*) FROM favorites WHERE article_id = 1",
      on: db,
      with: [],
      expecting: decode.field(0, decode.int, decode.success),
    )

  birdie.snap(
    string.inspect(#(count_after_add, count_after_remove)),
    "favorite_toggle",
  )
}

pub fn follow_test() {
  let db = setup_db()
  let assert Ok(_) = insert_user(db, "jake", "jake@example.com")
  let assert Ok(_) = insert_user(db, "jane", "jane@example.com")

  let assert Ok(Nil) =
    sqlight.exec(
      "INSERT INTO follows (follower_id, followed_id) VALUES (1, 2)",
      on: db,
    )

  let assert Ok(rows) =
    sqlight.query(
      "SELECT follower_id, followed_id FROM follows WHERE follower_id = 1",
      on: db,
      with: [],
      expecting: {
        use follower <- decode.field(0, decode.int)
        use followed <- decode.field(1, decode.int)
        decode.success(#(follower, followed))
      },
    )
  birdie.snap(string.inspect(rows), "follow_relationship")
}

pub fn comment_test() {
  let db = setup_db()
  let assert Ok(_) = insert_user(db, "jake", "jake@example.com")
  let assert Ok(Nil) =
    sqlight.exec(
      "INSERT INTO articles (slug, title, description, body, author_id, created_at, updated_at)
       VALUES ('hello-world', 'Hello World', 'Desc', 'Body', 1, 1735689600, 1735689600)",
      on: db,
    )

  let assert Ok(Nil) =
    sqlight.exec(
      "INSERT INTO comments (body, article_id, author_id, created_at)
       VALUES ('Great article!', 1, 1, 1735776000)",
      on: db,
    )

  let assert Ok(rows) =
    sqlight.query(
      "SELECT c.id, c.body, c.created_at, u.username
       FROM comments c JOIN users u ON c.author_id = u.id
       WHERE c.article_id = 1",
      on: db,
      with: [],
      expecting: {
        use id <- decode.field(0, decode.int)
        use body <- decode.field(1, decode.string)
        use created_at <- decode.field(2, decode.int)
        use author <- decode.field(3, decode.string)
        decode.success(#(id, body, created_at, author))
      },
    )
  birdie.snap(string.inspect(rows), "comment_with_author")
}

pub fn session_create_and_lookup_test() {
  let db = setup_db()
  let assert Ok(_) = insert_user(db, "jake", "jake@example.com")

  let assert Ok(Nil) =
    sqlight.exec(
      "INSERT INTO sessions (session_id, user_id, created_at)
       VALUES ('abc123', 1, 1735689600)",
      on: db,
    )

  let assert Ok(rows) =
    sqlight.query(
      "SELECT s.session_id, u.username, u.email
       FROM sessions s JOIN users u ON s.user_id = u.id
       WHERE s.session_id = 'abc123'",
      on: db,
      with: [],
      expecting: {
        use session_id <- decode.field(0, decode.string)
        use username <- decode.field(1, decode.string)
        use email <- decode.field(2, decode.string)
        decode.success(#(session_id, username, email))
      },
    )
  birdie.snap(string.inspect(rows), "session_lookup")
}

pub fn cascade_delete_test() {
  let db = setup_db()
  let assert Ok(_) = insert_user(db, "jake", "jake@example.com")
  let assert Ok(_) = insert_user(db, "jane", "jane@example.com")
  let assert Ok(Nil) =
    sqlight.exec(
      "INSERT INTO articles (slug, title, description, body, author_id, created_at, updated_at)
       VALUES ('hello-world', 'Hello World', 'Desc', 'Body', 1, 1735689600, 1735689600)",
      on: db,
    )
  let assert Ok(Nil) =
    sqlight.exec(
      "INSERT INTO comments (body, article_id, author_id, created_at)
       VALUES ('A comment', 1, 1, 1735689600)",
      on: db,
    )
  let assert Ok(Nil) =
    sqlight.exec(
      "INSERT INTO sessions (session_id, user_id, created_at)
       VALUES ('sess1', 1, 1735689600)",
      on: db,
    )
  let assert Ok(Nil) =
    sqlight.exec(
      "INSERT INTO follows (follower_id, followed_id) VALUES (2, 1)",
      on: db,
    )

  // Delete the article first (cascades to comments, article_tags)
  let assert Ok(Nil) = sqlight.exec("DELETE FROM articles WHERE id = 1", on: db)

  let count_decoder = decode.field(0, decode.int, decode.success)

  let assert Ok(comments_after_article_delete) =
    sqlight.query(
      "SELECT COUNT(*) FROM comments",
      on: db,
      with: [],
      expecting: count_decoder,
    )

  // Now delete the user (cascades to sessions, follows, favorites)
  let assert Ok(Nil) = sqlight.exec("DELETE FROM users WHERE id = 1", on: db)

  let assert Ok(sessions) =
    sqlight.query(
      "SELECT COUNT(*) FROM sessions",
      on: db,
      with: [],
      expecting: count_decoder,
    )
  let assert Ok(follows) =
    sqlight.query(
      "SELECT COUNT(*) FROM follows",
      on: db,
      with: [],
      expecting: count_decoder,
    )

  birdie.snap(
    string.inspect(#(comments_after_article_delete, sessions, follows)),
    "cascade_delete",
  )
}

pub fn tags_test() {
  let db = setup_db()
  let assert Ok(_) = insert_user(db, "jake", "jake@example.com")
  let assert Ok(Nil) =
    sqlight.exec(
      "INSERT INTO articles (slug, title, description, body, author_id, created_at, updated_at)
       VALUES ('hello-world', 'Hello World', 'Desc', 'Body', 1, 1735689600, 1735689600)",
      on: db,
    )

  let assert Ok(Nil) =
    sqlight.exec(
      "INSERT INTO tags (name) VALUES ('gleam'), ('fp'), ('web')",
      on: db,
    )

  let assert Ok(Nil) =
    sqlight.exec(
      "INSERT INTO article_tags (article_id, tag_id) VALUES (1, 1), (1, 2)",
      on: db,
    )

  let assert Ok(rows) =
    sqlight.query(
      "SELECT t.name FROM tags t
       JOIN article_tags at ON t.id = at.tag_id
       WHERE at.article_id = 1
       ORDER BY t.name",
      on: db,
      with: [],
      expecting: decode.field(0, decode.string, decode.success),
    )
  birdie.snap(string.inspect(rows), "article_tags")
}
