import gleam/dynamic/decode
import sqlight

pub type GetByUsernameRow {
  GetByUsernameRow(id: Int, username: String, bio: String, image: String)
}

pub fn get_by_username(
  db db: sqlight.Connection,
  username username: String,
) -> Result(List(GetByUsernameRow), sqlight.Error) {
  sqlight.query(
    "SELECT id, username, bio, image FROM users WHERE username = :username",
    on: db,
    with: [sqlight.text(username)],
    expecting: {
      use id <- decode.field(0, decode.int)
      use username <- decode.field(1, decode.string)
      use bio <- decode.field(2, decode.string)
      use image <- decode.field(3, decode.string)
      decode.success(GetByUsernameRow(id:, username:, bio:, image:))
    },
  )
}

pub type GetIdByUsernameRow {
  GetIdByUsernameRow(id: Int)
}

pub fn get_id_by_username(
  db db: sqlight.Connection,
  username username: String,
) -> Result(List(GetIdByUsernameRow), sqlight.Error) {
  sqlight.query(
    "SELECT id FROM users WHERE username = :username",
    on: db,
    with: [sqlight.text(username)],
    expecting: {
      use id <- decode.field(0, decode.int)
      decode.success(GetIdByUsernameRow(id:))
    },
  )
}

pub type GetInfoRow {
  GetInfoRow(username: String, image: String)
}

pub fn get_info(
  db db: sqlight.Connection,
  user_id user_id: Int,
) -> Result(List(GetInfoRow), sqlight.Error) {
  sqlight.query(
    "SELECT username, image FROM users WHERE id = :user_id",
    on: db,
    with: [sqlight.int(user_id)],
    expecting: {
      use username <- decode.field(0, decode.string)
      use image <- decode.field(1, decode.string)
      decode.success(GetInfoRow(username:, image:))
    },
  )
}
