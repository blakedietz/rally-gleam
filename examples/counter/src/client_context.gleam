import lustre/effect.{type Effect}

pub type ClientContext {
  ClientContext
}

pub type ClientContextMsg {
  NoOp
}

pub fn init() -> #(ClientContext, Effect(ClientContextMsg)) {
  #(ClientContext, effect.none())
}

pub fn update(model: ClientContext, msg: ClientContextMsg) -> #(ClientContext, Effect(ClientContextMsg)) {
  case msg {
    NoOp -> #(model, effect.none())
  }
}
