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
}

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model(0), effect.none())
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    Increment -> #(Model(model.count + 1), effect.none())
    Decrement -> #(Model(model.count - 1), effect.none())
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([], [html.text("Count: " <> int.to_string(model.count))])
}

pub type ServerIncrement {
  ServerIncrement
}

pub type ToClient {
  Updated(count: Int)
}

pub fn server_increment(
  msg: ServerIncrement,
  server_context: ServerContext,
) -> Result(Int, Nil) {
  Ok(42)
}
