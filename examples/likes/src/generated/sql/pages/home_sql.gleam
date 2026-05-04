import gleam/dynamic/decode
import sqlight

pub type GetLikesRow {
  GetLikesRow(count: Int)
}

pub fn get_likes(
  db db: sqlight.Connection,
) -> Result(List(GetLikesRow), sqlight.Error) {
  sqlight.query(
    "SELECT count FROM likes WHERE id = 1",
    on: db,
    with: [],
    expecting: {
      use count <- decode.field(0, decode.int)
      decode.success(GetLikesRow(count:))
    },
  )
}

pub fn increment_likes(
  db db: sqlight.Connection,
) -> Result(List(Nil), sqlight.Error) {
  sqlight.query(
    "UPDATE likes SET count = count + 1 WHERE id = 1",
    on: db,
    with: [],
    expecting: decode.success(Nil),
  )
}
