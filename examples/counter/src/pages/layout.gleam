import lustre/element.{type Element}

/// A layout wraps page content in shared chrome (header, footer, etc.).
/// The framework automatically applies the nearest layout.gleam to each page.
/// If a page doesn't need a layout, delete its nearest layout.gleam file.
pub fn layout(content: Element(msg)) -> Element(msg) {
  content
  // To add shared chrome, wrap content:
  //   html.div([], [
  //     html.header([], [html.text("My App")]),
  //     content,
  //     html.footer([], [html.text("Powered by Lando")]),
  //   ])
}
