import gleam/dynamic
import gleam/dynamic/decode
import gleam/int
import gleam/result
import gleam/time/timestamp
import global_value
import lando_runtime/jobs
import lando_runtime/wire
import logging
import sqlight

// synchronous=OFF is safe here: this is observability data, not app state.
// Losing a few recent messages on crash is acceptable for the throughput gain.
pub fn open(path: String) -> Result(sqlight.Connection, sqlight.Error) {
  use conn <- result.try(sqlight.open(path))
  use _ <- result.try(sqlight.exec("PRAGMA journal_mode=WAL;", on: conn))
  use _ <- result.try(sqlight.exec("PRAGMA synchronous=OFF;", on: conn))
  use _ <- result.try(sqlight.exec(
    "CREATE TABLE IF NOT EXISTS messages (
  id INTEGER PRIMARY KEY,
  timestamp INTEGER NOT NULL,
  session_id TEXT NOT NULL,
  user_id INTEGER,
  page TEXT NOT NULL,
  direction TEXT NOT NULL,
  variant TEXT NOT NULL,
  payload BLOB,
  elapsed_ms INTEGER
);
CREATE TABLE IF NOT EXISTS jobs (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  payload BLOB NOT NULL,
  run_at INTEGER NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending',
  last_error TEXT,
  created_at INTEGER NOT NULL DEFAULT (unixepoch())
);
CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id);
CREATE INDEX IF NOT EXISTS idx_messages_user ON messages(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_page ON messages(page);
CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_jobs_status_run_at ON jobs(status, run_at);",
    on: conn,
  ))
  Ok(conn)
}

pub fn log_to_server(
  db: sqlight.Connection,
  session_id: String,
  user_id: Result(Int, Nil),
  page: String,
  value: dynamic.Dynamic,
  raw_payload: BitArray,
  elapsed_ms: Int,
) -> Nil {
  let variant = wire.variant_tag(value) |> result.unwrap("unknown")
  let now = unix_seconds()
  let _ =
    sqlight.query(
      "INSERT INTO messages (timestamp, session_id, user_id, page, direction, variant, payload, elapsed_ms)
       VALUES (?1, ?2, ?3, ?4, 'to_server', ?5, ?6, ?7)",
      on: db,
      with: [
        sqlight.int(now),
        sqlight.text(session_id),
        nullable_int(user_id),
        sqlight.text(page),
        sqlight.text(variant),
        sqlight.blob(raw_payload),
        sqlight.int(elapsed_ms),
      ],
      expecting: decode.success(Nil),
    )
  Nil
}

pub fn log_to_client(
  db: sqlight.Connection,
  session_id: String,
  user_id: Result(Int, Nil),
  page: String,
  variant: String,
  elapsed_ms: Int,
) -> Nil {
  let now = unix_seconds()
  let _ =
    sqlight.query(
      "INSERT INTO messages (timestamp, session_id, user_id, page, direction, variant, elapsed_ms)
       VALUES (?1, ?2, ?3, ?4, 'to_client', ?5, ?6)",
      on: db,
      with: [
        sqlight.int(now),
        sqlight.text(session_id),
        nullable_int(user_id),
        sqlight.text(page),
        sqlight.text(variant),
        sqlight.int(elapsed_ms),
      ],
      expecting: decode.success(Nil),
    )
  Nil
}

pub fn log_broadcast(
  db: sqlight.Connection,
  page: String,
  variant: String,
) -> Nil {
  let now = unix_seconds()
  let _ =
    sqlight.query(
      "INSERT INTO messages (timestamp, session_id, user_id, page, direction, variant)
       VALUES (?1, '', NULL, ?2, 'broadcast', ?3)",
      on: db,
      with: [
        sqlight.int(now),
        sqlight.text(page),
        sqlight.text(variant),
      ],
      expecting: decode.success(Nil),
    )
  Nil
}

fn nullable_int(val: Result(Int, Nil)) -> sqlight.Value {
  case val {
    Ok(n) -> sqlight.int(n)
    Error(_) -> sqlight.null()
  }
}

fn unix_seconds() -> Int {
  let #(seconds, _nanoseconds) = timestamp.to_unix_seconds_and_nanoseconds(timestamp.system_time())
  seconds
}

/// Call during app startup. Opens the system DB and stores the connection
/// globally so any process (WS handlers) can access it.
pub fn start(path: String) -> Nil {
  case open(path) {
    Ok(conn) -> {
      let _ = global_value.create_with_unique_name("lando_system_db", fn() { conn })
      logging.log(logging.Info, "System DB opened: " <> path)
      let count = message_count(conn)
      logging.log(
        logging.Info,
        "System: " <> int.to_string(count) <> " messages recorded",
      )
      Nil
    }
    Error(err) -> {
      logging.log(logging.Warning, "Failed to open system DB: " <> err.message)
      Nil
    }
  }
}

/// Start the system DB with a background job runner.
pub fn start_with_jobs(path: String, handler: jobs.JobHandler) -> Nil {
  start(path)
  let conn = get_conn()
  case jobs.start_runner(conn, handler) {
    Ok(_) -> logging.log(logging.Info, "Job runner started")
    Error(_) -> logging.log(logging.Warning, "Failed to start job runner")
  }
}

/// Enqueue a job to run at a specific time.
pub fn enqueue(name: String, payload: BitArray, run_at: Int) -> Nil {
  jobs.enqueue(get_conn(), name, payload, run_at)
}

/// Enqueue a job to run after a delay.
pub fn enqueue_in(name: String, payload: BitArray, delay_seconds: Int) -> Nil {
  jobs.enqueue_in(get_conn(), name, payload, delay_seconds)
}

/// Enqueue a job to run immediately.
pub fn enqueue_now(name: String, payload: BitArray) -> Nil {
  jobs.enqueue(get_conn(), name, payload, 0)
}

// create_with_unique_name returns the existing value if already registered.
// The panic lambda only runs if start() was never called.
pub fn get_conn() -> sqlight.Connection {
  global_value.create_with_unique_name("lando_system_db", fn() {
    panic as "system.get_conn called before system.start"
  })
}

fn message_count(db: sqlight.Connection) -> Int {
  case
    sqlight.query(
      "SELECT COUNT(*) FROM messages",
      on: db,
      with: [],
      expecting: { decode.at([0], decode.int) },
    )
  {
    Ok([count]) -> count
    _ -> 0
  }
}
