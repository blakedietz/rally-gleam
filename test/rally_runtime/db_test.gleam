import gleeunit/should
import rally_runtime/db

pub fn collapse_whitespace_collapses_runs_test() {
  db.collapse_whitespace(" select   *\n\tfrom    users ")
  |> should.equal("select * from users")
}
