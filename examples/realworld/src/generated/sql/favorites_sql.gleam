import gleam/dynamic/decode
import sqlight

pub fn add(
  db db: sqlight.Connection,
  user_id user_id: Int,
  article_id article_id: Int,
) -> Result(List(Nil), sqlight.Error) {
  sqlight.query(
    "INSERT OR IGNORE INTO favorites (user_id, article_id) VALUES (:user_id, :article_id)",
    on: db,
    with: [sqlight.int(user_id), sqlight.int(article_id)],
    expecting: decode.success(Nil),
  )
}

pub type CountForArticleRow {
  CountForArticleRow(count: Int)
}

pub fn count_for_article(
  db db: sqlight.Connection,
  article_id article_id: Int,
) -> Result(List(CountForArticleRow), sqlight.Error) {
  sqlight.query(
    "SELECT COUNT(*) as count FROM favorites WHERE article_id = :article_id",
    on: db,
    with: [sqlight.int(article_id)],
    expecting: {
      use count <- decode.field(0, decode.int)
      decode.success(CountForArticleRow(count:))
    },
  )
}

pub type IsFavoritedRow {
  IsFavoritedRow(count: Int)
}

pub fn is_favorited(
  db db: sqlight.Connection,
  user_id user_id: Int,
  article_id article_id: Int,
) -> Result(List(IsFavoritedRow), sqlight.Error) {
  sqlight.query(
    "SELECT COUNT(*) as count FROM favorites WHERE user_id = :user_id AND article_id = :article_id",
    on: db,
    with: [sqlight.int(user_id), sqlight.int(article_id)],
    expecting: {
      use count <- decode.field(0, decode.int)
      decode.success(IsFavoritedRow(count:))
    },
  )
}

pub fn remove(
  db db: sqlight.Connection,
  user_id user_id: Int,
  article_id article_id: Int,
) -> Result(List(Nil), sqlight.Error) {
  sqlight.query(
    "DELETE FROM favorites WHERE user_id = :user_id AND article_id = :article_id",
    on: db,
    with: [sqlight.int(user_id), sqlight.int(article_id)],
    expecting: decode.success(Nil),
  )
}
