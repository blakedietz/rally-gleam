import gleam/dynamic/decode
import sqlight

pub fn create_or_ignore(
  db db: sqlight.Connection,
  name name: String,
) -> Result(List(Nil), sqlight.Error) {
  sqlight.query(
    "INSERT OR IGNORE INTO tags (name) VALUES (:name)",
    on: db,
    with: [sqlight.text(name)],
    expecting: decode.success(Nil),
  )
}

pub type GetIdByNameRow {
  GetIdByNameRow(id: Int)
}

pub fn get_id_by_name(
  db db: sqlight.Connection,
  name name: String,
) -> Result(List(GetIdByNameRow), sqlight.Error) {
  sqlight.query(
    "SELECT id FROM tags WHERE name = :name",
    on: db,
    with: [sqlight.text(name)],
    expecting: {
      use id <- decode.field(0, decode.int)
      decode.success(GetIdByNameRow(id:))
    },
  )
}

pub fn link_to_article(
  db db: sqlight.Connection,
  article_id article_id: Int,
  tag_id tag_id: Int,
) -> Result(List(Nil), sqlight.Error) {
  sqlight.query(
    "INSERT OR IGNORE INTO article_tags (article_id, tag_id) VALUES (:article_id, :tag_id)",
    on: db,
    with: [sqlight.int(article_id), sqlight.int(tag_id)],
    expecting: decode.success(Nil),
  )
}

pub type ListByArticleRow {
  ListByArticleRow(name: String)
}

pub fn list_by_article(
  db db: sqlight.Connection,
  article_id article_id: Int,
) -> Result(List(ListByArticleRow), sqlight.Error) {
  sqlight.query(
    "SELECT t.name FROM tags t JOIN article_tags at ON t.id = at.tag_id WHERE at.article_id = :article_id",
    on: db,
    with: [sqlight.int(article_id)],
    expecting: {
      use name <- decode.field(0, decode.string)
      decode.success(ListByArticleRow(name:))
    },
  )
}

pub type ListPopularRow {
  ListPopularRow(name: String)
}

pub fn list_popular(
  db db: sqlight.Connection,
) -> Result(List(ListPopularRow), sqlight.Error) {
  sqlight.query(
    "SELECT t.name FROM tags t JOIN article_tags at ON t.id = at.tag_id GROUP BY t.id ORDER BY COUNT(*) DESC LIMIT 10",
    on: db,
    with: [],
    expecting: {
      use name <- decode.field(0, decode.string)
      decode.success(ListPopularRow(name:))
    },
  )
}

pub fn unlink_from_article(
  db db: sqlight.Connection,
  article_id article_id: Int,
) -> Result(List(Nil), sqlight.Error) {
  sqlight.query(
    "DELETE FROM article_tags WHERE article_id = :article_id",
    on: db,
    with: [sqlight.int(article_id)],
    expecting: decode.success(Nil),
  )
}
