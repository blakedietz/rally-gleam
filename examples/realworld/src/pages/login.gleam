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
  Model(email: String, password: String, errors: List(String))
}

pub type Msg {
  UpdatedEmail(String)
  UpdatedPassword(String)
  ClickedLogin
  GotServerMsg(ToClient)
}

pub type ToServer {
  SubmitLogin(email: String, password: String)
}

pub type ToClient {
  Authenticated(username: String, image: String)
  AuthError(errors: List(String))
}

pub type ServerModel {
  ServerModel
}

pub fn init(_client_context: ClientContext) -> #(Model, Effect(Msg)) {
  #(Model(email: "", password: "", errors: []), effect.none())
}

pub fn update(
  _client_context: ClientContext,
  model: Model,
  msg: Msg,
) -> #(Model, Effect(Msg)) {
  case msg {
    UpdatedEmail(val) -> #(Model(..model, email: val), effect.none())
    UpdatedPassword(val) -> #(Model(..model, password: val), effect.none())
    ClickedLogin -> #(
      model,
      lando_effect.send_to_server(SubmitLogin(model.email, model.password)),
    )
    GotServerMsg(Authenticated(username, image)) -> #(model,
      effect.batch([
        lando_effect.send_to_client_context(SignedIn(User(username:, image:))),
        lando_effect.navigate("/"),
      ]))
    GotServerMsg(AuthError(errors)) -> #(
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
          html.h1([attr.class("text-xs-center")], [html.text("Sign in")]),
          html.p([attr.class("text-xs-center")], [
            html.a([attr.href("/register")], [
              html.text("Need an account?"),
            ]),
          ]),
          error_list(model.errors),
          html.fieldset([], [
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
                event.on_click(ClickedLogin),
              ],
              [html.text("Sign in")],
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
    SubmitLogin(email, password_text) -> {
      let errors = validate_login(email, password_text)
      case errors {
        [] -> {
          case
            sqlight.query(
              "SELECT id, username, password_hash, image FROM users WHERE email = ?",
              on: server_context.db,
              with: [sqlight.text(email)],
              expecting: login_decoder(),
            )
          {
            Ok([#(id, username, password_hash, image)]) -> {
              case password.verify(password_text, password_hash) {
                True -> {
                  let session_id = lando_effect.get_ws_session()
                  let now = datetime.now_unix()
                  let assert Ok(_) =
                    sqlight.query(
                      "INSERT OR REPLACE INTO sessions (session_id, user_id, created_at) VALUES (?, ?, ?)",
                      on: server_context.db,
                      with: [
                        sqlight.text(session_id),
                        sqlight.int(id),
                        sqlight.int(now),
                      ],
                      expecting: decode.success(Nil),
                    )
                  #(
                    ServerModel,
                    lando_effect.send_to_client(Authenticated(
                      username:,
                      image:,
                    )),
                  )
                }
                False -> #(
                  ServerModel,
                  lando_effect.send_to_client(AuthError([
                    "Invalid email or password",
                  ])),
                )
              }
            }
            _ -> #(
              ServerModel,
              lando_effect.send_to_client(AuthError([
                "Invalid email or password",
              ])),
            )
          }
        }
        _ -> #(ServerModel, lando_effect.send_to_client(AuthError(errors)))
      }
    }
  }
}

fn validate_login(email: String, password_text: String) -> List(String) {
  let errors = []
  let errors = case string.is_empty(string.trim(email)) {
    True -> ["Email can't be blank", ..errors]
    False -> errors
  }
  let errors = case string.is_empty(string.trim(password_text)) {
    True -> ["Password can't be blank", ..errors]
    False -> errors
  }
  errors
}

fn login_decoder() -> decode.Decoder(#(Int, String, String, String)) {
  use id <- decode.field(0, decode.int)
  use username <- decode.field(1, decode.string)
  use password_hash <- decode.field(2, decode.string)
  use image <- decode.field(3, decode.string)
  decode.success(#(id, username, password_hash, image))
}
