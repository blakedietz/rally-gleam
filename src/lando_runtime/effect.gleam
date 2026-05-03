import lustre/effect.{type Effect}

/// Send a ToBackend variant to the server over WebSocket.
/// On the client: serializes via ETF and sends.
/// On the server: no-op.
pub fn send_to_backend(_msg: a) -> Effect(b) {
  effect.from(fn(_dispatch) { Nil })
}

/// Send a ToFrontend variant to the connected client.
/// Server-side: serializes via ETF and sends over WebSocket.
/// Client-side: no-op.
pub fn send_to_client(_msg: a) -> Effect(b) {
  effect.from(fn(_dispatch) { Nil })
}

/// Broadcast a ToFrontend variant to all clients on a page.
/// Server-side: serializes via ETF and broadcasts.
/// Client-side: no-op.
pub fn broadcast(_msg: a) -> Effect(b) {
  effect.from(fn(_dispatch) { Nil })
}
