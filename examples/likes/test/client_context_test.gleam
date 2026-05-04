import client_context.{UpdateLikes}
import gleeunit/should

pub fn init_starts_at_zero_test() {
  let #(ctx, _effects) = client_context.init()
  ctx.smashed_likes |> should.equal(0)
}

pub fn update_likes_sets_count_test() {
  let #(ctx, _) = client_context.init()
  let #(updated, _) = client_context.update(ctx, UpdateLikes(42))
  updated.smashed_likes |> should.equal(42)
}

pub fn update_likes_replaces_previous_test() {
  let #(ctx, _) = client_context.init()
  let #(ctx2, _) = client_context.update(ctx, UpdateLikes(10))
  let #(ctx3, _) = client_context.update(ctx2, UpdateLikes(99))
  ctx3.smashed_likes |> should.equal(99)
}
