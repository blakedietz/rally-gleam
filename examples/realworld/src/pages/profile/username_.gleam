import client_context.{type ClientContext}
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
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
    profile: Option(Profile),
    articles: List(ArticlePreview),
    active_tab: ProfileTab,
    is_following: Bool,
  )
}

pub type Profile {
  Profile(username: String, bio: String, image: String)
}

pub type ArticlePreview {
  ArticlePreview(
    slug: String,
    title: String,
    description: String,
    created_at: String,
    author_username: String,
    author_image: String,
    favorites_count: Int,
  )
}

pub type ProfileTab {
  MyArticles
  FavoritedArticles
}

pub type Msg {
  ClickedFollow
  ClickedTab(ProfileTab)
  GotServerMsg(ToClient)
}

pub type ToServer {
  LoadProfile(username: String)
  ToggleFollow
  SwitchTab(tab_name: String)
}

pub type ToClient {
  ProfileData(
    profile: Profile,
    articles: List(ArticlePreview),
    is_following: Bool,
  )
  FollowUpdated(Bool)
  ProfileArticles(List(ArticlePreview))
}

pub type ServerModel {
  ServerModel(profile_user_id: Int)
  ServerModelEmpty
}

// --- Client ---

pub fn init(_client_context: ClientContext) -> #(Model, Effect(Msg)) {
  // TODO: Client should send LoadProfile(username) once URL parsing is wired in.
  #(
    Model(
      profile: None,
      articles: [],
      active_tab: MyArticles,
      is_following: False,
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
    ClickedFollow -> #(model, lando_effect.send_to_server(ToggleFollow))
    ClickedTab(tab) -> {
      let tab_name = case tab {
        MyArticles -> "my_articles"
        FavoritedArticles -> "favorited"
      }
      #(
        Model(..model, active_tab: tab),
        lando_effect.send_to_server(SwitchTab(tab_name:)),
      )
    }
    GotServerMsg(ProfileData(profile, articles, is_following)) -> #(
      Model(..model, profile: Some(profile), articles:, is_following:),
      effect.none(),
    )
    GotServerMsg(FollowUpdated(is_following)) -> #(
      Model(..model, is_following:),
      effect.none(),
    )
    GotServerMsg(ProfileArticles(articles)) -> #(
      Model(..model, articles:),
      effect.none(),
    )
  }
}

// --- View ---

pub fn view(_client_context: ClientContext, model: Model) -> Element(Msg) {
  case model.profile {
    None ->
      html.div([attr.class("profile-page")], [
        html.div([attr.class("container")], [html.text("Loading...")]),
      ])
    Some(profile) ->
      html.div([attr.class("profile-page")], [
        user_banner(profile, model.is_following),
        html.div([attr.class("container")], [
          html.div([attr.class("row")], [
            html.div([attr.class("col-xs-12 col-md-10 offset-md-1")], [
              articles_toggle(model.active_tab),
              ..list.map(model.articles, article_preview)
            ]),
          ]),
        ]),
      ])
  }
}

fn user_banner(profile: Profile, is_following: Bool) -> Element(Msg) {
  let follow_class = case is_following {
    True -> "btn btn-sm btn-secondary action-btn"
    False -> "btn btn-sm btn-outline-secondary action-btn"
  }
  let follow_text = case is_following {
    True -> "Unfollow " <> profile.username
    False -> "Follow " <> profile.username
  }
  html.div([attr.class("user-info")], [
    html.div([attr.class("container")], [
      html.div([attr.class("row")], [
        html.div([attr.class("col-xs-12 col-md-10 offset-md-1")], [
          html.img([attr.class("user-img"), attr.src(profile.image)]),
          html.h4([], [html.text(profile.username)]),
          html.p([], [html.text(profile.bio)]),
          html.button(
            [attr.class(follow_class), event.on_click(ClickedFollow)],
            [
              html.i([attr.class("ion-plus-round")], []),
              html.text(" " <> follow_text),
            ],
          ),
        ]),
      ]),
    ]),
  ])
}

fn articles_toggle(active_tab: ProfileTab) -> Element(Msg) {
  html.div([attr.class("articles-toggle")], [
    html.ul([attr.class("nav nav-pills outline-active")], [
      tab_link("My Articles", MyArticles, active_tab == MyArticles),
      tab_link("Favorited Articles", FavoritedArticles, active_tab == FavoritedArticles),
    ]),
  ])
}

fn tab_link(label: String, tab: ProfileTab, is_active: Bool) -> Element(Msg) {
  let active_class = case is_active {
    True -> "nav-link active"
    False -> "nav-link"
  }
  html.li([attr.class("nav-item")], [
    html.a(
      [attr.class(active_class), attr.href("#"), event.on_click(ClickedTab(tab))],
      [html.text(label)],
    ),
  ])
}

fn article_preview(article: ArticlePreview) -> Element(Msg) {
  html.div([attr.class("article-preview")], [
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
      html.button([attr.class("btn btn-outline-primary btn-sm pull-xs-right")], [
        html.i([attr.class("ion-heart")], []),
        html.text(" " <> int.to_string(article.favorites_count)),
      ]),
    ]),
    html.a([attr.class("preview-link"), attr.href("/article/" <> article.slug)], [
      html.h1([], [html.text(article.title)]),
      html.p([], [html.text(article.description)]),
      html.span([], [html.text("Read more...")]),
    ]),
  ])
}

// --- Server ---

pub fn server_init(
  _server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  // TODO: Route params not available in server_init yet.
  // The client must send LoadProfile(username) to populate the page.
  #(ServerModelEmpty, effect.none())
}

pub fn server_update(
  model: ServerModel,
  msg: ToServer,
  server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  case msg {
    LoadProfile(username) -> {
      let session_id = lando_effect.get_ws_session()
      let maybe_user_id = get_user_id(server_context.db, session_id)
      case
        sqlight.query(
          "SELECT id, username, bio, image FROM users WHERE username = ?",
          on: server_context.db,
          with: [sqlight.text(username)],
          expecting: profile_user_decoder(),
        )
      {
        Ok([#(profile_user_id, uname, bio, image)]) -> {
          let profile = Profile(username: uname, bio:, image:)
          let articles = fetch_user_articles(server_context.db, profile_user_id)
          let is_following =
            get_follow_status(server_context.db, profile_user_id, maybe_user_id)
          #(
            ServerModel(profile_user_id:),
            lando_effect.send_to_client(ProfileData(
              profile:,
              articles:,
              is_following:,
            )),
          )
        }
        _ -> #(ServerModelEmpty, effect.none())
      }
    }
    ToggleFollow -> {
      case model {
        ServerModelEmpty -> #(model, effect.none())
        ServerModel(profile_user_id) -> {
          let session_id = lando_effect.get_ws_session()
          case get_user_id(server_context.db, session_id) {
            Ok(user_id) -> {
              let assert Ok(existing) =
                sqlight.query(
                  "SELECT COUNT(*) FROM follows WHERE follower_id = ? AND followed_id = ?",
                  on: server_context.db,
                  with: [sqlight.int(user_id), sqlight.int(profile_user_id)],
                  expecting: int_decoder(),
                )
              case existing {
                [count] if count > 0 -> {
                  let assert Ok(_) =
                    sqlight.query(
                      "DELETE FROM follows WHERE follower_id = ? AND followed_id = ?",
                      on: server_context.db,
                      with: [sqlight.int(user_id), sqlight.int(profile_user_id)],
                      expecting: decode.success(Nil),
                    )
                  #(
                    model,
                    lando_effect.send_to_client(FollowUpdated(False)),
                  )
                }
                _ -> {
                  let assert Ok(_) =
                    sqlight.query(
                      "INSERT INTO follows (follower_id, followed_id) VALUES (?, ?)",
                      on: server_context.db,
                      with: [sqlight.int(user_id), sqlight.int(profile_user_id)],
                      expecting: decode.success(Nil),
                    )
                  #(
                    model,
                    lando_effect.send_to_client(FollowUpdated(True)),
                  )
                }
              }
            }
            Error(_) -> #(model, effect.none())
          }
        }
      }
    }
    SwitchTab(tab_name) -> {
      case model {
        ServerModelEmpty -> #(model, effect.none())
        ServerModel(profile_user_id) -> {
          let articles = case tab_name {
            "favorited" ->
              fetch_favorited_articles(server_context.db, profile_user_id)
            _ -> fetch_user_articles(server_context.db, profile_user_id)
          }
          #(model, lando_effect.send_to_client(ProfileArticles(articles)))
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

fn fetch_user_articles(
  db: sqlight.Connection,
  user_id: Int,
) -> List(ArticlePreview) {
  let assert Ok(rows) =
    sqlight.query(
      "SELECT a.slug, a.title, a.description, a.created_at,
              u.username, u.image,
              (SELECT COUNT(*) FROM favorites WHERE article_id = a.id) as fav_count
       FROM articles a JOIN users u ON a.author_id = u.id
       WHERE a.author_id = ?
       ORDER BY a.created_at DESC LIMIT 20",
      on: db,
      with: [sqlight.int(user_id)],
      expecting: article_preview_decoder(),
    )
  rows
}

fn fetch_favorited_articles(
  db: sqlight.Connection,
  user_id: Int,
) -> List(ArticlePreview) {
  let assert Ok(rows) =
    sqlight.query(
      "SELECT a.slug, a.title, a.description, a.created_at,
              u.username, u.image,
              (SELECT COUNT(*) FROM favorites WHERE article_id = a.id) as fav_count
       FROM articles a JOIN users u ON a.author_id = u.id
       JOIN favorites f ON f.article_id = a.id
       WHERE f.user_id = ?
       ORDER BY a.created_at DESC LIMIT 20",
      on: db,
      with: [sqlight.int(user_id)],
      expecting: article_preview_decoder(),
    )
  rows
}

// --- Decoders ---

fn profile_user_decoder() -> decode.Decoder(#(Int, String, String, String)) {
  use id <- decode.field(0, decode.int)
  use username <- decode.field(1, decode.string)
  use bio <- decode.field(2, decode.string)
  use image <- decode.field(3, decode.string)
  decode.success(#(id, username, bio, image))
}

fn article_preview_decoder() -> decode.Decoder(ArticlePreview) {
  use slug <- decode.field(0, decode.string)
  use title <- decode.field(1, decode.string)
  use description <- decode.field(2, decode.string)
  use created_at <- decode.field(3, decode.string)
  use author_username <- decode.field(4, decode.string)
  use author_image <- decode.field(5, decode.string)
  use favorites_count <- decode.field(6, decode.int)
  decode.success(ArticlePreview(
    slug:,
    title:,
    description:,
    created_at:,
    author_username:,
    author_image:,
    favorites_count:,
  ))
}

fn int_decoder() -> decode.Decoder(Int) {
  use val <- decode.field(0, decode.int)
  decode.success(val)
}
