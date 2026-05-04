import gleam/dynamic/decode
import sqlight

pub fn add(
  db db: sqlight.Connection,
  follower_id follower_id: Int,
  followed_id followed_id: Int,
) -> Result(List(Nil), sqlight.Error) {
  sqlight.query(
    "INSERT INTO follows (follower_id, followed_id) VALUES (:follower_id, :followed_id)",
    on: db,
    with: [sqlight.int(follower_id), sqlight.int(followed_id)],
    expecting: decode.success(Nil),
  )
}

pub type IsFollowingRow {
  IsFollowingRow(count: Int)
}

pub fn is_following(
  db db: sqlight.Connection,
  follower_id follower_id: Int,
  followed_id followed_id: Int,
) -> Result(List(IsFollowingRow), sqlight.Error) {
  sqlight.query(
    "SELECT COUNT(*) as count FROM follows WHERE follower_id = :follower_id AND followed_id = :followed_id",
    on: db,
    with: [sqlight.int(follower_id), sqlight.int(followed_id)],
    expecting: {
      use count <- decode.field(0, decode.int)
      decode.success(IsFollowingRow(count:))
    },
  )
}

pub fn remove(
  db db: sqlight.Connection,
  follower_id follower_id: Int,
  followed_id followed_id: Int,
) -> Result(List(Nil), sqlight.Error) {
  sqlight.query(
    "DELETE FROM follows WHERE follower_id = :follower_id AND followed_id = :followed_id",
    on: db,
    with: [sqlight.int(follower_id), sqlight.int(followed_id)],
    expecting: decode.success(Nil),
  )
}
