import gleam/option.{type Option, None, Some}
import lustre/effect.{type Effect}

pub type ClientContext {
  ClientContext(current_user: Option(User))
}

pub type User {
  User(username: String, image: String)
}

pub type ClientContextMsg {
  SignedIn(User)
  SignedOut
}

pub fn init() -> #(ClientContext, Effect(ClientContextMsg)) {
  #(ClientContext(current_user: None), effect.none())
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
