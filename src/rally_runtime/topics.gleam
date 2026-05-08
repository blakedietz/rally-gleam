// Topic pub/sub via OTP pg (process groups). Each WS handler process joins
// topics on connect; broadcasts send frames to all members of a group.
// Erlang-only because pg is a BEAM primitive with no JS equivalent.

@external(erlang, "rally_runtime_topics_ffi", "start")
pub fn start() -> Nil {
  Nil
}

@external(erlang, "rally_runtime_topics_ffi", "join")
pub fn join(_topic: String) -> Nil {
  Nil
}

@external(erlang, "rally_runtime_topics_ffi", "leave")
pub fn leave(_topic: String) -> Nil {
  Nil
}

@external(erlang, "rally_runtime_topics_ffi", "members")
pub fn members(_topic: String) -> List(a) {
  []
}

@external(erlang, "rally_runtime_topics_ffi", "broadcast")
pub fn broadcast(_topic: String, _frame: BitArray) -> Nil {
  Nil
}

@external(erlang, "rally_runtime_topics_ffi", "receive_frame")
pub fn receive_frame(_timeout_ms: Int) -> Result(BitArray, Nil) {
  Error(Nil)
}
