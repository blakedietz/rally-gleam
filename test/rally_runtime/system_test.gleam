import gleam/dynamic/decode
import gleeunit/should
import rally_runtime/system
import sqlight

pub fn open_creates_observability_tables_test() {
  let assert Ok(conn) = system.open(":memory:")

  table_exists(conn, "messages") |> should.equal(True)
  table_exists(conn, "jobs") |> should.equal(True)
}

pub fn log_to_client_persists_message_test() {
  let assert Ok(conn) = system.open(":memory:")

  system.log_to_client(conn, "session-1", Ok(42), "/home", "GotThing", 12)

  messages(conn)
  |> should.equal([#("session-1", 42, "/home", "to_client", "GotThing", 12)])
}

pub fn log_broadcast_persists_message_test() {
  let assert Ok(conn) = system.open(":memory:")

  system.log_broadcast(conn, "/room", "RoomUpdated")

  broadcast_messages(conn)
  |> should.equal([#("", "/room", "broadcast", "RoomUpdated")])
}

fn table_exists(conn: sqlight.Connection, name: String) -> Bool {
  let assert Ok(rows) =
    sqlight.query(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?1",
      on: conn,
      with: [sqlight.text(name)],
      expecting: {
        use table_name <- decode.field(0, decode.string)
        decode.success(table_name)
      },
    )
  case rows {
    [_] -> True
    _ -> False
  }
}

fn messages(
  conn: sqlight.Connection,
) -> List(#(String, Int, String, String, String, Int)) {
  let assert Ok(rows) =
    sqlight.query(
      "SELECT session_id, user_id, page, direction, variant, elapsed_ms FROM messages",
      on: conn,
      with: [],
      expecting: {
        use session_id <- decode.field(0, decode.string)
        use user_id <- decode.field(1, decode.int)
        use page <- decode.field(2, decode.string)
        use direction <- decode.field(3, decode.string)
        use variant <- decode.field(4, decode.string)
        use elapsed_ms <- decode.field(5, decode.int)
        decode.success(#(
          session_id,
          user_id,
          page,
          direction,
          variant,
          elapsed_ms,
        ))
      },
    )
  rows
}

fn broadcast_messages(
  conn: sqlight.Connection,
) -> List(#(String, String, String, String)) {
  let assert Ok(rows) =
    sqlight.query(
      "SELECT session_id, page, direction, variant FROM messages",
      on: conn,
      with: [],
      expecting: {
        use session_id <- decode.field(0, decode.string)
        use page <- decode.field(1, decode.string)
        use direction <- decode.field(2, decode.string)
        use variant <- decode.field(3, decode.string)
        decode.success(#(session_id, page, direction, variant))
      },
    )
  rows
}
