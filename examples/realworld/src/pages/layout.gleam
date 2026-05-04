import lustre/attribute as attr
import lustre/element.{type Element}
import lustre/element/html

pub fn layout(content: Element(msg)) -> Element(msg) {
  html.div([], [
    content,
    footer_view(),
  ])
}

fn footer_view() -> Element(msg) {
  html.footer([], [
    html.div([attr.class("container")], [
      html.a([attr.class("logo-font"), attr.href("/")], [
        html.text("conduit"),
      ]),
      html.span([attr.class("attribution")], [
        html.text("Built with "),
        html.a([attr.href("https://github.com/lando")], [
          html.text("Lando"),
        ]),
      ]),
    ]),
  ])
}
