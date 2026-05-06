import rally_runtime/effect as rally_effect

import password

import lustre/event

import lustre/element/html

import lustre/element.{type Element}

import lustre/effect.{type Effect}

import lustre/attribute as attr

import gleam/list

import client_context.{type ClientContext, SignedIn, User}

pub type ServerRegister {
  ServerRegister(username: String, email: String, password: String)
}

pub type Msg {
  UpdatedUsername(String)
  UpdatedEmail(String)
  UpdatedPassword(String)
  ClickedRegister
  GotRegister(Result(#(String, String), List(String)))
}

pub type Model {
  Model(username: String, email: String, password: String, errors: List(String))
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

fn error_list(errors: List(String)) -> Element(msg) {
  html.ul([attr.class("error-messages")], {
    list.map(errors, fn(e) { html.li([], [html.text(e)]) })
  })
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
      rally_effect.rpc(
        ServerRegister(
          username: model.username,
          email: model.email,
          password: model.password,
        ),
        on_response: GotRegister,
      ),
    )
    GotRegister(Ok(#(username, image))) -> #(
      model,
      effect.batch([
        rally_effect.send_to_client_context(SignedIn(User(username:, image:))),
        rally_effect.navigate("/"),
      ]),
    )
    GotRegister(Error(errors)) -> #(Model(..model, errors:), effect.none())
  }
}

pub fn init(_client_context: ClientContext) -> #(Model, Effect(Msg)) {
  #(Model(username: "", email: "", password: "", errors: []), effect.none())
}
