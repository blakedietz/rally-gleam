import client_context.{type ClientContext}
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{None, Some}
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
    articles: List(ArticlePreview),
    tags: List(String),
    active_tab: Tab,
    page: Int,
    total: Int,
  )
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

pub type Tab {
  GlobalFeed
  YourFeed
  TagFeed(tag: String)
}

pub type Msg {
  ClickedTab(Tab)
  ClickedPage(Int)
  ClickedTag(String)
  GotServerMsg(ToClient)
}

pub type ToServer {
  SwitchTab(tab_name: String, tag: String)
  ChangePage(page: Int, tab_name: String, tag: String)
}

pub type ToClient {
  HomeData(articles: List(ArticlePreview), tags: List(String), total: Int)
  ArticleListUpdated(articles: List(ArticlePreview), total: Int)
}

pub type ServerModel {
  ServerModel
}

// --- Client ---

pub fn init(_client_context: ClientContext) -> #(Model, Effect(Msg)) {
  #(
    Model(articles: [], tags: [], active_tab: GlobalFeed, page: 1, total: 0),
    effect.none(),
  )
}

pub fn update(
  _client_context: ClientContext,
  model: Model,
  msg: Msg,
) -> #(Model, Effect(Msg)) {
  case msg {
    ClickedTab(tab) -> {
      let #(tab_name, tag) = tab_to_wire(tab)
      #(
        Model(..model, active_tab: tab, page: 1),
        lando_effect.send_to_server(SwitchTab(tab_name:, tag:)),
      )
    }
    ClickedPage(page) -> {
      let #(tab_name, tag) = tab_to_wire(model.active_tab)
      #(
        Model(..model, page:),
        lando_effect.send_to_server(ChangePage(page:, tab_name:, tag:)),
      )
    }
    ClickedTag(tag) -> {
      #(
        Model(..model, active_tab: TagFeed(tag:), page: 1),
        lando_effect.send_to_server(SwitchTab(tab_name: "tag", tag:)),
      )
    }
    GotServerMsg(HomeData(articles:, tags:, total:)) -> #(
      Model(..model, articles:, tags:, total:),
      effect.none(),
    )
    GotServerMsg(ArticleListUpdated(articles:, total:)) -> #(
      Model(..model, articles:, total:),
      effect.none(),
    )
  }
}

fn tab_to_wire(tab: Tab) -> #(String, String) {
  case tab {
    GlobalFeed -> #("global", "")
    YourFeed -> #("feed", "")
    TagFeed(tag:) -> #("tag", tag)
  }
}

// --- View ---

pub fn view(client_context: ClientContext, model: Model) -> Element(Msg) {
  html.div([attr.class("home-page")], [
    banner(),
    html.div([attr.class("container page")], [
      html.div([attr.class("row")], [
        html.div([attr.class("col-md-9")], [
          feed_toggle(client_context, model.active_tab),
          ..list.map(model.articles, article_preview)
        ]),
        html.div([attr.class("col-md-3")], [sidebar(model.tags)]),
      ]),
      pagination(model.page, model.total),
    ]),
  ])
}

fn banner() -> Element(msg) {
  html.div([attr.class("banner")], [
    html.div([attr.class("container")], [
      html.h1([attr.class("logo-font")], [html.text("conduit")]),
      html.p([], [html.text("A place to share your knowledge.")]),
    ]),
  ])
}

fn feed_toggle(
  client_context: ClientContext,
  active_tab: Tab,
) -> Element(Msg) {
  let your_feed_tab = case client_context.current_user {
    Some(_) -> [
      tab_link("Your Feed", YourFeed, active_tab == YourFeed),
    ]
    None -> []
  }
  let tag_tab = case active_tab {
    TagFeed(tag:) -> [
      tab_link("# " <> tag, TagFeed(tag:), True),
    ]
    _ -> []
  }
  html.div([attr.class("feed-toggle")], [
    html.ul(
      [attr.class("nav nav-pills outline-active")],
      list.flatten([
        your_feed_tab,
        [tab_link("Global Feed", GlobalFeed, active_tab == GlobalFeed)],
        tag_tab,
      ]),
    ),
  ])
}

fn tab_link(label: String, tab: Tab, is_active: Bool) -> Element(Msg) {
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
          [
            attr.class("author"),
            attr.href("/profile/" <> article.author_username),
          ],
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

fn sidebar(tags: List(String)) -> Element(Msg) {
  html.div([attr.class("sidebar")], [
    html.p([], [html.text("Popular Tags")]),
    html.div(
      [attr.class("tag-list")],
      list.map(tags, fn(tag) {
        html.a(
          [
            attr.class("tag-pill tag-default"),
            attr.href("#"),
            event.on_click(ClickedTag(tag)),
          ],
          [html.text(tag)],
        )
      }),
    ),
  ])
}

fn pagination(current_page: Int, total: Int) -> Element(Msg) {
  let total_pages = { total + 9 } / 10
  case total_pages > 1 {
    True ->
      html.ul(
        [attr.class("pagination")],
        int.range(from: 1, to: total_pages + 1, with: [], run: fn(acc, p) {
          let item_class = case p == current_page {
            True -> "page-item active"
            False -> "page-item"
          }
          [
            html.li([attr.class(item_class)], [
              html.a(
                [
                  attr.class("page-link"),
                  attr.href("#"),
                  event.on_click(ClickedPage(p)),
                ],
                [html.text(int.to_string(p))],
              ),
            ]),
            ..acc
          ]
        })
          |> list.reverse,
      )
    False -> html.text("")
  }
}

// --- Server ---

pub fn server_init(
  server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  let articles = fetch_global_articles(server_context.db, 10, 0)
  let tags = fetch_popular_tags(server_context.db)
  let total = count_global_articles(server_context.db)
  #(ServerModel, lando_effect.send_to_client(HomeData(articles:, tags:, total:)))
}

pub fn server_update(
  _model: ServerModel,
  msg: ToServer,
  server_context: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  case msg {
    SwitchTab(tab_name:, tag:) -> {
      let #(articles, total) =
        fetch_tab_articles(server_context.db, tab_name, tag, 0)
      #(
        ServerModel,
        lando_effect.send_to_client(ArticleListUpdated(articles:, total:)),
      )
    }
    ChangePage(page:, tab_name:, tag:) -> {
      let offset = { page - 1 } * 10
      let #(articles, total) =
        fetch_tab_articles(server_context.db, tab_name, tag, offset)
      #(
        ServerModel,
        lando_effect.send_to_client(ArticleListUpdated(articles:, total:)),
      )
    }
  }
}

fn fetch_tab_articles(
  db: sqlight.Connection,
  tab_name: String,
  tag: String,
  offset: Int,
) -> #(List(ArticlePreview), Int) {
  case tab_name {
    "feed" -> {
      let session_id = lando_effect.get_ws_session()
      case get_user_id(db, session_id) {
        Ok(user_id) -> #(
          fetch_feed_articles(db, user_id, 10, offset),
          count_feed_articles(db, user_id),
        )
        Error(_) -> #([], 0)
      }
    }
    "tag" -> #(
      fetch_tag_articles(db, tag, 10, offset),
      count_tag_articles(db, tag),
    )
    _ -> #(
      fetch_global_articles(db, 10, offset),
      count_global_articles(db),
    )
  }
}

fn get_user_id(
  db: sqlight.Connection,
  session_id: String,
) -> Result(Int, Nil) {
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

fn fetch_global_articles(
  db: sqlight.Connection,
  limit: Int,
  offset: Int,
) -> List(ArticlePreview) {
  let assert Ok(rows) =
    sqlight.query(
      "SELECT a.slug, a.title, a.description, a.created_at,
              u.username, u.image,
              (SELECT COUNT(*) FROM favorites WHERE article_id = a.id) as fav_count
       FROM articles a JOIN users u ON a.author_id = u.id
       ORDER BY a.created_at DESC LIMIT ? OFFSET ?",
      on: db,
      with: [sqlight.int(limit), sqlight.int(offset)],
      expecting: article_preview_decoder(),
    )
  rows
}

fn fetch_feed_articles(
  db: sqlight.Connection,
  user_id: Int,
  limit: Int,
  offset: Int,
) -> List(ArticlePreview) {
  let assert Ok(rows) =
    sqlight.query(
      "SELECT a.slug, a.title, a.description, a.created_at,
              u.username, u.image,
              (SELECT COUNT(*) FROM favorites WHERE article_id = a.id) as fav_count
       FROM articles a JOIN users u ON a.author_id = u.id
       WHERE a.author_id IN (SELECT followed_id FROM follows WHERE follower_id = ?)
       ORDER BY a.created_at DESC LIMIT ? OFFSET ?",
      on: db,
      with: [sqlight.int(user_id), sqlight.int(limit), sqlight.int(offset)],
      expecting: article_preview_decoder(),
    )
  rows
}

fn fetch_tag_articles(
  db: sqlight.Connection,
  tag: String,
  limit: Int,
  offset: Int,
) -> List(ArticlePreview) {
  let assert Ok(rows) =
    sqlight.query(
      "SELECT a.slug, a.title, a.description, a.created_at,
              u.username, u.image,
              (SELECT COUNT(*) FROM favorites WHERE article_id = a.id) as fav_count
       FROM articles a JOIN users u ON a.author_id = u.id
       JOIN article_tags at ON a.id = at.article_id
       JOIN tags t ON at.tag_id = t.id
       WHERE t.name = ?
       ORDER BY a.created_at DESC LIMIT ? OFFSET ?",
      on: db,
      with: [sqlight.text(tag), sqlight.int(limit), sqlight.int(offset)],
      expecting: article_preview_decoder(),
    )
  rows
}

fn count_global_articles(db: sqlight.Connection) -> Int {
  let assert Ok([count]) =
    sqlight.query(
      "SELECT COUNT(*) as count FROM articles",
      on: db,
      with: [],
      expecting: int_decoder(),
    )
  count
}

fn count_feed_articles(db: sqlight.Connection, user_id: Int) -> Int {
  let assert Ok([count]) =
    sqlight.query(
      "SELECT COUNT(*) as count FROM articles a
       WHERE a.author_id IN (SELECT followed_id FROM follows WHERE follower_id = ?)",
      on: db,
      with: [sqlight.int(user_id)],
      expecting: int_decoder(),
    )
  count
}

fn count_tag_articles(db: sqlight.Connection, tag: String) -> Int {
  let assert Ok([count]) =
    sqlight.query(
      "SELECT COUNT(*) as count FROM articles a
       JOIN article_tags at ON a.id = at.article_id
       JOIN tags t ON at.tag_id = t.id
       WHERE t.name = ?",
      on: db,
      with: [sqlight.text(tag)],
      expecting: int_decoder(),
    )
  count
}

fn fetch_popular_tags(db: sqlight.Connection) -> List(String) {
  let assert Ok(rows) =
    sqlight.query(
      "SELECT t.name FROM tags t
       JOIN article_tags at ON t.id = at.tag_id
       GROUP BY t.id ORDER BY COUNT(*) DESC LIMIT 10",
      on: db,
      with: [],
      expecting: string_decoder(),
    )
  rows
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

fn string_decoder() -> decode.Decoder(String) {
  use val <- decode.field(0, decode.string)
  decode.success(val)
}
