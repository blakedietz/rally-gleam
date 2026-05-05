import datetime
import generated/sql/auth_sql
import gleam/option.{type Option, None, Some}
import lustre/effect.{type Effect}
import server_context.{type ServerContext}

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

pub fn from_session(
  server_context: ServerContext,
  session_id: String,
) -> ClientContext {
  case
    auth_sql.find_user_by_session(
      db: server_context.db,
      session_id: Some(session_id),
      now: datetime.now_unix(),
    )
  {
    Ok([user]) ->
      ClientContext(
        current_user: Some(User(username: user.username, image: user.image)),
      )
    _ -> ClientContext(current_user: None)
  }
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
