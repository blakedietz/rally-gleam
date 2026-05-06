import rally_runtime/effect as rally_effect

import lustre/event

import lustre/element/html

import lustre/element.{type Element}

import lustre/effect.{type Effect}

import lustre/attribute as attr

import gleam/string

import gleam/list

import client_context.{type ClientContext}

pub type ServerPublishArticle {
  ServerPublishArticle(
    title: String,
    description: String,
    body: String,
    tags: List(String),
  )
}

pub type Msg {
  UpdatedTitle(String)
  UpdatedDescription(String)
  UpdatedBody(String)
  UpdatedTagInput(String)
  AddedTag
  RemovedTag(String)
  ClickedPublish
  GotPublish(Result(String, List(String)))
}

pub type Model {
  Model(
    title: String,
    description: String,
    body: String,
    tag_input: String,
    tags: List(String),
    errors: List(String),
  )
}

fn error_list(errors: List(String)) -> Element(msg) {
  html.ul([attr.class("error-messages")], {
    list.map(errors, fn(e) { html.li([], [html.text(e)]) })
  })
}

pub fn view(_client_context: ClientContext, model: Model) -> Element(Msg) {
  html.div([attr.class("editor-page")], [
    html.div([attr.class("container page")], [
      html.div([attr.class("row")], [
        html.div([attr.class("col-md-10 offset-md-1 col-xs-12")], [
          error_list(model.errors),
          html.fieldset([], [
            html.fieldset([attr.class("form-group")], [
              html.input([
                attr.class("form-control form-control-lg"),
                attr.type_("text"),
                attr.placeholder("Article Title"),
                attr.value(model.title),
                event.on_input(UpdatedTitle),
              ]),
            ]),
            html.fieldset([attr.class("form-group")], [
              html.input([
                attr.class("form-control"),
                attr.type_("text"),
                attr.placeholder("What's this article about?"),
                attr.value(model.description),
                event.on_input(UpdatedDescription),
              ]),
            ]),
            html.fieldset([attr.class("form-group")], [
              html.textarea(
                [
                  attr.class("form-control"),
                  attr.attribute("rows", "8"),
                  attr.placeholder("Write your article (in markdown)"),
                  attr.value(model.body),
                  event.on_input(UpdatedBody),
                ],
                "",
              ),
            ]),
            html.fieldset([attr.class("form-group")], [
              html.input([
                attr.class("form-control"),
                attr.type_("text"),
                attr.placeholder("Enter tags"),
                attr.value(model.tag_input),
                event.on_input(UpdatedTagInput),
              ]),
              html.div(
                [attr.class("tag-list")],
                list.map(model.tags, fn(tag) {
                  html.span([attr.class("tag-default tag-pill")], [
                    html.i(
                      [
                        attr.class("ion-close-round"),
                        event.on_click(RemovedTag(tag)),
                      ],
                      [],
                    ),
                    html.text(" " <> tag),
                  ])
                }),
              ),
            ]),
            html.button(
              [
                attr.class("btn btn-lg pull-xs-right btn-primary"),
                attr.type_("button"),
                event.on_click(ClickedPublish),
              ],
              [html.text("Publish Article")],
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
    UpdatedTitle(val) -> #(Model(..model, title: val), effect.none())
    UpdatedDescription(val) -> #(
      Model(..model, description: val),
      effect.none(),
    )
    UpdatedBody(val) -> #(Model(..model, body: val), effect.none())
    UpdatedTagInput(val) -> #(Model(..model, tag_input: val), effect.none())
    AddedTag -> {
      let tag = string.trim(model.tag_input)
      case tag == "" || list.contains(model.tags, tag) {
        True -> #(model, effect.none())
        False -> #(
          Model(..model, tags: list.append(model.tags, [tag]), tag_input: ""),
          effect.none(),
        )
      }
    }
    RemovedTag(tag) -> #(
      Model(..model, tags: list.filter(model.tags, fn(t) { t != tag })),
      effect.none(),
    )
    ClickedPublish -> #(
      model,
      rally_effect.rpc(
        ServerPublishArticle(
          title: model.title,
          description: model.description,
          body: model.body,
          tags: model.tags,
        ),
        on_response: GotPublish,
      ),
    )
    GotPublish(Ok(article_slug)) -> #(
      Model(..model, errors: []),
      rally_effect.navigate("/article/" <> article_slug),
    )
    GotPublish(Error(errors)) -> #(Model(..model, errors:), effect.none())
  }
}

pub fn init(_client_context: ClientContext) -> #(Model, Effect(Msg)) {
  #(
    Model(
      title: "",
      description: "",
      body: "",
      tag_input: "",
      tags: [],
      errors: [],
    ),
    effect.none(),
  )
}
