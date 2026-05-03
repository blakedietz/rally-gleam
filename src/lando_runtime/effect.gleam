import lustre/effect.{type Effect}

pub fn none() -> Effect(a) {
  effect.none()
}

pub fn from(f: fn(fn(a) -> Nil) -> Nil) -> Effect(a) {
  effect.from(f)
}

/// Send a ToBackend variant to the server over WebSocket.
pub fn send_to_backend(_msg: a) -> Effect(b) {
  effect.none()
}

/// Send a ToFrontend variant to the connected client.
pub fn send_to_client(_msg: a) -> Effect(b) {
  effect.none()
}

/// Broadcast a ToFrontend variant to all clients on a page.
pub fn broadcast(_msg: a) -> Effect(b) {
  effect.none()
}
