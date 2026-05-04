import gleeunit/should
import likes_db
import sqlight

fn with_db(f: fn(sqlight.Connection) -> Nil) -> Nil {
  let assert Ok(db) = sqlight.open(":memory:")
  likes_db.ensure_table(db)
  f(db)
}

pub fn ensure_table_is_idempotent_test() {
  let assert Ok(db) = sqlight.open(":memory:")
  likes_db.ensure_table(db)
  likes_db.ensure_table(db)
  likes_db.get_likes(db) |> should.equal(0)
}

pub fn get_likes_starts_at_zero_test() {
  use db <- with_db()
  likes_db.get_likes(db) |> should.equal(0)
}

pub fn increment_likes_returns_new_count_test() {
  use db <- with_db()
  likes_db.increment_likes(db) |> should.equal(1)
}

pub fn increment_likes_accumulates_test() {
  use db <- with_db()
  likes_db.increment_likes(db) |> should.equal(1)
  likes_db.increment_likes(db) |> should.equal(2)
  likes_db.increment_likes(db) |> should.equal(3)
}

pub fn get_likes_reflects_increments_test() {
  use db <- with_db()
  let _ = likes_db.increment_likes(db)
  let _ = likes_db.increment_likes(db)
  likes_db.get_likes(db) |> should.equal(2)
}
