import gleam/int
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import server_context.{type ServerContext}

pub type Model {
  Model(count: Int)
}

pub type Msg {
  Increment
  Decrement
  ServerResponded(count: Int)
  BroadcastToAll(msg: ToClient)
}

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model(0), effect.none())
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    Increment -> #(Model(model.count + 1), effect.none())
    Decrement -> #(Model(model.count - 1), effect.none())
    ServerResponded(count) -> #(Model(count), effect.none())
    BroadcastToAll(_msg) -> #(model, effect.none())
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([], [html.text("Count: " <> int.to_string(model.count))])
}

pub type ServerIncrementBy {
  ServerIncrementBy(amount: Int)
}

pub type IncrementResult {
  IncrementResult(old: Int, new: Int)
}

pub type ToClient {
  Updated(count: Int)
}

pub fn server_increment_by(
  msg msg: ServerIncrementBy,
  server_context server_context: ServerContext,
) -> Result(IncrementResult, Nil) {
  Ok(IncrementResult(old: 0, new: msg.amount))
}

pub fn server_increment(
  msg msg: ServerIncrement,
  server_context server_context: ServerContext,
) -> Result(Int, Nil) {
  Ok(42)
}

pub type ServerIncrement {
  ServerIncrement
}
