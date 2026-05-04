import gleam/time/timestamp

pub fn now_unix() -> Int {
  let #(seconds, _nanoseconds) =
    timestamp.system_time()
    |> timestamp.to_unix_seconds_and_nanoseconds()
  seconds
}
