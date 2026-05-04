import client_context.{type ClientContext}
import datetime
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lando_runtime/effect as lando_effect
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import server_context.{type ServerContext}
import sqlight

pub type Model {
  Model(
    article: Option(Article),
    comments: List(Comment),
    is_favorited: Bool,
    is_following: Bool,
    favorites_count: Int,
    comment_body: String,
    errors: List(String),
  )
}

pub type Article {
  Article(
    id: Int,
    slug: String,
    title: String,
    description: String,
    body: String,
    created_at: String,
    tags: List(String),
    author_username: String,
    author_image: String,
    author_bio: String,
  )
}

pub type Comment {
  Comment(
    id: Int,
    body: String,
    created_at: String,
    username: String,
    image: String,
  )
}

pub type Msg {
  ClickedFavorite
  ClickedFollow(String)
  UpdatedComment(String)
  ClickedSubmitComment
  ClickedDeleteComment(Int)
  ClickedDeleteArticle
  GotServerMsg(ToClient)
}

pub type ToServer {
  LoadArticle(slug: String)
  ToggleFavorite
  ToggleFollow(username: String)
  SubmitComment(body: String)
  DeleteComment(id: Int)
  DeleteArticle
}

pub type ToClient {
  ArticleData(
    article: Article,
    comments: List(Comment),
    is_favorited: Bool,
    is_following: Bool,
    favorites_count: Int,
  )
  FavoriteUpdated(count: Int, is_favorited: Bool)
  FollowUpdated(is_following: Bool)
  CommentAdded(Comment)
  CommentRemoved(id: Int)
  ArticleDeleted
  ArticleError(String)
}

pub type ServerModel {
  ServerModel(article_id: Int, author_id: Int)
  ServerModelEmpty
}

// --- Client ---

pub fn init(_client_context: ClientContext) -> #(Model, Effect(Msg)) {
  // TODO: Client should send LoadArticle(slug) once URL parsing is wired in.
  #(
    Model(
      article: None,
      comments: [],
      is_favorited: False,
      is_following: False,
      favorites_count: 0,
      comment_body: "",
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
    ClickedFavorite -> #(model, lando_effect.send_to_server(ToggleFavorite))
    ClickedFollow(username) -> #(
      model,
      lando_effect.send_to_server(ToggleFollow(username:)),
    )
    UpdatedComment(val) -> #(Model(..model, comment_body: val), effect.none())
    ClickedSubmitComment -> #(
      Model(..model, comment_body: ""),
      lando_effect.send_to_server(SubmitComment(body: model.comment_body)),
    )
    ClickedDeleteComment(id) -> #(
      model,
      lando_effect.send_to_server(DeleteComment(id:)),
    )
    ClickedDeleteArticle -> #(
      model,
      lando_effect.send_to_server(DeleteArticle),
    )
    GotServerMsg(ArticleData(article, comments, is_favorited, is_following, favorites_count)) -> #(
      Model(
        ..model,
        article: Some(article),
        comments:,
        is_favorited:,
        is_following:,
        favorites_count:,
      ),
      effect.none(),
    )
    GotServerMsg(FavoriteUpdated(count, is_favorited)) -> #(
      Model(..model, favorites_count: count, is_favorited:),
      effect.none(),
    )
    GotServerMsg(FollowUpdated(is_following)) -> #(
      Model(..model, is_following:),
      effect.none(),
    )
    GotServerMsg(CommentAdded(comment)) -> #(
      Model(..model, comments: list.append(model.comments, [comment])),
      effect.none(),
    )
    GotServerMsg(CommentRemoved(id)) -> #(
      Model(
        ..model,
        comments: list.filter(model.comments, fn(c) { c.id != id }),
      ),
      effect.none(),
    )
    GotServerMsg(ArticleDeleted) -> #(model, effect.none())
    GotServerMsg(ArticleError(err)) -> #(
      Model(..model, errors: [err]),
      effect.none(),
    )
  }
}

// --- View ---

pub fn view(client_context: ClientContext, model: Model) -> Element(Msg) {
  case model.article {
    None ->
      html.div([attr.class("article-page")], [
        html.div([attr.class("container page")], [
          html.text("Loading..."),
        ]),
      ])
    Some(article) ->
      html.div([attr.class("article-page")], [
        article_banner(article, model.is_favorited, model.is_following, model.favorites_count),
        html.div([attr.class("container page")], [
          html.div([attr.class("row article-content")], [
            html.div([attr.class("col-md-12")], [
              html.p([], [html.text(article.body)]),
              html.ul(
                [attr.class("tag-list")],
                list.map(article.tags, fn(tag) {
                  html.li([attr.class("tag-default tag-pill tag-outline")], [
                    html.text(tag),
                  ])
                }),
              ),
            ]),
          ]),
          html.hr([]),
          html.div([attr.class("article-actions")], [
            article_meta(article, model.is_favorited, model.is_following, model.favorites_count),
          ]),
          comment_section(client_context, model),
        ]),
      ])
  }
}

fn article_banner(
  article: Article,
  is_favorited: Bool,
  is_following: Bool,
  favorites_count: Int,
) -> Element(Msg) {
  html.div([attr.class("banner")], [
    html.div([attr.class("container")], [
      html.h1([], [html.text(article.title)]),
      article_meta(article, is_favorited, is_following, favorites_count),
    ]),
  ])
}

fn article_meta(
  article: Article,
  is_favorited: Bool,
  is_following: Bool,
  favorites_count: Int,
) -> Element(Msg) {
  let follow_class = case is_following {
    True -> "btn btn-sm btn-secondary"
    False -> "btn btn-sm btn-outline-secondary"
  }
  let follow_text = case is_following {
    True -> "Unfollow " <> article.author_username
    False -> "Follow " <> article.author_username
  }
  let fav_class = case is_favorited {
    True -> "btn btn-sm btn-primary"
    False -> "btn btn-sm btn-outline-primary"
  }
  let fav_text = case is_favorited {
    True -> "Unfavorite Article (" <> int.to_string(favorites_count) <> ")"
    False -> "Favorite Article (" <> int.to_string(favorites_count) <> ")"
  }
  html.div([attr.class("article-meta")], [
    html.a([attr.href("/profile/" <> article.author_username)], [
      html.img([attr.src(article.author_image)]),
    ]),
    html.div([attr.class("info")], [
      html.a(
        [attr.class("author"), attr.href("/profile/" <> article.author_username)],
        [html.text(article.author_username)],
      ),
      html.span([attr.class("date")], [html.text(article.created_at)]),
    ]),
    html.button(
      [attr.class(follow_class), event.on_click(ClickedFollow(article.author_username))],
      [
        html.i([attr.class("ion-plus-round")], []),
        html.text(" " <> follow_text),
      ],
    ),
    html.text(" "),
    html.button(
      [attr.class(fav_class), event.on_click(ClickedFavorite)],
      [
        html.i([attr.class("ion-heart")], []),
        html.text(" " <> fav_text),
      ],
    ),
  ])
}

fn comment_section(
  client_context: ClientContext,
  model: Model,
) -> Element(Msg) {
  html.div([attr.class("row")], [
    html.div([attr.class("col-xs-12 col-md-8 offset-md-2")], list.flatten([
      case client_context.current_user {
        Some(_user) -> [comment_form(model.comment_body)]
        None -> []
      },
      list.map(model.comments, comment_card),
    ])),
  ])
}

fn comment_form(comment_body: String) -> Element(Msg) {
  html.form([attr.class("card comment-form")], [
    html.div([attr.class("card-block")], [
      html.textarea(
        [
          attr.class("form-control"),
          attr.placeholder("Write a comment..."),
          attr.attribute("rows", "3"),
          attr.value(comment_body),
          event.on_input(UpdatedComment),
        ],
        "",
      ),
    ]),
    html.div([attr.class("card-footer")], [
      html.button(
        [
          attr.class("btn btn-sm btn-primary"),
          attr.type_("button"),
          event.on_click(ClickedSubmitComment),
        ],
        [html.text("Post Comment")],
      ),
    ]),
  ])
}

fn comment_card(comment: Comment) -> Element(Msg) {
  html.div([attr.class("card")], [
    html.div([attr.class("card-block")], [
      html.p([attr.class("card-text")], [html.text(comment.body)]),
    ]),
    html.div([attr.class("card-footer")], [
      html.a(
        [attr.class("comment-author"), attr.href("/profile/" <> comment.username)],
        [html.img([attr.class("comment-author-img"), attr.src(comment.image)])],
      ),
      html.text(" "),
      html.a(
        [attr.class("comment-author"), attr.href("/profile/" <> comment.username)],
        [html.text(comment.username)],
      ),
      html.span([attr.class("date-posted")], [html.text(comment.created_at)]),
      html.span([attr.class("mod-options")], [
        html.i(
          [attr.class("ion-trash-a"), event.on_click(ClickedDeleteComment(comment.id))],
          [],
        ),
      ]),
    ]),
  ])
}

// --- Server ---

pub fn server_init(
  _server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  // TODO: Route params not available in server_init yet.
  // The client must send LoadArticle(slug) to populate the page.
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
      let maybe_user_id = get_user_id(server_context.db, session_id)
      case
        sqlight.query(
          "SELECT a.id, a.slug, a.title, a.description, a.body, a.created_at, a.author_id,
                  u.username, u.image, u.bio
           FROM articles a JOIN users u ON a.author_id = u.id
           WHERE a.slug = ?",
          on: server_context.db,
          with: [sqlight.text(article_slug)],
          expecting: full_article_decoder(),
        )
      {
        Ok([row]) -> {
          let tags = fetch_article_tags(server_context.db, row.id)
          let article =
            Article(
              id: row.id,
              slug: row.slug,
              title: row.title,
              description: row.description,
              body: row.body,
              created_at: row.created_at,
              tags:,
              author_username: row.author_username,
              author_image: row.author_image,
              author_bio: row.author_bio,
            )
          let comments = fetch_comments(server_context.db, row.id)
          let #(is_favorited, favorites_count) =
            get_favorite_info(server_context.db, row.id, maybe_user_id)
          let is_following =
            get_follow_status(server_context.db, row.author_id, maybe_user_id)
          #(
            ServerModel(article_id: row.id, author_id: row.author_id),
            lando_effect.send_to_client(ArticleData(
              article:,
              comments:,
              is_favorited:,
              is_following:,
              favorites_count:,
            )),
          )
        }
        _ -> #(
          ServerModelEmpty,
          lando_effect.send_to_client(ArticleError("Article not found")),
        )
      }
    }
    ToggleFavorite -> {
      case model {
        ServerModelEmpty -> #(
          model,
          lando_effect.send_to_client(ArticleError("No article loaded")),
        )
        ServerModel(article_id, _author_id) -> {
          let session_id = lando_effect.get_ws_session()
          case get_user_id(server_context.db, session_id) {
            Ok(user_id) -> {
              // Check if already favorited
              let assert Ok(existing) =
                sqlight.query(
                  "SELECT COUNT(*) FROM favorites WHERE user_id = ? AND article_id = ?",
                  on: server_context.db,
                  with: [sqlight.int(user_id), sqlight.int(article_id)],
                  expecting: int_decoder(),
                )
              case existing {
                [count] if count > 0 -> {
                  let assert Ok(_) =
                    sqlight.query(
                      "DELETE FROM favorites WHERE user_id = ? AND article_id = ?",
                      on: server_context.db,
                      with: [sqlight.int(user_id), sqlight.int(article_id)],
                      expecting: decode.success(Nil),
                    )
                  let new_count = get_favorites_count(server_context.db, article_id)
                  #(
                    model,
                    lando_effect.broadcast_to_page(FavoriteUpdated(
                      count: new_count,
                      is_favorited: False,
                    )),
                  )
                }
                _ -> {
                  let assert Ok(_) =
                    sqlight.query(
                      "INSERT INTO favorites (user_id, article_id) VALUES (?, ?)",
                      on: server_context.db,
                      with: [sqlight.int(user_id), sqlight.int(article_id)],
                      expecting: decode.success(Nil),
                    )
                  let new_count = get_favorites_count(server_context.db, article_id)
                  #(
                    model,
                    lando_effect.broadcast_to_page(FavoriteUpdated(
                      count: new_count,
                      is_favorited: True,
                    )),
                  )
                }
              }
            }
            Error(_) -> #(
              model,
              lando_effect.send_to_client(ArticleError("You must be logged in")),
            )
          }
        }
      }
    }
    ToggleFollow(username) -> {
      let session_id = lando_effect.get_ws_session()
      case get_user_id(server_context.db, session_id) {
        Ok(user_id) -> {
          case get_user_id_by_username(server_context.db, username) {
            Ok(followed_id) -> {
              let assert Ok(existing) =
                sqlight.query(
                  "SELECT COUNT(*) FROM follows WHERE follower_id = ? AND followed_id = ?",
                  on: server_context.db,
                  with: [sqlight.int(user_id), sqlight.int(followed_id)],
                  expecting: int_decoder(),
                )
              case existing {
                [count] if count > 0 -> {
                  let assert Ok(_) =
                    sqlight.query(
                      "DELETE FROM follows WHERE follower_id = ? AND followed_id = ?",
                      on: server_context.db,
                      with: [sqlight.int(user_id), sqlight.int(followed_id)],
                      expecting: decode.success(Nil),
                    )
                  #(
                    model,
                    lando_effect.send_to_client(FollowUpdated(is_following: False)),
                  )
                }
                _ -> {
                  let assert Ok(_) =
                    sqlight.query(
                      "INSERT INTO follows (follower_id, followed_id) VALUES (?, ?)",
                      on: server_context.db,
                      with: [sqlight.int(user_id), sqlight.int(followed_id)],
                      expecting: decode.success(Nil),
                    )
                  #(
                    model,
                    lando_effect.send_to_client(FollowUpdated(is_following: True)),
                  )
                }
              }
            }
            Error(_) -> #(
              model,
              lando_effect.send_to_client(ArticleError("User not found")),
            )
          }
        }
        Error(_) -> #(
          model,
          lando_effect.send_to_client(ArticleError("You must be logged in")),
        )
      }
    }
    SubmitComment(body) -> {
      case model {
        ServerModelEmpty -> #(
          model,
          lando_effect.send_to_client(ArticleError("No article loaded")),
        )
        ServerModel(article_id, _author_id) -> {
          case string.is_empty(string.trim(body)) {
            True -> #(
              model,
              lando_effect.send_to_client(ArticleError("Comment can't be blank")),
            )
            False -> {
              let session_id = lando_effect.get_ws_session()
              case get_user_id(server_context.db, session_id) {
                Ok(user_id) -> {
                  let now = datetime.now_iso8601()
                  case
                    sqlight.query(
                      "INSERT INTO comments (body, article_id, author_id, created_at)
                       VALUES (?, ?, ?, ?) RETURNING id",
                      on: server_context.db,
                      with: [
                        sqlight.text(body),
                        sqlight.int(article_id),
                        sqlight.int(user_id),
                        sqlight.text(now),
                      ],
                      expecting: int_decoder(),
                    )
                  {
                    Ok([comment_id]) -> {
                      let assert Ok([user_row]) =
                        sqlight.query(
                          "SELECT username, image FROM users WHERE id = ?",
                          on: server_context.db,
                          with: [sqlight.int(user_id)],
                          expecting: user_info_decoder(),
                        )
                      let comment =
                        Comment(
                          id: comment_id,
                          body:,
                          created_at: now,
                          username: user_row.0,
                          image: user_row.1,
                        )
                      #(model, lando_effect.broadcast_to_page(CommentAdded(comment)))
                    }
                    _ -> #(
                      model,
                      lando_effect.send_to_client(ArticleError("Failed to post comment")),
                    )
                  }
                }
                Error(_) -> #(
                  model,
                  lando_effect.send_to_client(ArticleError("You must be logged in")),
                )
              }
            }
          }
        }
      }
    }
    DeleteComment(id) -> {
      let session_id = lando_effect.get_ws_session()
      case get_user_id(server_context.db, session_id) {
        Ok(user_id) -> {
          // Only delete if the user owns the comment
          let assert Ok(_) =
            sqlight.query(
              "DELETE FROM comments WHERE id = ? AND author_id = ?",
              on: server_context.db,
              with: [sqlight.int(id), sqlight.int(user_id)],
              expecting: decode.success(Nil),
            )
          #(model, lando_effect.broadcast_to_page(CommentRemoved(id:)))
        }
        Error(_) -> #(
          model,
          lando_effect.send_to_client(ArticleError("You must be logged in")),
        )
      }
    }
    DeleteArticle -> {
      case model {
        ServerModelEmpty -> #(
          model,
          lando_effect.send_to_client(ArticleError("No article loaded")),
        )
        ServerModel(article_id, author_id) -> {
          let session_id = lando_effect.get_ws_session()
          case get_user_id(server_context.db, session_id) {
            Ok(user_id) -> {
              case user_id == author_id {
                True -> {
                  let assert Ok(_) =
                    sqlight.query(
                      "DELETE FROM article_tags WHERE article_id = ?",
                      on: server_context.db,
                      with: [sqlight.int(article_id)],
                      expecting: decode.success(Nil),
                    )
                  let assert Ok(_) =
                    sqlight.query(
                      "DELETE FROM comments WHERE article_id = ?",
                      on: server_context.db,
                      with: [sqlight.int(article_id)],
                      expecting: decode.success(Nil),
                    )
                  let assert Ok(_) =
                    sqlight.query(
                      "DELETE FROM favorites WHERE article_id = ?",
                      on: server_context.db,
                      with: [sqlight.int(article_id)],
                      expecting: decode.success(Nil),
                    )
                  let assert Ok(_) =
                    sqlight.query(
                      "DELETE FROM articles WHERE id = ?",
                      on: server_context.db,
                      with: [sqlight.int(article_id)],
                      expecting: decode.success(Nil),
                    )
                  #(ServerModelEmpty, lando_effect.send_to_client(ArticleDeleted))
                }
                False -> #(
                  model,
                  lando_effect.send_to_client(ArticleError("You can only delete your own articles")),
                )
              }
            }
            Error(_) -> #(
              model,
              lando_effect.send_to_client(ArticleError("You must be logged in")),
            )
          }
        }
      }
    }
  }
}

// --- Helpers ---

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

fn get_user_id_by_username(
  db: sqlight.Connection,
  username: String,
) -> Result(Int, Nil) {
  case
    sqlight.query(
      "SELECT id FROM users WHERE username = ?",
      on: db,
      with: [sqlight.text(username)],
      expecting: int_decoder(),
    )
  {
    Ok([id]) -> Ok(id)
    _ -> Error(Nil)
  }
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

fn fetch_comments(db: sqlight.Connection, article_id: Int) -> List(Comment) {
  let assert Ok(rows) =
    sqlight.query(
      "SELECT c.id, c.body, c.created_at, u.username, u.image
       FROM comments c JOIN users u ON c.author_id = u.id
       WHERE c.article_id = ?
       ORDER BY c.created_at ASC",
      on: db,
      with: [sqlight.int(article_id)],
      expecting: comment_decoder(),
    )
  rows
}

fn get_favorite_info(
  db: sqlight.Connection,
  article_id: Int,
  maybe_user_id: Result(Int, Nil),
) -> #(Bool, Int) {
  let count = get_favorites_count(db, article_id)
  let is_favorited = case maybe_user_id {
    Ok(user_id) -> {
      let assert Ok(rows) =
        sqlight.query(
          "SELECT COUNT(*) FROM favorites WHERE user_id = ? AND article_id = ?",
          on: db,
          with: [sqlight.int(user_id), sqlight.int(article_id)],
          expecting: int_decoder(),
        )
      case rows {
        [c] if c > 0 -> True
        _ -> False
      }
    }
    Error(_) -> False
  }
  #(is_favorited, count)
}

fn get_favorites_count(db: sqlight.Connection, article_id: Int) -> Int {
  let assert Ok([count]) =
    sqlight.query(
      "SELECT COUNT(*) FROM favorites WHERE article_id = ?",
      on: db,
      with: [sqlight.int(article_id)],
      expecting: int_decoder(),
    )
  count
}

fn get_follow_status(
  db: sqlight.Connection,
  followed_id: Int,
  maybe_user_id: Result(Int, Nil),
) -> Bool {
  case maybe_user_id {
    Ok(user_id) -> {
      let assert Ok(rows) =
        sqlight.query(
          "SELECT COUNT(*) FROM follows WHERE follower_id = ? AND followed_id = ?",
          on: db,
          with: [sqlight.int(user_id), sqlight.int(followed_id)],
          expecting: int_decoder(),
        )
      case rows {
        [c] if c > 0 -> True
        _ -> False
      }
    }
    Error(_) -> False
  }
}

// --- Decoders ---

type ArticleRow {
  ArticleRow(
    id: Int,
    slug: String,
    title: String,
    description: String,
    body: String,
    created_at: String,
    author_id: Int,
    author_username: String,
    author_image: String,
    author_bio: String,
  )
}

fn full_article_decoder() -> decode.Decoder(ArticleRow) {
  use id <- decode.field(0, decode.int)
  use article_slug <- decode.field(1, decode.string)
  use title <- decode.field(2, decode.string)
  use description <- decode.field(3, decode.string)
  use body <- decode.field(4, decode.string)
  use created_at <- decode.field(5, decode.string)
  use author_id <- decode.field(6, decode.int)
  use author_username <- decode.field(7, decode.string)
  use author_image <- decode.field(8, decode.string)
  use author_bio <- decode.field(9, decode.string)
  decode.success(ArticleRow(
    id:,
    slug: article_slug,
    title:,
    description:,
    body:,
    created_at:,
    author_id:,
    author_username:,
    author_image:,
    author_bio:,
  ))
}

fn comment_decoder() -> decode.Decoder(Comment) {
  use id <- decode.field(0, decode.int)
  use body <- decode.field(1, decode.string)
  use created_at <- decode.field(2, decode.string)
  use username <- decode.field(3, decode.string)
  use image <- decode.field(4, decode.string)
  decode.success(Comment(id:, body:, created_at:, username:, image:))
}

fn user_info_decoder() -> decode.Decoder(#(String, String)) {
  use username <- decode.field(0, decode.string)
  use image <- decode.field(1, decode.string)
  decode.success(#(username, image))
}

fn int_decoder() -> decode.Decoder(Int) {
  use val <- decode.field(0, decode.int)
  decode.success(val)
}

fn string_decoder() -> decode.Decoder(String) {
  use val <- decode.field(0, decode.string)
  decode.success(val)
}
