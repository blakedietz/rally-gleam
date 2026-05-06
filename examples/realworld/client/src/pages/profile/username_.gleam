import rally_runtime/effect as rally_effect

import lustre/event

import lustre/element/html

import lustre/element.{type Element}

import lustre/effect.{type Effect}

import lustre/attribute as attr

import gleam/option.{type Option, None, Some}

import gleam/list

import gleam/int

import client_context.{type ClientContext}

pub type ServerModel {
  ServerModel(profile_user_id: Int)
  ServerModelEmpty
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

pub type ToServer {
  ToggleFollow
  SwitchTab(tab_name: String)
}

pub type Msg {
  ClickedFollow
  ClickedTab(ProfileTab)
  GotServerMsg(ToClient)
}

pub type ProfileTab {
  MyArticles
  FavoritedArticles
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

pub type Profile {
  Profile(username: String, bio: String, image: String)
}

pub type Model {
  Model(
    profile: Option(Profile),
    articles: List(ArticlePreview),
    active_tab: ProfileTab,
    is_following: Bool,
  )
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

fn tab_link(label: String, tab: ProfileTab, is_active: Bool) -> Element(Msg) {
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

fn articles_toggle(active_tab: ProfileTab) -> Element(Msg) {
  html.div([attr.class("articles-toggle")], [
    html.ul([attr.class("nav nav-pills outline-active")], [
      tab_link("My Articles", MyArticles, active_tab == MyArticles),
      tab_link(
        "Favorited Articles",
        FavoritedArticles,
        active_tab == FavoritedArticles,
      ),
    ]),
  ])
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

pub fn update(
  _client_context: ClientContext,
  model: Model,
  msg: Msg,
) -> #(Model, Effect(Msg)) {
  case msg {
    ClickedFollow -> #(model, send_to_server(ToggleFollow))
    ClickedTab(tab) -> {
      let tab_name = case tab {
        MyArticles -> "my_articles"
        FavoritedArticles -> "favorited"
      }
      #(Model(..model, active_tab: tab), send_to_server(SwitchTab(tab_name:)))
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

pub fn init(
  _client_context: ClientContext,
  _username: String,
) -> #(Model, Effect(Msg)) {
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

import generated/transport

fn send_to_server(msg: a) -> effect.Effect(b) {
  effect.from(fn(_dispatch) {
    transport.send_to_server("ProfileUsername", msg)
    Nil
  })
}
