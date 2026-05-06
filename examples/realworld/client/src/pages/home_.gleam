import rally_runtime/effect as rally_effect

import lustre/event

import lustre/element/html

import lustre/element.{type Element}

import lustre/effect.{type Effect}

import lustre/attribute as attr

import gleam/list

import gleam/int

import client_context.{type ClientContext}

pub type ServerChangePage {
  ServerChangePage(page: Int, tab_name: String, tag: String)
}

pub type ServerSwitchTab {
  ServerSwitchTab(tab_name: String, tag: String)
}

pub type Msg {
  ClickedTab(Tab)
  ClickedPage(Int)
  ClickedTag(String)
  GotArticles(Result(#(List(ArticlePreview), Int), Nil))
}

pub type Tab {
  GlobalFeed
  YourFeed
  TagFeed(tag: String)
}

pub type ArticlePreview {
  ArticlePreview(
    slug: String,
    title: String,
    description: String,
    created_at: Int,
    author_username: String,
    author_image: String,
    favorites_count: Int,
  )
}

pub type Model {
  Model(
    articles: List(ArticlePreview),
    tags: List(String),
    active_tab: Tab,
    page: Int,
    total: Int,
  )
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
        html.span([attr.class("date")], [
          html.text(int.to_string(article.created_at)),
        ]),
      ]),
      html.button([attr.class("btn btn-outline-primary btn-sm pull-xs-right")], [
        html.i([attr.class("ion-heart")], []),
        html.text(" " <> int.to_string(article.favorites_count)),
      ]),
    ]),
    html.a(
      [attr.class("preview-link"), attr.href("/article/" <> article.slug)],
      [
        html.h1([], [html.text(article.title)]),
        html.p([], [html.text(article.description)]),
        html.span([], [html.text("Read more...")]),
      ],
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
      [
        attr.class(active_class),
        attr.href("#"),
        event.on_click(ClickedTab(tab)),
      ],
      [html.text(label)],
    ),
  ])
}

fn feed_toggle(client_context: ClientContext, active_tab: Tab) -> Element(Msg) {
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

fn banner() -> Element(msg) {
  html.div([attr.class("banner")], [
    html.div([attr.class("container")], [
      html.h1([attr.class("logo-font")], [html.text("conduit")]),
      html.p([], [html.text("A place to share your knowledge.")]),
    ]),
  ])
}

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

fn tab_to_wire(tab: Tab) -> #(String, String) {
  case tab {
    GlobalFeed -> #("global", "")
    YourFeed -> #("feed", "")
    TagFeed(tag:) -> #("tag", tag)
  }
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
        rally_effect.rpc(
          ServerSwitchTab(tab_name:, tag:),
          on_response: GotArticles,
        ),
      )
    }
    ClickedPage(page) -> {
      let #(tab_name, tag) = tab_to_wire(model.active_tab)
      #(
        Model(..model, page:),
        rally_effect.rpc(
          ServerChangePage(page:, tab_name:, tag:),
          on_response: GotArticles,
        ),
      )
    }
    ClickedTag(tag) -> {
      #(
        Model(..model, active_tab: TagFeed(tag:), page: 1),
        rally_effect.rpc(
          ServerSwitchTab(tab_name: "tag", tag:),
          on_response: GotArticles,
        ),
      )
    }
    GotArticles(Ok(#(articles, total))) -> #(
      Model(..model, articles:, total:),
      effect.none(),
    )
    GotArticles(Error(_)) -> #(model, effect.none())
  }
}

pub fn init(_client_context: ClientContext) -> #(Model, Effect(Msg)) {
  #(
    Model(articles: [], tags: [], active_tab: GlobalFeed, page: 1, total: 0),
    effect.none(),
  )
}
