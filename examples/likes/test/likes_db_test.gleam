import generated/sql/pages/home_sql
import gleeunit/should
import lando_runtime/migrate
import sqlight

fn with_db(f: fn(sqlight.Connection) -> Nil) -> Nil {
  let assert Ok(db) = sqlight.open(":memory:")
  let assert Ok(_) = migrate.run(conn: db, dir: "migrations")
  f(db)
}

pub fn migration_creates_table_test() {
  use db <- with_db()
  let assert Ok([row]) = home_sql.get_likes(db:)
  row.count |> should.equal(0)
}

pub fn migration_is_idempotent_test() {
  let assert Ok(db) = sqlight.open(":memory:")
  let assert Ok(_) = migrate.run(conn: db, dir: "migrations")
  let assert Ok(_) = migrate.run(conn: db, dir: "migrations")
  let assert Ok([row]) = home_sql.get_likes(db:)
  row.count |> should.equal(0)
}

pub fn increment_likes_test() {
  use db <- with_db()
  let assert Ok(_) = home_sql.increment_likes(db:)
  let assert Ok([row]) = home_sql.get_likes(db:)
  row.count |> should.equal(1)
}

pub fn increment_accumulates_test() {
  use db <- with_db()
  let assert Ok(_) = home_sql.increment_likes(db:)
  let assert Ok(_) = home_sql.increment_likes(db:)
  let assert Ok(_) = home_sql.increment_likes(db:)
  let assert Ok([row]) = home_sql.get_likes(db:)
  row.count |> should.equal(3)
}
