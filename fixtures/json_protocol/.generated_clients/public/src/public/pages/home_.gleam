import lustre/element/html

import lustre/element.{type Element}

import lustre/effect.{type Effect}

import gleam/int

pub type ToClient {
  Updated(count: Int)
}

pub type IncrementResult {
  IncrementResult(old: Int, new: Int)
}

pub type Msg {
  Increment
  Decrement
  ServerResponded(count: Int)
}

pub type Model {
  Model(count: Int)
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([], [html.text("Count: " <> int.to_string(model.count))])
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    Increment -> #(Model(model.count + 1), effect.none())
    Decrement -> #(Model(model.count - 1), effect.none())
    ServerResponded(count) -> #(Model(count), effect.none())
  }
}

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model(0), effect.none())
}
