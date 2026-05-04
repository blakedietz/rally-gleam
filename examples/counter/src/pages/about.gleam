import client_context.{type ClientContext}
import lustre/element.{type Element}
import lustre/element/html
import lustre/effect.{type Effect}

pub type Model {
  Model
}

pub type Msg {
  Noop
}

pub fn init(_ctx: ClientContext) -> #(Model, Effect(Msg)) {
  #(Model, effect.none())
}

pub fn update(_ctx: ClientContext, model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    Noop -> #(model, effect.none())
  }
}

pub fn view(_ctx: ClientContext, _model: Model) -> Element(Msg) {
  html.div([], [
    html.h1([], [html.text("About")]),
    html.p([], [html.text("A Lando app with file-based routing, WebSocket RPC, and server-side state.")]),
    html.p([], [html.text("Built with Gleam + Lustre + Lando.")]),
  ])
}
