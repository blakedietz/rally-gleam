import client_context.{type ClientContext, SignedIn, SignedOut, User}
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
  GotServerMsg(ToClient)
}

pub type ToServer {
  UpdateSettings(
    image: String,
    username: String,
    bio: String,
    email: String,
    password: String,
  )
  Logout
}

pub type ToClient {
  SettingsLoaded(image: String, username: String, bio: String, email: String)
  SettingsUpdated(username: String, image: String)
  SettingsError(errors: List(String))
  LoggedOut
}

pub type ServerModel {
  ServerModel
}

// --- Client ---

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
      lando_effect.send_to_server(UpdateSettings(
        image: model.image,
        username: model.username,
        bio: model.bio,
        email: model.email,
        password: model.password,
      )),
    )
    ClickedLogout -> #(model, lando_effect.send_to_server(Logout))
    GotServerMsg(SettingsLoaded(image, username, bio, email)) -> #(
      Model(..model, image:, username:, bio:, email:),
      effect.none(),
    )
    GotServerMsg(SettingsUpdated(username, image)) -> #(
      Model(..model, errors: []),
      lando_effect.send_to_client_context(SignedIn(User(username:, image:))),
    )
    GotServerMsg(SettingsError(errors)) -> #(
      Model(..model, errors:),
      effect.none(),
    )
    GotServerMsg(LoggedOut) -> #(
      model,
      lando_effect.send_to_client_context(SignedOut),
    )
  }
}

// --- View ---

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

// --- Server ---

pub fn server_init(
  server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  let session_id = lando_effect.get_ws_session()
  case get_user_id(server_context.db, session_id) {
    Ok(user_id) -> {
      case
        sqlight.query(
          "SELECT image, username, bio, email FROM users WHERE id = ?",
          on: server_context.db,
          with: [sqlight.int(user_id)],
          expecting: settings_decoder(),
        )
      {
        Ok([#(image, username, bio, email)]) -> #(
          ServerModel,
          lando_effect.send_to_client(SettingsLoaded(
            image:,
            username:,
            bio:,
            email:,
          )),
        )
        _ -> #(ServerModel, effect.none())
      }
    }
    Error(_) -> #(ServerModel, effect.none())
  }
}

pub fn server_update(
  _model: ServerModel,
  msg: ToServer,
  server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  case msg {
    UpdateSettings(image, username, bio, email, password_text) -> {
      let session_id = lando_effect.get_ws_session()
      case get_user_id(server_context.db, session_id) {
        Ok(user_id) -> {
          let errors = validate_settings(username, email)
          case errors {
            [] -> {
              let now = datetime.now_iso8601()
              // Update with or without password change
              case string.is_empty(string.trim(password_text)) {
                True -> {
                  let assert Ok(_) =
                    sqlight.query(
                      "UPDATE users SET image = ?, username = ?, bio = ?, email = ?, updated_at = ? WHERE id = ?",
                      on: server_context.db,
                      with: [
                        sqlight.text(image),
                        sqlight.text(username),
                        sqlight.text(bio),
                        sqlight.text(email),
                        sqlight.text(now),
                        sqlight.int(user_id),
                      ],
                      expecting: decode.success(Nil),
                    )
                  #(
                    ServerModel,
                    lando_effect.send_to_client(SettingsUpdated(username:, image:)),
                  )
                }
                False -> {
                  case string.length(password_text) < 8 {
                    True -> #(
                      ServerModel,
                      lando_effect.send_to_client(SettingsError([
                        "Password must be at least 8 characters",
                      ])),
                    )
                    False -> {
                      let hash = password.hash(password_text)
                      let assert Ok(_) =
                        sqlight.query(
                          "UPDATE users SET image = ?, username = ?, bio = ?, email = ?, password_hash = ?, updated_at = ? WHERE id = ?",
                          on: server_context.db,
                          with: [
                            sqlight.text(image),
                            sqlight.text(username),
                            sqlight.text(bio),
                            sqlight.text(email),
                            sqlight.text(hash),
                            sqlight.text(now),
                            sqlight.int(user_id),
                          ],
                          expecting: decode.success(Nil),
                        )
                      #(
                        ServerModel,
                        lando_effect.send_to_client(SettingsUpdated(username:, image:)),
                      )
                    }
                  }
                }
              }
            }
            _ -> #(
              ServerModel,
              lando_effect.send_to_client(SettingsError(errors)),
            )
          }
        }
        Error(_) -> #(
          ServerModel,
          lando_effect.send_to_client(SettingsError(["You must be logged in"])),
        )
      }
    }
    Logout -> {
      let session_id = lando_effect.get_ws_session()
      let assert Ok(_) =
        sqlight.query(
          "DELETE FROM sessions WHERE session_id = ?",
          on: server_context.db,
          with: [sqlight.text(session_id)],
          expecting: decode.success(Nil),
        )
      #(ServerModel, lando_effect.send_to_client(LoggedOut))
    }
  }
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

fn get_user_id(db: sqlight.Connection, session_id: String) -> Result(Int, Nil) {
  case
    sqlight.query(
      "SELECT u.id FROM users u JOIN sessions s ON u.id = s.user_id WHERE s.session_id = ?",
      on: db,
      with: [sqlight.text(session_id)],
      expecting: int_decoder(),
    )
  {
    Ok([id]) -> Ok(id)
    _ -> Error(Nil)
  }
}

fn settings_decoder() -> decode.Decoder(#(String, String, String, String)) {
  use image <- decode.field(0, decode.string)
  use username <- decode.field(1, decode.string)
  use bio <- decode.field(2, decode.string)
  use email <- decode.field(3, decode.string)
  decode.success(#(image, username, bio, email))
}

fn int_decoder() -> decode.Decoder(Int) {
  use val <- decode.field(0, decode.int)
  decode.success(val)
}
