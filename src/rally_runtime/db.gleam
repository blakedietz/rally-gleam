import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/time/duration
import gleam/time/timestamp
import logging
import sqlight

// WAL allows concurrent readers during writes. busy_timeout prevents
// immediate SQLITE_BUSY failures under contention. foreign_keys is
// per-connection in SQLite (off by default), so we enable it here.
pub fn open(path: String) -> Result(sqlight.Connection, sqlight.Error) {
  use conn <- result.try(sqlight.open(path))
  use _ <- result.try(sqlight.exec("PRAGMA journal_mode=WAL;", on: conn))
  use _ <- result.try(sqlight.exec("PRAGMA busy_timeout=5000;", on: conn))
  use _ <- result.try(sqlight.exec("PRAGMA foreign_keys=ON;", on: conn))
  Ok(conn)
}

pub fn one(rows: List(a)) -> Option(a) {
  case rows {
    [row] -> Some(row)
    _ -> None
  }
}

pub fn bool_to_int(val: Bool) -> sqlight.Value {
  sqlight.int(case val {
    True -> 1
    False -> 0
  })
}

pub fn nullable_text(val: Option(String)) -> sqlight.Value {
  case val {
    Some(s) -> sqlight.text(s)
    None -> sqlight.null()
  }
}

/// Timed query wrapper. Same signature as sqlight.query but adds debug
/// logging with query text, param count, elapsed time, and row count.
/// Accumulates timing in the process dictionary for per-request totals.
pub fn query(
  sql sql: String,
  on conn: sqlight.Connection,
  with params: List(sqlight.Value),
  expecting decoder: decode.Decoder(a),
) -> Result(List(a), sqlight.Error) {
  let start = timestamp.system_time()
  let result = sqlight.query(sql, on: conn, with: params, expecting: decoder)
  let elapsed_ms =
    timestamp.difference(start, timestamp.system_time())
    |> duration.to_milliseconds()
  add_db_timing(elapsed_ms)
  log_query(sql: sql, param_count: list.length(params), elapsed_ms: elapsed_ms)
  log_result(result)
  result
}

// SAVEPOINT instead of BEGIN/COMMIT so transaction() calls can nest safely.
// Each gets a unique name to avoid collisions in recursive calls.
pub fn transaction(
  conn: sqlight.Connection,
  body: fn() -> Result(a, sqlight.Error),
) -> Result(a, sqlight.Error) {
  let id = int.absolute_value(unique_id())
  let savepoint = "sp_" <> int.to_string(id)
  use _ <- result.try(sqlight.exec("SAVEPOINT " <> savepoint <> ";", on: conn))
  case body() {
    Ok(val) -> {
      use _ <- result.try(sqlight.exec("RELEASE " <> savepoint <> ";", on: conn))
      Ok(val)
    }
    Error(err) -> {
      let _rollback = sqlight.exec("ROLLBACK TO " <> savepoint <> ";", on: conn)
      use _ <- result.try(sqlight.exec("RELEASE " <> savepoint <> ";", on: conn))
      Error(err)
    }
  }
}

/// Get accumulated DB timing for the current request.
/// Returns #(total_milliseconds, query_count).
pub fn get_timing() -> #(Int, Int) {
  get_db_timing()
}

/// Reset accumulated DB timing. Call at the start of each request/message.
pub fn init_timing() -> Nil {
  init_db_timing()
}

// --- Internal ---

fn log_query(
  sql sql: String,
  param_count param_count: Int,
  elapsed_ms elapsed_ms: Int,
) -> Nil {
  let msg =
    collapse_whitespace(sql)
    <> " | params: "
    <> int.to_string(param_count)
    <> " ("
    <> int.to_string(elapsed_ms)
    <> "ms)"
  logging.log(logging.Debug, msg)
}

fn log_result(result: Result(List(a), sqlight.Error)) -> Nil {
  case result {
    Ok(rows) ->
      logging.log(
        logging.Debug,
        "→ " <> int.to_string(list.length(rows)) <> " row(s)",
      )
    Error(err) -> logging.log(logging.Warning, "→ DB ERROR: " <> err.message)
  }
}

pub fn collapse_whitespace(sql: String) -> String {
  sql
  |> string.replace("\n", " ")
  |> string.replace("\t", " ")
  |> do_collapse_whitespace
  |> string.trim()
}

fn do_collapse_whitespace(sql: String) -> String {
  case string.contains(sql, "  ") {
    True -> do_collapse_whitespace(string.replace(sql, "  ", " "))
    _ -> sql
  }
}

@external(erlang, "rally_runtime_db_ffi", "add_db_timing")
fn add_db_timing(elapsed_ms: Int) -> Nil

@external(erlang, "rally_runtime_db_ffi", "get_db_timing")
fn get_db_timing() -> #(Int, Int)

@external(erlang, "rally_runtime_db_ffi", "init_db_timing")
fn init_db_timing() -> Nil

@external(erlang, "erlang", "unique_integer")
fn unique_id() -> Int
