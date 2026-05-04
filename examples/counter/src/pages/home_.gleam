import client_context.{type ClientContext}
import server_context.{type ServerContext}
import gleam/string
import lustre/element.{type Element}
import lustre/element/html
import lustre/effect.{type Effect}
import lando_runtime/effect as lando_effect

pub type Model { Model(count: Int) }

pub type Msg {
  UserClickedIncrement
  UserClickedDecrement
  GotServerMsg(ToClient)
}

pub type ToServer {
  Increment
  Decrement
}

pub type ToClient { CounterNewValue(value: Int) }

pub type ServerModel { ServerModel(count: Int) }

pub fn init(_ctx: ClientContext) -> #(Model, Effect(Msg)) {
  #(Model(count: 0), effect.none())
}

pub fn update(_ctx: ClientContext, model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UserClickedIncrement -> #(model, lando_effect.send_to_server(Increment))
    UserClickedDecrement -> #(model, lando_effect.send_to_server(Decrement))
    GotServerMsg(CounterNewValue(n)) -> #(Model(count: n), effect.none())
  }
}

pub fn view(_ctx: ClientContext, model: Model) -> Element(Msg) {
  html.div([], [
    html.button([], [html.text("+")]),
    html.text(string.inspect(model.count)),
    html.button([], [html.text("-")]),
  ])
}

pub fn server_update(
  model: ServerModel,
  msg: ToServer,
  _ctx: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  case msg {
    Increment -> #(ServerModel(count: model.count + 1), lando_effect.send_to_client(CounterNewValue(model.count + 1)))
    Decrement -> #(ServerModel(count: model.count - 1), lando_effect.send_to_client(CounterNewValue(model.count - 1)))
  }
}

pub fn server_init(_ctx: ServerContext) -> #(ServerModel, Effect(ToClient)) {
  #(ServerModel(count: 0), effect.none())
}
