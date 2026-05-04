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

pub type ToServer {
  LoadArticle(slug: String)
  UpdateArticle(
    title: String,
    description: String,
    body: String,
    tags: List(String),
  )
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

pub type ServerModel {
  ServerModel(article_id: Int, author_id: Int)
  ServerModelEmpty
}

// --- Client ---

pub fn init(_client_context: ClientContext) -> #(Model, Effect(Msg)) {
  // TODO: Route params not yet available in framework.
  // Client should send LoadArticle(slug) once URL parsing is wired in.
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
    ClickedUpdate -> #(
      model,
      lando_effect.send_to_server(UpdateArticle(
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

// --- View ---

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

fn error_list(errors: List(String)) -> Element(msg) {
  html.ul([attr.class("error-messages")], {
    list.map(errors, fn(e) { html.li([], [html.text(e)]) })
  })
}

// --- Server ---

pub fn server_init(
  _server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  // TODO: Route params not available in server_init yet.
  // The client must send LoadArticle(slug) to populate the editor.
  #(ServerModelEmpty, effect.none())
}

pub fn server_update(
  model: ServerModel,
  msg: ToServer,
  server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  case msg {
    LoadArticle(article_slug) -> {
      let session_id = lando_effect.get_ws_session()
      case get_user_id(server_context.db, session_id) {
        Ok(user_id) -> {
          case
            sqlight.query(
              "SELECT id, title, description, body, author_id FROM articles WHERE slug = ?",
              on: server_context.db,
              with: [sqlight.text(article_slug)],
              expecting: article_loader_decoder(),
            )
          {
            Ok([#(article_id, title, description, body, author_id)]) -> {
              case author_id == user_id {
                True -> {
                  let tags = fetch_article_tags(server_context.db, article_id)
                  #(
                    ServerModel(article_id:, author_id:),
                    lando_effect.send_to_client(ArticleLoaded(
                      title:,
                      description:,
                      body:,
                      tags:,
                    )),
                  )
                }
                False -> #(
                  ServerModelEmpty,
                  lando_effect.send_to_client(EditorErrors([
                    "You can only edit your own articles",
                  ])),
                )
              }
            }
            _ -> #(
              ServerModelEmpty,
              lando_effect.send_to_client(EditorErrors(["Article not found"])),
            )
          }
        }
        Error(_) -> #(
          ServerModelEmpty,
          lando_effect.send_to_client(EditorErrors([
            "You must be logged in to edit",
          ])),
        )
      }
    }
    UpdateArticle(title, description, body, tags) -> {
      case model {
        ServerModelEmpty -> #(
          ServerModelEmpty,
          lando_effect.send_to_client(EditorErrors(["No article loaded"])),
        )
        ServerModel(article_id, _author_id) -> {
          let errors = validate_article(title, body)
          case errors {
            [] -> {
              let now = datetime.now_iso8601()
              let new_slug = slug.from_title(title)
              let assert Ok(_) =
                sqlight.query(
                  "UPDATE articles SET slug = ?, title = ?, description = ?, body = ?, updated_at = ? WHERE id = ?",
                  on: server_context.db,
                  with: [
                    sqlight.text(new_slug),
                    sqlight.text(title),
                    sqlight.text(description),
                    sqlight.text(body),
                    sqlight.text(now),
                    sqlight.int(article_id),
                  ],
                  expecting: decode.success(Nil),
                )
              // Clear old tags and re-save
              let assert Ok(_) =
                sqlight.query(
                  "DELETE FROM article_tags WHERE article_id = ?",
                  on: server_context.db,
                  with: [sqlight.int(article_id)],
                  expecting: decode.success(Nil),
                )
              save_tags(server_context.db, article_id, tags)
              #(
                model,
                lando_effect.send_to_client(ArticleUpdated(slug: new_slug)),
              )
            }
            _ -> #(
              model,
              lando_effect.send_to_client(EditorErrors(errors)),
            )
          }
        }
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

fn fetch_article_tags(db: sqlight.Connection, article_id: Int) -> List(String) {
  let assert Ok(rows) =
    sqlight.query(
      "SELECT t.name FROM tags t JOIN article_tags at ON t.id = at.tag_id WHERE at.article_id = ?",
      on: db,
      with: [sqlight.int(article_id)],
      expecting: string_decoder(),
    )
  rows
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

fn article_loader_decoder() -> decode.Decoder(#(Int, String, String, String, Int)) {
  use id <- decode.field(0, decode.int)
  use title <- decode.field(1, decode.string)
  use description <- decode.field(2, decode.string)
  use body <- decode.field(3, decode.string)
  use author_id <- decode.field(4, decode.int)
  decode.success(#(id, title, description, body, author_id))
}

fn int_decoder() -> decode.Decoder(Int) {
  use val <- decode.field(0, decode.int)
  decode.success(val)
}

fn string_decoder() -> decode.Decoder(String) {
  use val <- decode.field(0, decode.string)
  decode.success(val)
}
