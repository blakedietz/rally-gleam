import generated/sql_sql
import sqlight

pub fn ensure_table(db: sqlight.Connection) -> Nil {
  let assert Ok(_) =
    sqlight.exec(
      "CREATE TABLE IF NOT EXISTS likes (id INTEGER PRIMARY KEY, count INTEGER NOT NULL DEFAULT 0);
     INSERT OR IGNORE INTO likes (id, count) VALUES (1, 0);",
      db,
    )
  Nil
}

pub fn get_likes(db: sqlight.Connection) -> Int {
  case sql_sql.get_likes(db:) {
    Ok([row]) -> row.count
    _ -> 0
  }
}

pub fn increment_likes(db: sqlight.Connection) -> Int {
  let assert Ok(_) = sql_sql.increment_likes(db:)
  get_likes(db)
}
