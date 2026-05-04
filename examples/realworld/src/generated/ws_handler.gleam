// Generated stub - will be overwritten by lando codegen
import gleam/erlang/process
import gleam/option.{type Option, None}
import mist.{type WebsocketConnection, type WebsocketMessage}
import server_context.{type ServerContext}

pub type State {
  State
}

pub fn handler(
  state: State,
  _msg: WebsocketMessage(Nil),
  _conn: WebsocketConnection,
) -> mist.Next(State, Nil) {
  mist.continue(state)
}

pub fn on_init(
  _conn: WebsocketConnection,
  _ctx: ServerContext,
  _session_id: String,
) -> #(State, Option(process.Selector(Nil))) {
  #(State, None)
}

pub fn on_close(_state: State) -> Nil {
  Nil
}
