import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/otp/actor
import gleam/time/timestamp
import logging
import sqlight

const poll_interval_ms = 1000

const max_attempts = 5

pub type JobHandler =
  fn(String, BitArray) -> Result(Nil, String)

pub type Job {
  Job(
    id: Int,
    name: String,
    payload: BitArray,
    attempts: Int,
  )
}

type Msg {
  Poll
}

type State {
  State(db: sqlight.Connection, handler: JobHandler, self: Subject(Msg))
}

pub fn enqueue(
  db: sqlight.Connection,
  name: String,
  payload: BitArray,
  run_at: Int,
) -> Nil {
  let _ =
    sqlight.query(
      "INSERT INTO jobs (name, payload, run_at, attempts, status) VALUES (?1, ?2, ?3, 0, 'pending')",
      on: db,
      with: [sqlight.text(name), sqlight.blob(payload), sqlight.int(run_at)],
      expecting: decode.success(Nil),
    )
  Nil
}

pub fn enqueue_in(
  db: sqlight.Connection,
  name: String,
  payload: BitArray,
  delay_seconds: Int,
) -> Nil {
  let run_at = unix_seconds() + delay_seconds
  enqueue(db, name, payload, run_at)
}

pub fn start_runner(
  db: sqlight.Connection,
  handler: JobHandler,
) -> Result(actor.Started(Nil), actor.StartError) {
  actor.new_with_initialiser(1000, fn(subject) {
    let selector =
      process.new_selector()
      |> process.select_map(subject, fn(msg) { msg })
    let state = State(db:, handler:, self: subject)
    process.send(subject, Poll)
    actor.initialised(state)
    |> actor.selecting(selector)
    |> Ok
  })
  |> actor.on_message(fn(state, msg) {
    case msg {
      Poll -> {
        process_pending_jobs(state.db, state.handler)
        let _ = process.send_after(state.self, poll_interval_ms, Poll)
        actor.continue(state)
      }
    }
  })
  |> actor.start
}

fn process_pending_jobs(db: sqlight.Connection, handler: JobHandler) -> Nil {
  let now = unix_seconds()
  case fetch_ready_jobs(db, now) {
    [] -> Nil
    jobs -> run_jobs(db, handler, jobs)
  }
}

fn fetch_ready_jobs(db: sqlight.Connection, now: Int) -> List(Job) {
  case
    sqlight.query(
      "UPDATE jobs SET status = 'running'
       WHERE id IN (SELECT id FROM jobs WHERE status = 'pending' AND run_at <= ?1 ORDER BY run_at LIMIT 10)
       RETURNING id, name, payload, attempts",
      on: db,
      with: [sqlight.int(now)],
      expecting: {
        use id <- decode.field(0, decode.int)
        use name <- decode.field(1, decode.string)
        use payload <- decode.field(2, decode.bit_array)
        use attempts <- decode.field(3, decode.int)
        decode.success(Job(id:, name:, payload:, attempts:))
      },
    )
  {
    Ok(jobs) -> jobs
    Error(_) -> []
  }
}

fn run_jobs(
  db: sqlight.Connection,
  handler: JobHandler,
  jobs: List(Job),
) -> Nil {
  case jobs {
    [] -> Nil
    [job, ..rest] -> {
      run_single_job(db, handler, job)
      run_jobs(db, handler, rest)
    }
  }
}

fn run_single_job(
  db: sqlight.Connection,
  handler: JobHandler,
  job: Job,
) -> Nil {
  case handler(job.name, job.payload) {
    Ok(_) -> mark_completed(db, job.id)
    Error(reason) -> {
      let next_attempts = job.attempts + 1
      case next_attempts >= max_attempts {
        True -> {
          mark_dead(db, job.id, reason)
          logging.log(
            logging.Warning,
            "Job " <> job.name <> " dead-lettered after "
            <> int.to_string(max_attempts) <> " attempts: " <> reason,
          )
        }
        False -> {
          // Quadratic backoff: 5s, 20s, 45s, 80s. Spreads retries without
          // requiring jitter since jobs are single-writer (one poller).
          let backoff_seconds = next_attempts * next_attempts * 5
          let retry_at = unix_seconds() + backoff_seconds
          mark_retry(db, job.id, next_attempts, retry_at, reason)
        }
      }
    }
  }
}

fn mark_completed(db: sqlight.Connection, job_id: Int) -> Nil {
  let _ =
    sqlight.query(
      "UPDATE jobs SET status = 'completed' WHERE id = ?1",
      on: db,
      with: [sqlight.int(job_id)],
      expecting: decode.success(Nil),
    )
  Nil
}

fn mark_dead(db: sqlight.Connection, job_id: Int, reason: String) -> Nil {
  let _ =
    sqlight.query(
      "UPDATE jobs SET status = 'dead', last_error = ?2 WHERE id = ?1",
      on: db,
      with: [sqlight.int(job_id), sqlight.text(reason)],
      expecting: decode.success(Nil),
    )
  Nil
}

fn mark_retry(
  db: sqlight.Connection,
  job_id: Int,
  attempts: Int,
  retry_at: Int,
  reason: String,
) -> Nil {
  let _ =
    sqlight.query(
      "UPDATE jobs SET status = 'pending', attempts = ?2, run_at = ?3, last_error = ?4 WHERE id = ?1",
      on: db,
      with: [
        sqlight.int(job_id),
        sqlight.int(attempts),
        sqlight.int(retry_at),
        sqlight.text(reason),
      ],
      expecting: decode.success(Nil),
    )
  Nil
}

fn unix_seconds() -> Int {
  let #(seconds, _nanoseconds) =
    timestamp.to_unix_seconds_and_nanoseconds(timestamp.system_time())
  seconds
}
