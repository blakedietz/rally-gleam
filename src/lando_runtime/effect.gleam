import lustre/effect.{type Effect}
import lando_runtime/wire

pub fn none() -> Effect(a) {
  effect.none()
}

pub fn from(f: fn(fn(a) -> Nil) -> Nil) -> Effect(a) {
  effect.from(f)
}

/// Send a ToServer variant to the server over WebSocket.
/// On the server this is a no-op. On the client, the generated
/// transport module provides the real implementation.
pub fn send_to_server(_msg: a) -> Effect(b) {
  effect.none()
}

/// Send a ToClient variant to the connected client.
/// Encodes the message as an ETF push frame and queues it for
/// the WebSocket handler to send after the current dispatch.
pub fn send_to_client(msg: a) -> Effect(b) {
  do_push(msg)
  effect.none()
}

/// Broadcast a ToClient variant to all clients on a page.
/// Currently queues a push to the single connected client.
pub fn broadcast(msg: a) -> Effect(b) {
  do_push(msg)
  effect.none()
}

fn do_push(msg: a) -> Nil {
  let page = get_ws_page()
  let frame = wire.tag_push(page, msg)
  push_outgoing_frame(frame)
}

// --- FFI bindings ---

@external(erlang, "lando_runtime_ffi", "put_ws_state")
pub fn put_ws_state(conn: a, page: String) -> Nil {
  let _ = conn
  let _ = page
  panic as "put_ws_state: server-side only"
}

@external(erlang, "lando_runtime_ffi", "get_ws_page")
fn get_ws_page() -> String {
  panic as "get_ws_page: server-side only"
}

@external(erlang, "lando_runtime_ffi", "get_ws_conn")
pub fn get_ws_conn() -> a {
  panic as "get_ws_conn: server-side only"
}

@external(erlang, "lando_runtime_ffi", "push_outgoing_frame")
fn push_outgoing_frame(frame: a) -> Nil {
  let _ = frame
  panic as "push_outgoing_frame: server-side only"
}

@external(erlang, "lando_runtime_ffi", "drain_outgoing_frames")
pub fn drain_outgoing_frames() -> List(a) {
  panic as "drain_outgoing_frames: server-side only"
}
