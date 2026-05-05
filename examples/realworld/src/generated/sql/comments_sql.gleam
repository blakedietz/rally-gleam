import gleam/dynamic/decode
import sqlight

pub type CreateRow {
  CreateRow(id: Int)
}

pub fn create(
  db db: sqlight.Connection,
  body body: String,
  article_id article_id: Int,
  author_id author_id: Int,
  created_at created_at: Int,
) -> Result(List(CreateRow), sqlight.Error) {
  sqlight.query(
    "INSERT INTO comments (body, article_id, author_id, created_at) VALUES (:body, :article_id, :author_id, :now) RETURNING id",
    on: db,
    with: [
      sqlight.text(body),
      sqlight.int(article_id),
      sqlight.int(author_id),
      sqlight.int(created_at),
    ],
    expecting: {
      use id <- decode.field(0, decode.int)
      decode.success(CreateRow(id:))
    },
  )
}

pub type DeleteOwnRow {
  DeleteOwnRow(id: Int)
}

pub fn delete_own(
  db db: sqlight.Connection,
  id id: Int,
  author_id author_id: Int,
) -> Result(List(DeleteOwnRow), sqlight.Error) {
  sqlight.query(
    "DELETE FROM comments WHERE id = :id AND author_id = :author_id RETURNING id",
    on: db,
    with: [sqlight.int(id), sqlight.int(author_id)],
    expecting: {
      use id <- decode.field(0, decode.int)
      decode.success(DeleteOwnRow(id:))
    },
  )
}

pub type ListByArticleRow {
  ListByArticleRow(
    id: Int,
    body: String,
    created_at: Int,
    username: String,
    image: String,
  )
}

pub fn list_by_article(
  db db: sqlight.Connection,
  article_id article_id: Int,
) -> Result(List(ListByArticleRow), sqlight.Error) {
  sqlight.query(
    "SELECT c.id, c.body, c.created_at, u.username, u.image FROM comments c JOIN users u ON c.author_id = u.id WHERE c.article_id = :article_id ORDER BY c.created_at ASC",
    on: db,
    with: [sqlight.int(article_id)],
    expecting: {
      use id <- decode.field(0, decode.int)
      use body <- decode.field(1, decode.string)
      use created_at <- decode.field(2, decode.int)
      use username <- decode.field(3, decode.string)
      use image <- decode.field(4, decode.string)
      decode.success(ListByArticleRow(
        id:,
        body:,
        created_at:,
        username:,
        image:,
      ))
    },
  )
}
