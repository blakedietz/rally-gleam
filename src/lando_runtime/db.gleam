import gleam/result
import sqlight

pub fn open(path: String) -> Result(sqlight.Connection, sqlight.Error) {
  use conn <- result.try(sqlight.open(path))
  use _ <- result.try(sqlight.exec("PRAGMA journal_mode=WAL;", on: conn))
  use _ <- result.try(sqlight.exec("PRAGMA busy_timeout=5000;", on: conn))
  use _ <- result.try(sqlight.exec("PRAGMA foreign_keys=ON;", on: conn))
  Ok(conn)
}
