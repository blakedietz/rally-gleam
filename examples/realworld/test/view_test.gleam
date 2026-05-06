import birdie
import client_context.{type ClientContext, ClientContext, User}
import gleam/option.{None, Some}
import lustre/element
import pages/article/slug_ as article_page
import pages/editor
import pages/home_
import pages/login
import pages/profile/username_ as profile_page
import pages/register
import pages/settings

fn logged_out_ctx() -> ClientContext {
  ClientContext(current_user: None)
}

fn logged_in_ctx() -> ClientContext {
  ClientContext(
    current_user: Some(User(
      username: "jake",
      image: "https://i.imgur.com/test.jpg",
    )),
  )
}

pub fn home_logged_out_view_test() {
  let model =
    home_.Model(
      articles: [],
      tags: [],
      active_tab: home_.GlobalFeed,
      page: 1,
      total: 0,
    )
  home_.view(logged_out_ctx(), model)
  |> element.to_string
  |> birdie.snap("home_logged_out_view")
}

pub fn home_with_articles_view_test() {
  let model =
    home_.Model(
      articles: [
        home_.ArticlePreview(
          slug: "how-to-train-your-dragon",
          title: "How to train your dragon",
          description: "Ever wonder how?",
          created_at: 1_714_800_000,
          author_username: "jake",
          author_image: "https://i.imgur.com/test.jpg",
          favorites_count: 29,
        ),
      ],
      tags: ["dragons", "training", "gleam"],
      active_tab: home_.GlobalFeed,
      page: 1,
      total: 10,
    )
  home_.view(logged_in_ctx(), model)
  |> element.to_string
  |> birdie.snap("home_with_articles_view")
}

pub fn login_empty_view_test() {
  let model = login.Model(email: "", password: "", errors: [])
  login.view(logged_out_ctx(), model)
  |> element.to_string
  |> birdie.snap("login_empty_view")
}

pub fn register_empty_view_test() {
  let model = register.Model(username: "", email: "", password: "", errors: [])
  register.view(logged_out_ctx(), model)
  |> element.to_string
  |> birdie.snap("register_empty_view")
}

pub fn editor_empty_view_test() {
  let model =
    editor.Model(
      title: "",
      description: "",
      body: "",
      tag_input: "",
      tags: [],
      errors: [],
    )
  editor.view(logged_in_ctx(), model)
  |> element.to_string
  |> birdie.snap("editor_empty_view")
}

pub fn article_loaded_view_test() {
  let model =
    article_page.Model(
      article: Some(article_page.Article(
        id: 1,
        slug: "how-to-train-your-dragon",
        title: "How to train your dragon",
        description: "Ever wonder how?",
        body: "It takes a Gleam programmer...",
        created_at: 1_714_800_000,
        tags: ["dragons", "training"],
        author_username: "jake",
        author_image: "https://i.imgur.com/test.jpg",
        author_bio: "I work at a thing",
      )),
      comments: [
        article_page.Comment(
          id: 1,
          body: "Great article!",
          created_at: 1_714_800_100,
          username: "jane",
          image: "https://i.imgur.com/jane.jpg",
        ),
      ],
      is_favorited: False,
      is_following: False,
      favorites_count: 5,
      comment_body: "",
      errors: [],
    )
  article_page.view(logged_in_ctx(), model)
  |> element.to_string
  |> birdie.snap("article_loaded_view")
}

pub fn profile_loaded_view_test() {
  let model =
    profile_page.Model(
      profile: Some(profile_page.Profile(
        username: "jake",
        bio: "I work at a thing",
        image: "https://i.imgur.com/test.jpg",
      )),
      articles: [
        profile_page.ArticlePreview(
          slug: "how-to-train-your-dragon",
          title: "How to train your dragon",
          description: "Ever wonder how?",
          created_at: 1_714_800_000,
          author_username: "jake",
          author_image: "https://i.imgur.com/test.jpg",
          favorites_count: 29,
        ),
      ],
      active_tab: profile_page.MyArticles,
      is_following: False,
    )
  profile_page.view(logged_in_ctx(), model)
  |> element.to_string
  |> birdie.snap("profile_loaded_view")
}

pub fn settings_view_test() {
  let model =
    settings.Model(
      username: "jake",
      email: "jake@jake.jake",
      bio: "I work at a thing",
      image: "https://i.imgur.com/test.jpg",
      password: "",
      errors: [],
    )
  settings.view(logged_in_ctx(), model)
  |> element.to_string
  |> birdie.snap("settings_view")
}
