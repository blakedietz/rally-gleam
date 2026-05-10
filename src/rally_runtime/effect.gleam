import lustre/effect
import rally_runtime/topics
import rally_runtime/wire

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

/// Call an RPC handler on the server. On the server this is a no-op
/// (the update function is never called server-side). On the client,
/// the generated views module replaces this with a typed transport call.
pub fn rpc(_msg: a, on_response _on_response: fn(b) -> msg) -> Effect(msg) {
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
/// Broadcasts via pg topics for other connections, plus push_outgoing_frame
/// for the sender's own connection (which isn't subscribed to its own topic).
pub fn broadcast_to_page(msg: a) -> Effect(b) {
  let page = get_ws_page()
  let frame = wire.encode_push(page, msg)
  topics.broadcast("page:" <> page, frame)
  push_outgoing_frame(frame)
  effect.none()
}

/// Broadcast a message to every connection in the app.
pub fn broadcast_to_app(msg: a) -> Effect(b) {
  let page = get_ws_page()
  let frame = wire.encode_push(page, msg)
  topics.broadcast("app", frame)
  push_outgoing_frame(frame)
  effect.none()
}

/// Send a ClientContextMsg to update the client's shared context.
/// On the server, encodes and queues a push frame tagged "__ClientContext__".
/// On the client, the generated app dispatches it through client_context.update.
pub fn send_to_client_context(msg: a) -> Effect(b) {
  let frame = wire.encode_push("__ClientContext__", msg)
  push_outgoing_frame(frame)
  effect.none()
}

/// Navigate to a new URL path. Pushes a new history entry and triggers
/// a route change via modem's popstate listener.
/// On the server, this is a no-op.
pub fn navigate(path: String) -> Effect(a) {
  effect.from(fn(_dispatch) {
    let Nil = do_navigate(path)
    Nil
  })
}

@external(javascript, "./rally_effect_ffi.mjs", "navigate")
fn do_navigate(_path: String) -> Nil {
  Nil
}

/// Toggle dark mode. On the client, sets the cookie and toggles the class.
/// On the server, this is a no-op.
pub fn set_dark_mode(_enabled: Bool) -> Effect(a) {
  effect.none()
}

/// Set the language preference cookie.
/// On the server, this is a no-op.
pub fn set_lang(_lang: String) -> Effect(a) {
  effect.none()
}

/// Read the dark mode preference from the cookie.
/// Falls back to prefers-color-scheme media query.
/// On the server, returns False.
pub fn read_dark_mode() -> Bool {
  False
}

/// Read the language preference from the cookie.
/// On the server, returns "en".
pub fn read_lang() -> String {
  "en"
}

/// Broadcast a message to all connections in the current browser session.
pub fn broadcast_to_session(msg: a) -> Effect(b) {
  let page = get_ws_page()
  let session = get_ws_session()
  let frame = wire.encode_push(page, msg)
  topics.broadcast("session:" <> session, frame)
  push_outgoing_frame(frame)
  effect.none()
}

fn do_push(msg: a) -> Nil {
  let page = get_ws_page()
  let frame = wire.encode_push(page, msg)
  push_outgoing_frame(frame)
}

// --- FFI bindings ---

@external(erlang, "rally_runtime_ffi", "put_ws_state")
pub fn put_ws_state(_conn: a, _server_context: b, _page: String) -> Nil {
  Nil
}

@external(erlang, "rally_runtime_ffi", "get_stored_server_context")
pub fn get_stored_server_context() -> Result(a, Nil) {
  Error(Nil)
}

@external(erlang, "rally_runtime_ffi", "get_ws_page")
pub fn get_ws_page() -> String {
  ""
}

@external(erlang, "rally_runtime_ffi", "get_ws_conn")
pub fn get_ws_conn() -> Result(a, Nil) {
  Error(Nil)
}

@external(erlang, "rally_runtime_ffi", "push_outgoing_frame")
fn push_outgoing_frame(_frame: a) -> Nil {
  Nil
}

@external(erlang, "rally_runtime_ffi", "drain_outgoing_frames")
pub fn drain_outgoing_frames() -> List(a) {
  []
}

@external(erlang, "rally_runtime_ffi", "put_ws_session")
pub fn put_ws_session(_session_id: String) -> Nil {
  Nil
}

@external(erlang, "rally_runtime_ffi", "get_ws_session")
pub fn get_ws_session() -> String {
  ""
}

@external(erlang, "rally_runtime_ffi", "decode_rally_push")
pub fn decode_rally_push(_msg: a) -> Result(BitArray, Nil) {
  Error(Nil)
}
