import client_context.{type ClientContext, SignedIn, SignedOut, User}
import datetime
import generated/sql/auth_sql
import gleam/list
import gleam/option.{Some}
import gleam/string
import lando_runtime/effect as lando_effect
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import password
import generated/rpc_dispatch.{Logout, UpdateSettings}
import server_context.{type ServerContext}

pub type Model {
  Model(
    image: String,
    username: String,
    bio: String,
    email: String,
    password: String,
    errors: List(String),
  )
}

pub type Msg {
  UpdatedImage(String)
  UpdatedUsername(String)
  UpdatedBio(String)
  UpdatedEmail(String)
  UpdatedPassword(String)
  ClickedUpdate
  ClickedLogout
  GotUpdate(Result(#(String, String), List(String)))
  GotLogout(Result(Nil, Nil))
}

pub fn init(_client_context: ClientContext) -> #(Model, Effect(Msg)) {
  #(
    Model(
      image: "",
      username: "",
      bio: "",
      email: "",
      password: "",
      errors: [],
    ),
    effect.none(),
  )
}

pub fn update(
  _client_context: ClientContext,
  model: Model,
  msg: Msg,
) -> #(Model, Effect(Msg)) {
  case msg {
    UpdatedImage(val) -> #(Model(..model, image: val), effect.none())
    UpdatedUsername(val) -> #(Model(..model, username: val), effect.none())
    UpdatedBio(val) -> #(Model(..model, bio: val), effect.none())
    UpdatedEmail(val) -> #(Model(..model, email: val), effect.none())
    UpdatedPassword(val) -> #(Model(..model, password: val), effect.none())
    ClickedUpdate -> #(
      model,
      lando_effect.rpc(
        UpdateSettings(
          image: model.image,
          username: model.username,
          bio: model.bio,
          email: model.email,
          password: model.password,
        ),
        on_response: GotUpdate,
      ),
    )
    ClickedLogout -> #(
      model,
      lando_effect.rpc(Logout, on_response: GotLogout),
    )
    GotUpdate(Ok(#(username, image))) -> #(
      Model(..model, errors: []),
      lando_effect.send_to_client_context(SignedIn(User(username:, image:))),
    )
    GotUpdate(Error(errors)) -> #(Model(..model, errors:), effect.none())
    GotLogout(Ok(_)) -> #(
      model,
      effect.batch([
        lando_effect.send_to_client_context(SignedOut),
        lando_effect.navigate("/"),
      ]),
    )
    GotLogout(Error(_)) -> #(model, effect.none())
  }
}

pub fn view(_client_context: ClientContext, model: Model) -> Element(Msg) {
  html.div([attr.class("settings-page")], [
    html.div([attr.class("container page")], [
      html.div([attr.class("row")], [
        html.div([attr.class("col-md-6 offset-md-3 col-xs-12")], [
          html.h1([attr.class("text-xs-center")], [html.text("Your Settings")]),
          error_list(model.errors),
          html.fieldset([], [
            html.fieldset([attr.class("form-group")], [
              html.input([
                attr.class("form-control"),
                attr.type_("text"),
                attr.placeholder("URL of profile picture"),
                attr.value(model.image),
                event.on_input(UpdatedImage),
              ]),
            ]),
            html.fieldset([attr.class("form-group")], [
              html.input([
                attr.class("form-control form-control-lg"),
                attr.type_("text"),
                attr.placeholder("Your Name"),
                attr.value(model.username),
                event.on_input(UpdatedUsername),
              ]),
            ]),
            html.fieldset([attr.class("form-group")], [
              html.textarea(
                [
                  attr.class("form-control form-control-lg"),
                  attr.attribute("rows", "8"),
                  attr.placeholder("Short bio about you"),
                  attr.value(model.bio),
                  event.on_input(UpdatedBio),
                ],
                "",
              ),
            ]),
            html.fieldset([attr.class("form-group")], [
              html.input([
                attr.class("form-control form-control-lg"),
                attr.type_("text"),
                attr.placeholder("Email"),
                attr.value(model.email),
                event.on_input(UpdatedEmail),
              ]),
            ]),
            html.fieldset([attr.class("form-group")], [
              html.input([
                attr.class("form-control form-control-lg"),
                attr.type_("password"),
                attr.placeholder("New Password"),
                attr.value(model.password),
                event.on_input(UpdatedPassword),
              ]),
            ]),
            html.button(
              [
                attr.class("btn btn-lg btn-primary pull-xs-right"),
                attr.type_("button"),
                event.on_click(ClickedUpdate),
              ],
              [html.text("Update Settings")],
            ),
          ]),
          html.hr([]),
          html.button(
            [
              attr.class("btn btn-outline-danger"),
              attr.type_("button"),
              event.on_click(ClickedLogout),
            ],
            [html.text("Or click here to logout.")],
          ),
        ]),
      ]),
    ]),
  ])
}

fn error_list(errors: List(String)) -> Element(msg) {
  html.ul([attr.class("error-messages")], {
    list.map(errors, fn(e) { html.li([], [html.text(e)]) })
  })
}

// --- Server handlers ---

pub fn server_update_settings(
  image image: String,
  username username: String,
  bio bio: String,
  email email: String,
  password password_text: String,
  server_context server_context: ServerContext,
) -> Result(#(String, String), List(String)) {
  let session_id = lando_effect.get_ws_session()
  case
    auth_sql.find_user_by_session(
      db: server_context.db,
      session_id: Some(session_id),
      now: datetime.now_unix(),
    )
  {
    Ok([user]) -> {
      let errors = validate_settings(username, email)
      case errors {
        [] -> {
          let now = datetime.now_unix()
          case string.is_empty(string.trim(password_text)) {
            True -> {
              let assert Ok(_) =
                auth_sql.update_user(
                  db: server_context.db,
                  image:,
                  username:,
                  bio:,
                  email:,
                  now:,
                  user_id: user.id,
                )
              Ok(#(username, image))
            }
            False -> {
              case string.length(password_text) < 8 {
                True -> Error(["Password must be at least 8 characters"])
                False -> {
                  let hash = password.hash(password_text)
                  let assert Ok(_) =
                    auth_sql.update_user_with_password(
                      db: server_context.db,
                      image:,
                      username:,
                      bio:,
                      email:,
                      password_hash: hash,
                      now:,
                      user_id: user.id,
                    )
                  Ok(#(username, image))
                }
              }
            }
          }
        }
        _ -> Error(errors)
      }
    }
    _ -> Error(["You must be logged in"])
  }
}

pub fn server_logout(
  server_context server_context: ServerContext,
) -> Result(Nil, Nil) {
  let session_id = lando_effect.get_ws_session()
  let assert Ok(_) =
    auth_sql.delete_session(
      db: server_context.db,
      session_id: Some(session_id),
    )
  Ok(Nil)
}

fn validate_settings(username: String, email: String) -> List(String) {
  let errors = []
  let errors = case string.is_empty(string.trim(username)) {
    True -> ["Username can't be blank", ..errors]
    False -> errors
  }
  let errors = case string.is_empty(string.trim(email)) {
    True -> ["Email can't be blank", ..errors]
    False -> errors
  }
  errors
}
