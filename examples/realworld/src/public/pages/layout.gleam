import gleam/option.{None, Some}
import lustre/attribute as attr
import lustre/element.{type Element}
import lustre/element/html
import public/client_context.{type ClientContext, type ClientContextMsg}

pub fn layout(
  client_context: ClientContext,
  _on_context_msg: fn(ClientContextMsg) -> msg,
  content: Element(msg),
) -> Element(msg) {
  html.div([], [
    nav(client_context),
    content,
    footer_view(),
  ])
}

fn nav(client_context: ClientContext) -> Element(msg) {
  html.nav([attr.class("navbar navbar-light")], [
    html.div([attr.class("container")], [
      html.a([attr.class("navbar-brand"), attr.href("/")], [
        html.text("conduit"),
      ]),
      html.ul(
        [attr.class("nav navbar-nav pull-xs-right")],
        case client_context.current_user {
          None -> [
            nav_link("/", "Home"),
            nav_link("/login", "Sign in"),
            nav_link("/register", "Sign up"),
          ]
          Some(user) -> [
            nav_link("/", "Home"),
            nav_link("/editor", "New Article"),
            nav_link("/settings", "Settings"),
            nav_link("/profile/" <> user.username, user.username),
          ]
        },
      ),
    ]),
  ])
}

fn nav_link(href: String, label: String) -> Element(msg) {
  html.li([attr.class("nav-item")], [
    html.a([attr.class("nav-link"), attr.href(href)], [html.text(label)]),
  ])
}

fn footer_view() -> Element(msg) {
  html.footer([], [
    html.div([attr.class("container")], [
      html.a([attr.class("logo-font"), attr.href("/")], [html.text("conduit")]),
      html.span([attr.class("attribution")], [
        html.text("Built with "),
        html.a([attr.href("https://github.com/rally")], [html.text("Rally")]),
      ]),
    ]),
  ])
}
