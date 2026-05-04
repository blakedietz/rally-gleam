import lustre/effect.{type Effect}

pub type ClientContext {
  ClientContext(smashed_likes: Int)
}

pub type ClientContextMsg {
  UpdateLikes(count: Int)
}

pub fn init() -> #(ClientContext, Effect(ClientContextMsg)) {
  #(ClientContext(smashed_likes: 0), effect.none())
}

pub fn update(
  model: ClientContext,
  msg: ClientContextMsg,
) -> #(ClientContext, Effect(ClientContextMsg)) {
  case msg {
    UpdateLikes(count) -> #(ClientContext(smashed_likes: count), effect.none())
  }
}
