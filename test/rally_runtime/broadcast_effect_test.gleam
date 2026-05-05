import gleam/list
import gleeunit/should
import rally_runtime/effect
import rally_runtime/topics

pub fn broadcast_to_page_no_crash_test() {
  topics.start()
  let page = "TestPage"
  effect.put_ws_state(Nil, Nil, page)
  topics.join("page:" <> page)
  // Should not crash - broadcasts to others (none), pushes frame to self
  let _ = effect.broadcast_to_page(#("test", 42))
  // Drain the frame that was pushed to self
  let frames = effect.drain_outgoing_frames()
  list.length(frames) |> should.equal(1)
}

pub fn broadcast_to_app_no_crash_test() {
  topics.start()
  effect.put_ws_state(Nil, Nil, "SomePage")
  topics.join("app")
  let _ = effect.broadcast_to_app(#("test", 42))
  let frames = effect.drain_outgoing_frames()
  list.length(frames) |> should.equal(1)
}

pub fn broadcast_to_session_no_crash_test() {
  topics.start()
  effect.put_ws_state(Nil, Nil, "SomePage")
  effect.put_ws_session("test-session-123")
  topics.join("session:test-session-123")
  let _ = effect.broadcast_to_session(#("test", 42))
  let frames = effect.drain_outgoing_frames()
  list.length(frames) |> should.equal(1)
}
