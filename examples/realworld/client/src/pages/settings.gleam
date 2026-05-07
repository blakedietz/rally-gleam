import rally_runtime/effect as rally_effect

import lustre/event

import lustre/element/html

import lustre/element.{type Element}

import lustre/effect.{type Effect}

import lustre/attribute as attr

import gleam/list

import client_context.{type ClientContext, SignedIn, SignedOut, User}

pub type ServerLogout {
  ServerLogout
}

pub type ServerUpdateSettings {
  ServerUpdateSettings(
    image: String,
    username: String,
    bio: String,
    email: String,
    password: String,
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

fn error_list(errors: List(String)) -> Element(msg) {
  html.ul([attr.class("error-messages")], {
    list.map(errors, fn(e) { html.li([], [html.text(e)]) })
  })
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
      rally_effect.rpc(
        ServerUpdateSettings(
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
      rally_effect.rpc(ServerLogout, on_response: GotLogout),
    )
    GotUpdate(Ok(#(username, image))) -> #(
      Model(..model, errors: []),
      rally_effect.send_to_client_context(SignedIn(User(username:, image:))),
    )
    GotUpdate(Error(errors)) -> #(Model(..model, errors:), effect.none())
    GotLogout(Ok(_)) -> #(
      model,
      effect.batch([
        rally_effect.send_to_client_context(SignedOut),
        rally_effect.navigate("/"),
      ]),
    )
    GotLogout(Error(_)) -> #(model, effect.none())
  }
}

pub fn init(_client_context: ClientContext) -> #(Model, Effect(Msg)) {
  #(
    Model(image: "", username: "", bio: "", email: "", password: "", errors: []),
    effect.none(),
  )
}
