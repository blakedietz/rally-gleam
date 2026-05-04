import client_context.{ClientContext}
import generated/sql/likes_sql
import gleam/list
import gleam/string
import gleeunit/should
import lando_runtime/effect as lando_effect
import lando_runtime/migrate
import lando_runtime/topics
import lustre/element
import pages/home_.{Model, ServerModel, SmashLike}
import server_context.{type ServerContext, ServerContext}
import sqlight

fn with_server_ctx(f: fn(ServerContext) -> Nil) -> Nil {
  let assert Ok(db) = sqlight.open(":memory:")
  let assert Ok(_) = migrate.run(conn: db, dir: "migrations")
  let ctx = ServerContext(db:)
  topics.start()
  lando_effect.put_ws_state(Nil, ctx, "Home")
  topics.join("page:Home")
  f(ctx)
}

// -- Client-side tests --

pub fn init_returns_model_test() {
  let ctx = ClientContext(smashed_likes: 0)
  let #(model, _effects) = home_.init(ctx)
  model |> should.equal(Model)
}

pub fn view_renders_like_count_test() {
  let ctx = ClientContext(smashed_likes: 42)
  let html = home_.view(ctx, Model) |> element.to_string()
  html |> string.contains("42") |> should.be_true()
}

pub fn view_renders_zero_test() {
  let ctx = ClientContext(smashed_likes: 0)
  let html = home_.view(ctx, Model) |> element.to_string()
  html |> string.contains("0") |> should.be_true()
}

// -- Server-side tests --

pub fn server_init_returns_current_count_test() {
  use ctx <- with_server_ctx()
  let #(model, _effects) = home_.server_init(ctx)
  model |> should.equal(ServerModel)
  let frames = lando_effect.drain_outgoing_frames()
  list.is_empty(frames) |> should.be_false()
}

pub fn server_init_after_increments_test() {
  use ctx <- with_server_ctx()
  let assert Ok(_) = likes_sql.increment_likes(db: ctx.db)
  let assert Ok(_) = likes_sql.increment_likes(db: ctx.db)
  let #(_model, _effects) = home_.server_init(ctx)
  let frames = lando_effect.drain_outgoing_frames()
  list.is_empty(frames) |> should.be_false()
}

pub fn server_update_smash_like_increments_test() {
  use ctx <- with_server_ctx()
  let #(model, _effects) = home_.server_init(ctx)
  let _ = lando_effect.drain_outgoing_frames()

  let #(new_model, _effects) = home_.server_update(model, SmashLike, ctx)
  new_model |> should.equal(ServerModel)
  let assert Ok([row]) = likes_sql.get_likes(db: ctx.db)
  row.count |> should.equal(1)

  let frames = lando_effect.drain_outgoing_frames()
  list.is_empty(frames) |> should.be_false()
}

pub fn server_update_multiple_smashes_test() {
  use ctx <- with_server_ctx()
  let #(model, _) = home_.server_init(ctx)
  let _ = lando_effect.drain_outgoing_frames()

  let #(m2, _) = home_.server_update(model, SmashLike, ctx)
  let _ = lando_effect.drain_outgoing_frames()
  let #(m3, _) = home_.server_update(m2, SmashLike, ctx)
  let _ = lando_effect.drain_outgoing_frames()
  let #(_m4, _) = home_.server_update(m3, SmashLike, ctx)
  let _ = lando_effect.drain_outgoing_frames()

  let assert Ok([row]) = likes_sql.get_likes(db: ctx.db)
  row.count |> should.equal(3)
}
