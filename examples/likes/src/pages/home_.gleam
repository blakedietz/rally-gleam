import gleam/dynamic
import gleam/int
import client_context.{type ClientContext, UpdateLikes}
import lando_runtime/effect as lando_effect
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import server_context.{type ServerContext}
import sqlight

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
      attr.style([#("text-align", "center")]),
    ],
    [
      html.h1(
        [
          attr.style([
            #("font-size", "2.5rem"),
            #("margin-bottom", "1rem"),
          ]),
        ],
        [html.text("Lando Likes")],
      ),
      html.p(
        [
          attr.style([
            #("opacity", "0.8"),
            #("margin-bottom", "2rem"),
          ]),
        ],
        [html.text("Real-time likes, broadcast to everyone")],
      ),
      html.button(
        [
          event.on_click(SmashedLikeButton),
          attr.style([
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
  ensure_table(ctx.db)
  let count = get_likes(ctx.db)
  #(ServerModel, lando_effect.send_to_client(NewSmashedLikes(count)))
}

pub fn server_update(
  _model: ServerModel,
  msg: ToServer,
  ctx: ServerContext,
) -> #(ServerModel, Effect(ToClient)) {
  case msg {
    SmashLike -> {
      let count = increment_likes(ctx.db)
      #(ServerModel, lando_effect.broadcast_to_page(NewSmashedLikes(count)))
    }
  }
}

fn ensure_table(db: sqlight.Connection) -> Nil {
  let assert Ok(_) =
    sqlight.exec(
      "CREATE TABLE IF NOT EXISTS likes (id INTEGER PRIMARY KEY, count INTEGER DEFAULT 0);
     INSERT OR IGNORE INTO likes (id, count) VALUES (1, 0);",
      db,
    )
  Nil
}

fn get_likes(db: sqlight.Connection) -> Int {
  case
    sqlight.query(
      "SELECT count FROM likes WHERE id = 1",
      db,
      [],
      fn(row) {
        let assert Ok(count) = dynamic.element(0, dynamic.int)(row)
        count
      },
    )
  {
    Ok([count]) -> count
    _ -> 0
  }
}

fn increment_likes(db: sqlight.Connection) -> Int {
  let assert Ok(_) =
    sqlight.exec(
      "UPDATE likes SET count = count + 1 WHERE id = 1",
      db,
    )
  get_likes(db)
}
