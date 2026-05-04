import client_context.{type ClientContext, SignedIn, User}
import datetime
import gleam/dynamic/decode
import gleam/list
import gleam/string
import lando_runtime/effect as lando_effect
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import password
import server_context.{type ServerContext}
import sqlight

pub type Model {
  Model(username: String, email: String, password: String, errors: List(String))
}

pub type Msg {
  UpdatedUsername(String)
  UpdatedEmail(String)
  UpdatedPassword(String)
  ClickedRegister
  GotServerMsg(ToClient)
}

pub type ToServer {
  SubmitRegister(username: String, email: String, password: String)
}

pub type ToClient {
  Registered(username: String, image: String)
  RegisterError(errors: List(String))
}

pub type ServerModel {
  ServerModel
}

pub fn init(_client_context: ClientContext) -> #(Model, Effect(Msg)) {
  #(Model(username: "", email: "", password: "", errors: []), effect.none())
}

pub fn update(
  _client_context: ClientContext,
  model: Model,
  msg: Msg,
) -> #(Model, Effect(Msg)) {
  case msg {
    UpdatedUsername(val) -> #(Model(..model, username: val), effect.none())
    UpdatedEmail(val) -> #(Model(..model, email: val), effect.none())
    UpdatedPassword(val) -> #(Model(..model, password: val), effect.none())
    ClickedRegister -> #(
      model,
      lando_effect.send_to_server(SubmitRegister(
        model.username,
        model.email,
        model.password,
      )),
    )
    GotServerMsg(Registered(username, image)) -> #(model,
      effect.batch([
        lando_effect.send_to_client_context(SignedIn(User(username:, image:))),
        lando_effect.navigate("/"),
      ]))
    GotServerMsg(RegisterError(errors)) -> #(
      Model(..model, errors:),
      effect.none(),
    )
  }
}

pub fn view(_client_context: ClientContext, model: Model) -> Element(Msg) {
  html.div([attr.class("auth-page")], [
    html.div([attr.class("container page")], [
      html.div([attr.class("row")], [
        html.div([attr.class("col-md-6 offset-md-3 col-xs-12")], [
          html.h1([attr.class("text-xs-center")], [html.text("Sign up")]),
          html.p([attr.class("text-xs-center")], [
            html.a([attr.href("/login")], [html.text("Have an account?")]),
          ]),
          error_list(model.errors),
          html.fieldset([], [
            fieldset_input("text", "Your Name", model.username, UpdatedUsername),
            fieldset_input("text", "Email", model.email, UpdatedEmail),
            fieldset_input(
              "password",
              "Password",
              model.password,
              UpdatedPassword,
            ),
            html.button(
              [
                attr.class("btn btn-lg btn-primary pull-xs-right"),
                attr.type_("button"),
                event.on_click(ClickedRegister),
              ],
              [html.text("Sign up")],
            ),
          ]),
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

fn fieldset_input(
  type_: String,
  placeholder: String,
  value: String,
  on_input_msg: fn(String) -> msg,
) -> Element(msg) {
  html.fieldset([attr.class("form-group")], [
    html.input([
      attr.class("form-control form-control-lg"),
      attr.type_(type_),
      attr.placeholder(placeholder),
      attr.value(value),
      event.on_input(on_input_msg),
    ]),
  ])
}

pub fn server_init(
  _server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  #(ServerModel, effect.none())
}

pub fn server_update(
  _model: ServerModel,
  msg: ToServer,
  server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  case msg {
    SubmitRegister(username, email, password_text) -> {
      let errors = validate_register(username, email, password_text)
      case errors {
        [] -> {
          let session_id = lando_effect.get_ws_session()
          let now = datetime.now_iso8601()
          let hash = password.hash(password_text)
          case
            sqlight.query(
              "INSERT INTO users (username, email, password_hash, bio, image, created_at, updated_at)
               VALUES (?, ?, ?, '', '', ?, ?)
               RETURNING id, username, image",
              on: server_context.db,
              with: [
                sqlight.text(username),
                sqlight.text(email),
                sqlight.text(hash),
                sqlight.text(now),
                sqlight.text(now),
              ],
              expecting: register_decoder(),
            )
          {
            Ok([#(id, uname, image)]) -> {
              let assert Ok(_) =
                sqlight.query(
                  "INSERT OR REPLACE INTO sessions (session_id, user_id, created_at) VALUES (?, ?, ?)",
                  on: server_context.db,
                  with: [
                    sqlight.text(session_id),
                    sqlight.int(id),
                    sqlight.text(now),
                  ],
                  expecting: decode.success(Nil),
                )
              #(
                ServerModel,
                lando_effect.send_to_client(Registered(
                  username: uname,
                  image: image,
                )),
              )
            }
            _ -> #(
              ServerModel,
              lando_effect.send_to_client(RegisterError([
                "Username or email already taken",
              ])),
            )
          }
        }
        _ -> #(ServerModel, lando_effect.send_to_client(RegisterError(errors)))
      }
    }
  }
}

fn validate_register(
  username: String,
  email: String,
  password_text: String,
) -> List(String) {
  let errors = []
  let errors = case string.is_empty(string.trim(username)) {
    True -> ["Username can't be blank", ..errors]
    False -> errors
  }
  let errors = case string.is_empty(string.trim(email)) {
    True -> ["Email can't be blank", ..errors]
    False -> errors
  }
  let errors = case string.length(password_text) < 8 {
    True -> ["Password must be at least 8 characters", ..errors]
    False -> errors
  }
  errors
}

fn register_decoder() -> decode.Decoder(#(Int, String, String)) {
  use id <- decode.field(0, decode.int)
  use username <- decode.field(1, decode.string)
  use image <- decode.field(2, decode.string)
  decode.success(#(id, username, image))
}
