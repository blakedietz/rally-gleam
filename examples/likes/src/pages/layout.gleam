import client_context.{type ClientContext}
import lustre/attribute as attr
import lustre/element.{type Element}
import lustre/element/html

pub fn layout(_client_context: ClientContext, content: Element(msg)) -> Element(msg) {
  html.div(
    [
      attr.styles([
        #("min-height", "100vh"),
        #("display", "flex"),
        #("flex-direction", "column"),
        #("align-items", "center"),
        #("justify-content", "center"),
        #("background", "linear-gradient(135deg, #667eea 0%, #764ba2 100%)"),
        #("color", "white"),
        #("font-family", "system-ui, sans-serif"),
      ]),
    ],
    [content],
  )
}
