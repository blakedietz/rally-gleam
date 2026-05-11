import gleam/string
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
  BroadcastToAll(msg: ToClient)
}

pub type ToClient {
  Updated(msg: String)
}

pub fn init(_slug: String) -> #(Model, Effect(Msg)) {
  #(Model(0), effect.none())
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    Increment -> #(Model(model.count + 1), effect.none())
    Decrement -> #(Model(model.count - 1), effect.none())
    BroadcastToAll(_msg) -> #(model, effect.none())
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([], [
    html.text("Notifications: " <> string.inspect(model.count)),
  ])
}
