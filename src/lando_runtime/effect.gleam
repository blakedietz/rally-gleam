import lustre/effect
import lando_runtime/topics
import lando_runtime/wire

pub type Effect(a) =
  effect.Effect(a)

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

/// Broadcast a message to all connections viewing the current page.
pub fn broadcast_to_page(msg: a) -> Effect(b) {
  let page = get_ws_page()
  let frame = wire.tag_push(page, msg)
  topics.broadcast("page:" <> page, frame)
  push_outgoing_frame(frame)
  effect.none()
}

/// Broadcast a message to every connection in the app.
pub fn broadcast_to_app(msg: a) -> Effect(b) {
  let page = get_ws_page()
  let frame = wire.tag_push(page, msg)
  topics.broadcast("app", frame)
  push_outgoing_frame(frame)
  effect.none()
}

/// Send a ClientContextMsg from a page to update the client context.
/// On the server, this is a no-op (client context is client-side only).
pub fn send_to_client_context(_msg: a) -> Effect(b) {
  effect.none()
}

/// Navigate to a new URL path. Pushes a new history entry and triggers
/// a route change via modem's popstate listener.
/// On the server, this is a no-op.
pub fn navigate(path: String) -> Effect(a) {
  effect.from(fn(_dispatch) {
    do_navigate(path)
    Nil
  })
}

@external(javascript, "./lando_effect_ffi.mjs", "navigate")
fn do_navigate(_path: String) -> Nil {
  Nil
}

/// Broadcast a message to all connections in the current browser session.
pub fn broadcast_to_session(msg: a) -> Effect(b) {
  let page = get_ws_page()
  let session = get_ws_session()
  let frame = wire.tag_push(page, msg)
  topics.broadcast("session:" <> session, frame)
  push_outgoing_frame(frame)
  effect.none()
}

fn do_push(msg: a) -> Nil {
  let page = get_ws_page()
  let frame = wire.tag_push(page, msg)
  push_outgoing_frame(frame)
}

// --- FFI bindings ---

@external(erlang, "lando_runtime_ffi", "put_ws_state")
pub fn put_ws_state(conn: a, ctx: b, page: String) -> Nil {
  let _ = conn
  let _ = ctx
  let _ = page
  panic as "put_ws_state: server-side only"
}

@external(erlang, "lando_runtime_ffi", "get_stored_ctx")
pub fn get_stored_ctx() -> a {
  panic as "get_stored_ctx: server-side only"
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

@external(erlang, "lando_runtime_ffi", "put_ws_session")
pub fn put_ws_session(session_id: String) -> Nil {
  let _ = session_id
  panic as "put_ws_session: server-side only"
}

@external(erlang, "lando_runtime_ffi", "get_ws_session")
pub fn get_ws_session() -> String {
  panic as "get_ws_session: server-side only"
}

@external(erlang, "lando_runtime_ffi", "decode_lando_push")
pub fn decode_lando_push(msg: a) -> Result(BitArray, Nil) {
  let _ = msg
  panic as "decode_lando_push: server-side only"
}
