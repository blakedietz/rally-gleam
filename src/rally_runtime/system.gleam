//// System database: observability and background jobs.
////
//// Opens a separate SQLite database (system.db) for message logging and
//// the job queue. The connection is stored globally so any WS handler
//// process can log messages. Uses synchronous=OFF because losing a few
//// recent log entries on crash is acceptable for the throughput gain.

import gleam/int
import global_value
import logging
import rally_runtime/internal/system_db
import rally_runtime/jobs

pub type JobHandler =
  fn(String, BitArray) -> Result(Nil, String)

/// Call during app startup. Opens the system DB and stores the connection
/// globally so any process (WS handlers) can access it.
pub fn start(path: String) -> Nil {
  case system_db.open(path) {
    Ok(conn) -> {
      let _global_value =
        global_value.create_with_unique_name("rally_system_db", fn() { conn })
      system_db.store_conn(conn)
      logging.log(logging.Info, "System DB opened: " <> path)
      let count = system_db.message_count(conn)
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
pub fn start_with_jobs(path path: String, handler handler: JobHandler) -> Nil {
  start(path)
  case system_db.get_conn() {
    Ok(conn) -> {
      case jobs.start_runner(db: conn, handler: handler) {
        Ok(_) -> logging.log(logging.Info, "Job runner started")
        _ -> logging.log(logging.Warning, "Failed to start job runner")
      }
    }
    _ -> logging.log(logging.Warning, "System DB not available")
  }
}

/// Enqueue a job to run at a specific time.
pub fn enqueue(
  name name: String,
  payload payload: BitArray,
  run_at run_at: Int,
) -> Nil {
  case system_db.get_conn() {
    Ok(conn) ->
      jobs.enqueue(db: conn, name: name, payload: payload, run_at: run_at)
    _ -> Nil
  }
}

/// Enqueue a job to run after a delay.
pub fn enqueue_in(
  name name: String,
  payload payload: BitArray,
  delay_seconds delay_seconds: Int,
) -> Nil {
  case system_db.get_conn() {
    Ok(conn) ->
      jobs.enqueue_in(
        db: conn,
        name: name,
        payload: payload,
        delay_seconds: delay_seconds,
      )
    _ -> Nil
  }
}

/// Enqueue a job to run immediately.
pub fn enqueue_now(name name: String, payload payload: BitArray) -> Nil {
  case system_db.get_conn() {
    Ok(conn) -> jobs.enqueue(db: conn, name: name, payload: payload, run_at: 0)
    _ -> Nil
  }
}
