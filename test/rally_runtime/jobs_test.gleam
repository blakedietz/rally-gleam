import gleam/dynamic/decode
import gleeunit/should
import rally_runtime/jobs
import rally_runtime/system
import sqlight

pub fn run_once_completes_ready_jobs_test() {
  let assert Ok(conn) = system.open(":memory:")
  jobs.enqueue(conn, "welcome", <<"payload":utf8>>, 0)

  jobs.run_once(conn, fn(name, payload) {
    name |> should.equal("welcome")
    payload |> should.equal(<<"payload":utf8>>)
    Ok(Nil)
  })

  job_statuses(conn)
  |> should.equal(["completed"])
}

pub fn run_once_retries_failed_jobs_with_backoff_test() {
  let assert Ok(conn) = system.open(":memory:")
  jobs.enqueue(conn, "retry_me", <<>>, 0)

  jobs.run_once(conn, fn(_, _) { Error("nope") })

  let assert [row] = job_attempts(conn)
  row.status |> should.equal("pending")
  row.attempts |> should.equal(1)
  row.last_error |> should.equal("nope")
  should.equal(row.run_at > 0, True)
}

pub fn run_once_reclaims_running_jobs_test() {
  let assert Ok(conn) = system.open(":memory:")
  let assert Ok(_) =
    sqlight.query(
      "INSERT INTO jobs (name, payload, run_at, attempts, status) VALUES (?1, ?2, ?3, 0, 'running')",
      on: conn,
      with: [
        sqlight.text("orphan"),
        sqlight.blob(<<"payload":utf8>>),
        sqlight.int(0),
      ],
      expecting: decode.success(Nil),
    )

  jobs.run_once(conn, fn(name, payload) {
    name |> should.equal("orphan")
    payload |> should.equal(<<"payload":utf8>>)
    Ok(Nil)
  })

  job_statuses(conn)
  |> should.equal(["completed"])
}

type JobAttempt {
  JobAttempt(status: String, attempts: Int, run_at: Int, last_error: String)
}

fn job_statuses(conn: sqlight.Connection) -> List(String) {
  let assert Ok(rows) =
    sqlight.query(
      "SELECT status FROM jobs ORDER BY id",
      on: conn,
      with: [],
      expecting: {
        use status <- decode.field(0, decode.string)
        decode.success(status)
      },
    )
  rows
}

fn job_attempts(conn: sqlight.Connection) -> List(JobAttempt) {
  let assert Ok(rows) =
    sqlight.query(
      "SELECT status, attempts, run_at, last_error FROM jobs ORDER BY id",
      on: conn,
      with: [],
      expecting: {
        use status <- decode.field(0, decode.string)
        use attempts <- decode.field(1, decode.int)
        use run_at <- decode.field(2, decode.int)
        use last_error <- decode.field(3, decode.string)
        decode.success(JobAttempt(status:, attempts:, run_at:, last_error:))
      },
    )
  rows
}
