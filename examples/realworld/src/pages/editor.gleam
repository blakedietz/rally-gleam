import client_context.{type ClientContext}
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
import server_context.{type ServerContext}
import slug
import sqlight

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

pub type Msg {
  UpdatedTitle(String)
  UpdatedDescription(String)
  UpdatedBody(String)
  UpdatedTagInput(String)
  AddedTag
  RemovedTag(String)
  ClickedPublish
  GotServerMsg(ToClient)
}

pub type ToServer {
  PublishArticle(
    title: String,
    description: String,
    body: String,
    tags: List(String),
  )
}

pub type ToClient {
  ArticlePublished(slug: String)
  EditorErrors(errors: List(String))
}

pub type ServerModel {
  ServerModel
}

// --- Client ---

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

pub fn update(
  _client_context: ClientContext,
  model: Model,
  msg: Msg,
) -> #(Model, Effect(Msg)) {
  case msg {
    UpdatedTitle(val) -> #(Model(..model, title: val), effect.none())
    UpdatedDescription(val) -> #(Model(..model, description: val), effect.none())
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
      lando_effect.send_to_server(PublishArticle(
        title: model.title,
        description: model.description,
        body: model.body,
        tags: model.tags,
      )),
    )
    GotServerMsg(ArticlePublished(_slug)) -> #(
      Model(..model, errors: []),
      effect.none(),
    )
    GotServerMsg(EditorErrors(errors)) -> #(
      Model(..model, errors:),
      effect.none(),
    )
  }
}

// --- View ---

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

fn error_list(errors: List(String)) -> Element(msg) {
  html.ul([attr.class("error-messages")], {
    list.map(errors, fn(e) { html.li([], [html.text(e)]) })
  })
}

// --- Server ---

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
    PublishArticle(title, description, body, tags) -> {
      let errors = validate_article(title, body)
      case errors {
        [] -> {
          let session_id = lando_effect.get_ws_session()
          case get_user_id(server_context.db, session_id) {
            Ok(user_id) -> {
              let now = datetime.now_iso8601()
              let article_slug = slug.from_title(title)
              case
                sqlight.query(
                  "INSERT INTO articles (slug, title, description, body, author_id, created_at, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?) RETURNING id, slug",
                  on: server_context.db,
                  with: [
                    sqlight.text(article_slug),
                    sqlight.text(title),
                    sqlight.text(description),
                    sqlight.text(body),
                    sqlight.int(user_id),
                    sqlight.text(now),
                    sqlight.text(now),
                  ],
                  expecting: article_insert_decoder(),
                )
              {
                Ok([#(article_id, returned_slug)]) -> {
                  save_tags(server_context.db, article_id, tags)
                  #(
                    ServerModel,
                    lando_effect.send_to_client(ArticlePublished(
                      slug: returned_slug,
                    )),
                  )
                }
                _ -> #(
                  ServerModel,
                  lando_effect.send_to_client(EditorErrors([
                    "Failed to create article",
                  ])),
                )
              }
            }
            Error(_) -> #(
              ServerModel,
              lando_effect.send_to_client(EditorErrors([
                "You must be logged in to publish",
              ])),
            )
          }
        }
        _ -> #(ServerModel, lando_effect.send_to_client(EditorErrors(errors)))
      }
    }
  }
}

fn validate_article(title: String, body: String) -> List(String) {
  let errors = []
  let errors = case string.is_empty(string.trim(title)) {
    True -> ["Title can't be blank", ..errors]
    False -> errors
  }
  let errors = case string.is_empty(string.trim(body)) {
    True -> ["Body can't be blank", ..errors]
    False -> errors
  }
  errors
}

fn save_tags(db: sqlight.Connection, article_id: Int, tags: List(String)) -> Nil {
  list.each(tags, fn(tag) {
    let assert Ok(_) =
      sqlight.query(
        "INSERT OR IGNORE INTO tags (name) VALUES (?)",
        on: db,
        with: [sqlight.text(tag)],
        expecting: decode.success(Nil),
      )
    let assert Ok([tag_id]) =
      sqlight.query(
        "SELECT id FROM tags WHERE name = ?",
        on: db,
        with: [sqlight.text(tag)],
        expecting: int_decoder(),
      )
    let assert Ok(_) =
      sqlight.query(
        "INSERT OR IGNORE INTO article_tags (article_id, tag_id) VALUES (?, ?)",
        on: db,
        with: [sqlight.int(article_id), sqlight.int(tag_id)],
        expecting: decode.success(Nil),
      )
  })
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

fn article_insert_decoder() -> decode.Decoder(#(Int, String)) {
  use id <- decode.field(0, decode.int)
  use s <- decode.field(1, decode.string)
  decode.success(#(id, s))
}

fn int_decoder() -> decode.Decoder(Int) {
  use val <- decode.field(0, decode.int)
  decode.success(val)
}
