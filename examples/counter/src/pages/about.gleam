import lustre/element.{type Element}
import lustre/element/html

pub type Model {
  Model
}

pub type Msg {
  Noop
}

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model, effect.none())
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    Noop -> #(model, effect.none())
  }
}

pub fn view(_model: Model) -> Element(Msg) {
  html.div([], [
    html.h1([], [html.text("About")]),
    html.p([], [html.text("A Lando app demonstrating file-based routing, WebSocket RPC, and server-side state.")]),
    html.p([], [html.text("Built with Gleam + Lustre + Lando.")]),
  ])
}
