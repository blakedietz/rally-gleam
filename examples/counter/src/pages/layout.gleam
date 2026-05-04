//// Layout — wraps every page with shared chrome.
//// Equivalent to Lamdera's Shared module.
//// The framework applies the nearest layout.gleam to each page.

import lustre/element.{type Element}
import lustre/element/html
import lustre/attribute

/// Wrap page content in a shared header and footer.
/// `content` is the page's rendered view.
pub fn layout(content: Element(msg)) -> Element(msg) {
  html.div([attribute.class("app")], [
    html.header([attribute.class("header")], [
      html.nav([], [
        html.a([attribute.href("/")], [html.text("Home")]),
        html.text(" | "),
        html.a([attribute.href("/about")], [html.text("About")]),
      ]),
    ]),
    html.main_([attribute.class("content")], [content]),
    html.footer([attribute.class("footer")], [
      html.text("Powered by Lando"),
    ]),
  ])
}
