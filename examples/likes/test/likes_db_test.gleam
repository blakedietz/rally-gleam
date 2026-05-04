import generated/sql/home_sql
import gleeunit/should
import lando_runtime/test_db
import sqlight

fn setup() -> sqlight.Connection {
  test_db.setup("migrations")
}

pub fn migration_creates_table_test() {
  let db = setup()
  let assert Ok([row]) = home_sql.get_likes(db:)
  row.count |> should.equal(0)
}

pub fn migration_is_idempotent_test() {
  let db = setup()
  let assert Ok([row]) = home_sql.get_likes(db:)
  row.count |> should.equal(0)
}

pub fn increment_likes_test() {
  let db = setup()
  let assert Ok(_) = home_sql.increment_likes(db:)
  let assert Ok([row]) = home_sql.get_likes(db:)
  row.count |> should.equal(1)
}

pub fn increment_accumulates_test() {
  let db = setup()
  let assert Ok(_) = home_sql.increment_likes(db:)
  let assert Ok(_) = home_sql.increment_likes(db:)
  let assert Ok(_) = home_sql.increment_likes(db:)
  let assert Ok([row]) = home_sql.get_likes(db:)
  row.count |> should.equal(3)
}
