import gleam/list
import gleam/string

/// Generate a unique session ID.
@external(erlang, "lando_runtime_ffi", "unique_id")
pub fn generate_id() -> String {
  panic as "generate_id: server-side only"
}

/// Extract the lando_session cookie value from a cookie header string.
pub fn extract_session_id(cookie_header: String) -> Result(String, Nil) {
  cookie_header
  |> string.split(";")
  |> list.map(string.trim)
  |> list.find_map(fn(pair) {
    case string.split_once(pair, "=") {
      Ok(#("lando_session", value)) -> Ok(string.trim(value))
      _ -> Error(Nil)
    }
  })
}

/// Build a Set-Cookie header value for a new session.
pub fn set_cookie_header(session_id: String) -> String {
  "lando_session=" <> session_id <> "; Path=/; HttpOnly; SameSite=Lax"
}
