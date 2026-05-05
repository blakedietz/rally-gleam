import gleam/string
import gleeunit/should
import rally_runtime/session

pub fn generate_session_id_test() {
  let id = session.generate_id()
  let assert True = string.length(id) > 0
}

pub fn extract_session_from_cookie_test() {
  let cookie_header = "rally_session=abc123; other=value"
  session.extract_session_id(cookie_header)
  |> should.equal(Ok("abc123"))
}

pub fn extract_session_missing_test() {
  let cookie_header = "other=value"
  session.extract_session_id(cookie_header)
  |> should.equal(Error(Nil))
}

pub fn extract_session_empty_test() {
  session.extract_session_id("")
  |> should.equal(Error(Nil))
}

pub fn set_cookie_header_test() {
  session.set_cookie_header("abc123")
  |> should.equal(
    "rally_session=abc123; Path=/; HttpOnly; SameSite=Lax; Secure",
  )
}
