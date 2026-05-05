// Topic pub/sub via OTP pg (process groups). Each WS handler process joins
// topics on connect; broadcasts send frames to all members of a group.
// Erlang-only because pg is a BEAM primitive with no JS equivalent.

@external(erlang, "lando_runtime_topics_ffi", "start")
pub fn start() -> Nil {
  panic as "topics: server-side only"
}

@external(erlang, "lando_runtime_topics_ffi", "join")
pub fn join(topic: String) -> Nil {
  let _ = topic
  panic as "topics: server-side only"
}

@external(erlang, "lando_runtime_topics_ffi", "leave")
pub fn leave(topic: String) -> Nil {
  let _ = topic
  panic as "topics: server-side only"
}

@external(erlang, "lando_runtime_topics_ffi", "members")
pub fn members(topic: String) -> List(a) {
  let _ = topic
  panic as "topics: server-side only"
}

@external(erlang, "lando_runtime_topics_ffi", "broadcast")
pub fn broadcast(topic: String, frame: BitArray) -> Nil {
  let _ = topic
  let _ = frame
  panic as "topics: server-side only"
}

@external(erlang, "lando_runtime_topics_ffi", "receive_frame")
pub fn receive_frame(timeout_ms: Int) -> Result(BitArray, Nil) {
  let _ = timeout_ms
  panic as "topics: server-side only"
}
