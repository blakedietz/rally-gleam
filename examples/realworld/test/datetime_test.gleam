import gleam/string
import gleeunit/should
import datetime

pub fn now_iso8601_format_test() {
  let ts = datetime.now_iso8601()

  // Should be exactly 20 chars: "YYYY-MM-DDTHH:MM:SSZ"
  string.length(ts)
  |> should.equal(20)

  // Should end with Z
  string.ends_with(ts, "Z")
  |> should.be_true

  // Should have T at position 10 (0-indexed)
  let assert Ok(char) = string.first(string.drop_start(ts, 10))
  char
  |> should.equal("T")
}
