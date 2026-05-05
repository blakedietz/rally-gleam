import rally_runtime/migrate
import sqlight

@external(erlang, "rally_runtime_test_db_ffi", "clone_db")
fn clone_db(template: sqlight.Connection) -> Result(sqlight.Connection, Nil) {
  let _ = template
  panic as "clone_db: server-side only"
}

@external(erlang, "rally_runtime_test_db_ffi", "pt_put")
fn pt_put(key: String, value: Result(sqlight.Connection, Nil)) -> Nil {
  let _ = key
  let _ = value
  panic as "pt_put: server-side only"
}

@external(erlang, "rally_runtime_test_db_ffi", "pt_get")
fn pt_get(
  key: String,
  default: Result(sqlight.Connection, Nil),
) -> Result(sqlight.Connection, Nil) {
  let _ = key
  let _ = default
  panic as "pt_get: server-side only"
}

fn template_db(migrations_dir: String) -> sqlight.Connection {
  let cache_key = "rally_test_template:" <> migrations_dir
  case pt_get(cache_key, Error(Nil)) {
    Ok(conn) -> conn
    Error(Nil) -> {
      let assert Ok(conn) = sqlight.open(":memory:")
      let assert Ok(_) = migrate.run(conn:, dir: migrations_dir)
      pt_put(cache_key, Ok(conn))
      conn
    }
  }
}

/// Open a fresh in-memory database with migrations already applied.
/// The first call runs migrations into a template db cached via
/// persistent_term. Subsequent calls clone it via SQLite's backup
/// API (page-level copy), avoiding re-running migrations per test.
pub fn setup(migrations_dir: String) -> sqlight.Connection {
  let assert Ok(conn) = clone_db(template_db(migrations_dir))
  conn
}
