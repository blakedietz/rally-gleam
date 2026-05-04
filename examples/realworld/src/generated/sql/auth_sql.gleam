import gleam/dynamic/decode
import gleam/option.{type Option}
import sqlight

pub fn create_session(
  db db: sqlight.Connection,
  session_id session_id: Option(String),
  user_id user_id: Int,
  created_at created_at: Int,
) -> Result(List(Nil), sqlight.Error) {
  sqlight.query(
    "INSERT OR REPLACE INTO sessions (session_id, user_id, created_at) VALUES (:session_id, :user_id, :now)",
    on: db,
    with: [
      sqlight.nullable(sqlight.text, session_id),
      sqlight.int(user_id),
      sqlight.int(created_at),
    ],
    expecting: decode.success(Nil),
  )
}

pub fn delete_session(
  db db: sqlight.Connection,
  session_id session_id: Option(String),
) -> Result(List(Nil), sqlight.Error) {
  sqlight.query(
    "DELETE FROM sessions WHERE session_id = :session_id",
    on: db,
    with: [sqlight.nullable(sqlight.text, session_id)],
    expecting: decode.success(Nil),
  )
}

pub type FindUserByEmailRow {
  FindUserByEmailRow(
    id: Int,
    username: String,
    email: String,
    password_hash: String,
    bio: String,
    image: String,
  )
}

pub fn find_user_by_email(
  db db: sqlight.Connection,
  email email: String,
) -> Result(List(FindUserByEmailRow), sqlight.Error) {
  sqlight.query(
    "SELECT id, username, email, password_hash, bio, image FROM users WHERE email = :email",
    on: db,
    with: [sqlight.text(email)],
    expecting: {
      use id <- decode.field(0, decode.int)
      use username <- decode.field(1, decode.string)
      use email <- decode.field(2, decode.string)
      use password_hash <- decode.field(3, decode.string)
      use bio <- decode.field(4, decode.string)
      use image <- decode.field(5, decode.string)
      decode.success(FindUserByEmailRow(
        id:,
        username:,
        email:,
        password_hash:,
        bio:,
        image:,
      ))
    },
  )
}

pub type FindUserBySessionRow {
  FindUserBySessionRow(
    id: Int,
    username: String,
    email: String,
    bio: String,
    image: String,
  )
}

pub fn find_user_by_session(
  db db: sqlight.Connection,
  session_id session_id: Option(String),
) -> Result(List(FindUserBySessionRow), sqlight.Error) {
  sqlight.query(
    "SELECT u.id, u.username, u.email, u.bio, u.image FROM users u JOIN sessions s ON u.id = s.user_id WHERE s.session_id = :session_id",
    on: db,
    with: [sqlight.nullable(sqlight.text, session_id)],
    expecting: {
      use id <- decode.field(0, decode.int)
      use username <- decode.field(1, decode.string)
      use email <- decode.field(2, decode.string)
      use bio <- decode.field(3, decode.string)
      use image <- decode.field(4, decode.string)
      decode.success(FindUserBySessionRow(id:, username:, email:, bio:, image:))
    },
  )
}

pub type GetUserSettingsRow {
  GetUserSettingsRow(
    image: String,
    username: String,
    bio: String,
    email: String,
  )
}

pub fn get_user_settings(
  db db: sqlight.Connection,
  user_id user_id: Int,
) -> Result(List(GetUserSettingsRow), sqlight.Error) {
  sqlight.query(
    "SELECT image, username, bio, email FROM users WHERE id = :user_id",
    on: db,
    with: [sqlight.int(user_id)],
    expecting: {
      use image <- decode.field(0, decode.string)
      use username <- decode.field(1, decode.string)
      use bio <- decode.field(2, decode.string)
      use email <- decode.field(3, decode.string)
      decode.success(GetUserSettingsRow(image:, username:, bio:, email:))
    },
  )
}

pub type RegisterUserRow {
  RegisterUserRow(
    id: Int,
    username: String,
    email: String,
    bio: String,
    image: String,
  )
}

pub fn register_user(
  db db: sqlight.Connection,
  username username: String,
  email email: String,
  password_hash password_hash: String,
  bio bio: String,
  image image: String,
  created_at created_at: Int,
  updated_at updated_at: Int,
) -> Result(List(RegisterUserRow), sqlight.Error) {
  sqlight.query(
    "INSERT INTO users (username, email, password_hash, bio, image, created_at, updated_at) VALUES (:username, :email, :password_hash, :bio, :image, :created_at, :updated_at) RETURNING id, username, email, bio, image",
    on: db,
    with: [
      sqlight.text(username),
      sqlight.text(email),
      sqlight.text(password_hash),
      sqlight.text(bio),
      sqlight.text(image),
      sqlight.int(created_at),
      sqlight.int(updated_at),
    ],
    expecting: {
      use id <- decode.field(0, decode.int)
      use username <- decode.field(1, decode.string)
      use email <- decode.field(2, decode.string)
      use bio <- decode.field(3, decode.string)
      use image <- decode.field(4, decode.string)
      decode.success(RegisterUserRow(id:, username:, email:, bio:, image:))
    },
  )
}

pub fn update_user(
  db db: sqlight.Connection,
  image image: String,
  username username: String,
  bio bio: String,
  email email: String,
  now now: Int,
  user_id user_id: Int,
) -> Result(List(Nil), sqlight.Error) {
  sqlight.query(
    "UPDATE users SET image = :image, username = :username, bio = :bio, email = :email, updated_at = :now WHERE id = :user_id",
    on: db,
    with: [
      sqlight.text(image),
      sqlight.text(username),
      sqlight.text(bio),
      sqlight.text(email),
      sqlight.int(now),
      sqlight.int(user_id),
    ],
    expecting: decode.success(Nil),
  )
}

pub fn update_user_with_password(
  db db: sqlight.Connection,
  image image: String,
  username username: String,
  bio bio: String,
  email email: String,
  password_hash password_hash: String,
  now now: Int,
  user_id user_id: Int,
) -> Result(List(Nil), sqlight.Error) {
  sqlight.query(
    "UPDATE users SET image = :image, username = :username, bio = :bio, email = :email, password_hash = :password_hash, updated_at = :now WHERE id = :user_id",
    on: db,
    with: [
      sqlight.text(image),
      sqlight.text(username),
      sqlight.text(bio),
      sqlight.text(email),
      sqlight.text(password_hash),
      sqlight.int(now),
      sqlight.int(user_id),
    ],
    expecting: decode.success(Nil),
  )
}
