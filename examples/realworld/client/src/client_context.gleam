import lustre/effect.{type Effect}

import gleam/option.{type Option, None, Some}

pub type ClientContextMsg {
  SignedIn(User)
  SignedOut
}

pub type User {
  User(username: String, image: String)
}

pub type ClientContext {
  ClientContext(current_user: Option(User))
}

pub fn update(
  _model: ClientContext,
  msg: ClientContextMsg,
) -> #(ClientContext, Effect(ClientContextMsg)) {
  case msg {
    SignedIn(user) -> #(ClientContext(current_user: Some(user)), effect.none())
    SignedOut -> #(ClientContext(current_user: None), effect.none())
  }
}

pub fn init() -> #(ClientContext, Effect(ClientContextMsg)) {
  #(ClientContext(current_user: None), effect.none())
}
