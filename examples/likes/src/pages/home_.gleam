import gleam/int
import client_context.{type ClientContext, UpdateLikes}
import generated/sql/home_sql
import lando_runtime/effect as lando_effect
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import server_context.{type ServerContext}

pub type Model {
  Model
}

pub type Msg {
  SmashedLikeButton
  GotServerMsg(ToClient)
}

pub type ToServer {
  SmashLike
}

pub type ToClient {
  NewSmashedLikes(count: Int)
}

pub type ServerModel {
  ServerModel
}

pub fn init(_ctx: ClientContext) -> #(Model, Effect(Msg)) {
  #(Model, effect.none())
}

pub fn update(
  _ctx: ClientContext,
  model: Model,
  msg: Msg,
) -> #(Model, Effect(Msg)) {
  case msg {
    SmashedLikeButton -> #(model, lando_effect.send_to_server(SmashLike))
    GotServerMsg(NewSmashedLikes(count)) -> #(
      model,
      lando_effect.send_to_client_context(UpdateLikes(count)),
    )
  }
}

pub fn view(ctx: ClientContext, _model: Model) -> Element(Msg) {
  html.div(
    [
      attr.styles([#("text-align", "center")]),
    ],
    [
      html.h1(
        [
          attr.styles([
            #("font-size", "2.5rem"),
            #("margin-bottom", "1rem"),
          ]),
        ],
        [html.text("Lando Likes")],
      ),
      html.p(
        [
          attr.styles([
            #("opacity", "0.8"),
            #("margin-bottom", "2rem"),
          ]),
        ],
        [html.text("Real-time likes, broadcast to everyone")],
      ),
      html.button(
        [
          event.on_click(SmashedLikeButton),
          attr.styles([
            #("font-size", "1.5rem"),
            #("padding", "0.75rem 2rem"),
            #("border-radius", "0.5rem"),
            #("border", "none"),
            #("background", "rgba(255,255,255,0.2)"),
            #("color", "white"),
            #("cursor", "pointer"),
          ]),
        ],
        [html.text("\u{1F44D} " <> int.to_string(ctx.smashed_likes))],
      ),
    ],
  )
}

pub fn server_init(ctx: ServerContext) -> #(ServerModel, Effect(ToClient)) {
  let assert Ok([row]) = home_sql.get_likes(db: ctx.db)
  #(ServerModel, lando_effect.send_to_client(NewSmashedLikes(row.count)))
}

pub fn server_update(
  _model: ServerModel,
  msg: ToServer,
  ctx: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  case msg {
    SmashLike -> {
      let assert Ok(_) = home_sql.increment_likes(db: ctx.db)
      let assert Ok([row]) = home_sql.get_likes(db: ctx.db)
      #(ServerModel, lando_effect.broadcast_to_page(NewSmashedLikes(row.count)))
    }
  }
}

