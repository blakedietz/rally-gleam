import rally_runtime/effect as rally_effect

import lustre/event

import lustre/element/html

import lustre/element.{type Element}

import lustre/effect.{type Effect}

import lustre/attribute as attr

import gleam/string

import gleam/list

import client_context.{type ClientContext}

pub type ServerModel {
  ServerModel(article_id: Int, author_id: Int)
  ServerModelEmpty
}

pub type ToClient {
  ArticleLoaded(
    title: String,
    description: String,
    body: String,
    tags: List(String),
  )
  ArticleUpdated(slug: String)
  EditorErrors(errors: List(String))
}

pub type ToServer {
  UpdateArticle(
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
  ClickedUpdate
  GotServerMsg(ToClient)
}

pub type Model {
  Model(
    slug: String,
    title: String,
    description: String,
    body: String,
    tag_input: String,
    tags: List(String),
    errors: List(String),
    loaded: Bool,
  )
}

fn error_list(errors: List(String)) -> Element(msg) {
  html.ul([attr.class("error-messages")], {
    list.map(errors, fn(e) { html.li([], [html.text(e)]) })
  })
}

pub fn view(_client_context: ClientContext, model: Model) -> Element(Msg) {
  case model.loaded {
    False ->
      html.div([attr.class("editor-page")], [
        html.div([attr.class("container page")], [
          html.text("Loading..."),
        ]),
      ])
    True ->
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
                    event.on_click(ClickedUpdate),
                  ],
                  [html.text("Update Article")],
                ),
              ]),
            ]),
          ]),
        ]),
      ])
  }
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
    ClickedUpdate -> #(
      model,
      send_to_server(UpdateArticle(
        title: model.title,
        description: model.description,
        body: model.body,
        tags: model.tags,
      )),
    )
    GotServerMsg(ArticleLoaded(title, description, body, tags)) -> #(
      Model(..model, title:, description:, body:, tags:, loaded: True),
      effect.none(),
    )
    GotServerMsg(ArticleUpdated(_slug)) -> #(
      Model(..model, errors: []),
      effect.none(),
    )
    GotServerMsg(EditorErrors(errors)) -> #(
      Model(..model, errors:),
      effect.none(),
    )
  }
}

pub fn init(
  _client_context: ClientContext,
  _slug: String,
) -> #(Model, Effect(Msg)) {
  #(
    Model(
      slug: "",
      title: "",
      description: "",
      body: "",
      tag_input: "",
      tags: [],
      errors: [],
      loaded: False,
    ),
    effect.none(),
  )
}

import generated/transport

fn send_to_server(msg: a) -> effect.Effect(b) {
  effect.from(fn(_dispatch) {
    transport.send_to_server("EditorSlug", msg)
    Nil
  })
}
