import gleam/dynamic/decode
import gleam/option.{type Option}
import sqlight

pub type CountByTagRow {
  CountByTagRow(count: Int)
}

pub fn count_by_tag(
  db db: sqlight.Connection,
  tag tag: String,
) -> Result(List(CountByTagRow), sqlight.Error) {
  sqlight.query(
    "SELECT COUNT(*) as count FROM articles a JOIN article_tags at ON a.id = at.article_id JOIN tags t ON at.tag_id = t.id WHERE t.name = :tag",
    on: db,
    with: [sqlight.text(tag)],
    expecting: {
      use count <- decode.field(0, decode.int)
      decode.success(CountByTagRow(count:))
    },
  )
}

pub type CountFeedRow {
  CountFeedRow(count: Int)
}

pub fn count_feed(
  db db: sqlight.Connection,
  user_id user_id: Int,
) -> Result(List(CountFeedRow), sqlight.Error) {
  sqlight.query(
    "SELECT COUNT(*) as count FROM articles a WHERE a.author_id IN (SELECT followed_id FROM follows WHERE follower_id = :user_id)",
    on: db,
    with: [sqlight.int(user_id)],
    expecting: {
      use count <- decode.field(0, decode.int)
      decode.success(CountFeedRow(count:))
    },
  )
}

pub type CountGlobalRow {
  CountGlobalRow(count: Int)
}

pub fn count_global(
  db db: sqlight.Connection,
) -> Result(List(CountGlobalRow), sqlight.Error) {
  sqlight.query(
    "SELECT COUNT(*) as count FROM articles",
    on: db,
    with: [],
    expecting: {
      use count <- decode.field(0, decode.int)
      decode.success(CountGlobalRow(count:))
    },
  )
}

pub type CreateRow {
  CreateRow(id: Int, slug: String)
}

pub fn create(
  db db: sqlight.Connection,
  slug slug: String,
  title title: String,
  description description: String,
  body body: String,
  author_id author_id: Int,
  created_at created_at: Int,
  updated_at updated_at: Int,
) -> Result(List(CreateRow), sqlight.Error) {
  sqlight.query(
    "INSERT INTO articles (slug, title, description, body, author_id, created_at, updated_at) VALUES (:slug, :title, :description, :body, :author_id, :created_at, :updated_at) RETURNING id, slug",
    on: db,
    with: [
      sqlight.text(slug),
      sqlight.text(title),
      sqlight.text(description),
      sqlight.text(body),
      sqlight.int(author_id),
      sqlight.int(created_at),
      sqlight.int(updated_at),
    ],
    expecting: {
      use id <- decode.field(0, decode.int)
      use slug <- decode.field(1, decode.string)
      decode.success(CreateRow(id:, slug:))
    },
  )
}

pub fn delete(
  db db: sqlight.Connection,
  article_id article_id: Int,
) -> Result(List(Nil), sqlight.Error) {
  sqlight.query(
    "DELETE FROM articles WHERE id = :article_id",
    on: db,
    with: [sqlight.int(article_id)],
    expecting: decode.success(Nil),
  )
}

pub type GetBySlugRow {
  GetBySlugRow(
    id: Int,
    slug: String,
    title: String,
    description: String,
    body: String,
    created_at: Int,
    author_id: Int,
    username: String,
    image: String,
    bio: String,
  )
}

pub fn get_by_slug(
  db db: sqlight.Connection,
  slug slug: String,
) -> Result(List(GetBySlugRow), sqlight.Error) {
  sqlight.query(
    "SELECT a.id, a.slug, a.title, a.description, a.body, a.created_at, a.author_id, u.username, u.image, u.bio FROM articles a JOIN users u ON a.author_id = u.id WHERE a.slug = :slug",
    on: db,
    with: [sqlight.text(slug)],
    expecting: {
      use id <- decode.field(0, decode.int)
      use slug <- decode.field(1, decode.string)
      use title <- decode.field(2, decode.string)
      use description <- decode.field(3, decode.string)
      use body <- decode.field(4, decode.string)
      use created_at <- decode.field(5, decode.int)
      use author_id <- decode.field(6, decode.int)
      use username <- decode.field(7, decode.string)
      use image <- decode.field(8, decode.string)
      use bio <- decode.field(9, decode.string)
      decode.success(GetBySlugRow(
        id:,
        slug:,
        title:,
        description:,
        body:,
        created_at:,
        author_id:,
        username:,
        image:,
        bio:,
      ))
    },
  )
}

pub type GetForEditRow {
  GetForEditRow(
    id: Int,
    title: String,
    description: String,
    body: String,
    author_id: Int,
  )
}

pub fn get_for_edit(
  db db: sqlight.Connection,
  slug slug: String,
) -> Result(List(GetForEditRow), sqlight.Error) {
  sqlight.query(
    "SELECT id, title, description, body, author_id FROM articles WHERE slug = :slug",
    on: db,
    with: [sqlight.text(slug)],
    expecting: {
      use id <- decode.field(0, decode.int)
      use title <- decode.field(1, decode.string)
      use description <- decode.field(2, decode.string)
      use body <- decode.field(3, decode.string)
      use author_id <- decode.field(4, decode.int)
      decode.success(GetForEditRow(id:, title:, description:, body:, author_id:))
    },
  )
}

pub type ListByAuthorRow {
  ListByAuthorRow(
    slug: String,
    title: String,
    description: String,
    created_at: Int,
    username: String,
    image: String,
    fav_count: Option(String),
  )
}

pub fn list_by_author(
  db db: sqlight.Connection,
  author_id author_id: Int,
) -> Result(List(ListByAuthorRow), sqlight.Error) {
  sqlight.query(
    "SELECT a.slug, a.title, a.description, a.created_at, u.username, u.image, (SELECT COUNT(*) FROM favorites WHERE article_id = a.id) as fav_count FROM articles a JOIN users u ON a.author_id = u.id WHERE a.author_id = :author_id ORDER BY a.created_at DESC LIMIT 20",
    on: db,
    with: [sqlight.int(author_id)],
    expecting: {
      use slug <- decode.field(0, decode.string)
      use title <- decode.field(1, decode.string)
      use description <- decode.field(2, decode.string)
      use created_at <- decode.field(3, decode.int)
      use username <- decode.field(4, decode.string)
      use image <- decode.field(5, decode.string)
      use fav_count <- decode.field(6, decode.optional(decode.string))
      decode.success(ListByAuthorRow(
        slug:,
        title:,
        description:,
        created_at:,
        username:,
        image:,
        fav_count:,
      ))
    },
  )
}

pub type ListByTagRow {
  ListByTagRow(
    slug: String,
    title: String,
    description: String,
    created_at: Int,
    username: String,
    image: String,
    fav_count: Option(String),
  )
}

pub fn list_by_tag(
  db db: sqlight.Connection,
  tag tag: String,
  limit limit: Int,
  offset offset: Int,
) -> Result(List(ListByTagRow), sqlight.Error) {
  sqlight.query(
    "SELECT a.slug, a.title, a.description, a.created_at, u.username, u.image, (SELECT COUNT(*) FROM favorites WHERE article_id = a.id) as fav_count FROM articles a JOIN users u ON a.author_id = u.id JOIN article_tags at ON a.id = at.article_id JOIN tags t ON at.tag_id = t.id WHERE t.name = :tag ORDER BY a.created_at DESC LIMIT :limit OFFSET :offset",
    on: db,
    with: [sqlight.text(tag), sqlight.int(limit), sqlight.int(offset)],
    expecting: {
      use slug <- decode.field(0, decode.string)
      use title <- decode.field(1, decode.string)
      use description <- decode.field(2, decode.string)
      use created_at <- decode.field(3, decode.int)
      use username <- decode.field(4, decode.string)
      use image <- decode.field(5, decode.string)
      use fav_count <- decode.field(6, decode.optional(decode.string))
      decode.success(ListByTagRow(
        slug:,
        title:,
        description:,
        created_at:,
        username:,
        image:,
        fav_count:,
      ))
    },
  )
}

pub type ListFavoritedByUserRow {
  ListFavoritedByUserRow(
    slug: String,
    title: String,
    description: String,
    created_at: Int,
    username: String,
    image: String,
    fav_count: Option(String),
  )
}

pub fn list_favorited_by_user(
  db db: sqlight.Connection,
  user_id user_id: Int,
) -> Result(List(ListFavoritedByUserRow), sqlight.Error) {
  sqlight.query(
    "SELECT a.slug, a.title, a.description, a.created_at, u.username, u.image, (SELECT COUNT(*) FROM favorites WHERE article_id = a.id) as fav_count FROM articles a JOIN users u ON a.author_id = u.id JOIN favorites f ON f.article_id = a.id WHERE f.user_id = :user_id ORDER BY a.created_at DESC LIMIT 20",
    on: db,
    with: [sqlight.int(user_id)],
    expecting: {
      use slug <- decode.field(0, decode.string)
      use title <- decode.field(1, decode.string)
      use description <- decode.field(2, decode.string)
      use created_at <- decode.field(3, decode.int)
      use username <- decode.field(4, decode.string)
      use image <- decode.field(5, decode.string)
      use fav_count <- decode.field(6, decode.optional(decode.string))
      decode.success(ListFavoritedByUserRow(
        slug:,
        title:,
        description:,
        created_at:,
        username:,
        image:,
        fav_count:,
      ))
    },
  )
}

pub type ListFeedRow {
  ListFeedRow(
    slug: String,
    title: String,
    description: String,
    created_at: Int,
    username: String,
    image: String,
    fav_count: Option(String),
  )
}

pub fn list_feed(
  db db: sqlight.Connection,
  user_id user_id: Int,
  limit limit: Int,
  offset offset: Int,
) -> Result(List(ListFeedRow), sqlight.Error) {
  sqlight.query(
    "SELECT a.slug, a.title, a.description, a.created_at, u.username, u.image, (SELECT COUNT(*) FROM favorites WHERE article_id = a.id) as fav_count FROM articles a JOIN users u ON a.author_id = u.id WHERE a.author_id IN (SELECT followed_id FROM follows WHERE follower_id = :user_id) ORDER BY a.created_at DESC LIMIT :limit OFFSET :offset",
    on: db,
    with: [sqlight.int(user_id), sqlight.int(limit), sqlight.int(offset)],
    expecting: {
      use slug <- decode.field(0, decode.string)
      use title <- decode.field(1, decode.string)
      use description <- decode.field(2, decode.string)
      use created_at <- decode.field(3, decode.int)
      use username <- decode.field(4, decode.string)
      use image <- decode.field(5, decode.string)
      use fav_count <- decode.field(6, decode.optional(decode.string))
      decode.success(ListFeedRow(
        slug:,
        title:,
        description:,
        created_at:,
        username:,
        image:,
        fav_count:,
      ))
    },
  )
}

pub type ListGlobalRow {
  ListGlobalRow(
    slug: String,
    title: String,
    description: String,
    created_at: Int,
    username: String,
    image: String,
    fav_count: Option(String),
  )
}

pub fn list_global(
  db db: sqlight.Connection,
  limit limit: Int,
  offset offset: Int,
) -> Result(List(ListGlobalRow), sqlight.Error) {
  sqlight.query(
    "SELECT a.slug, a.title, a.description, a.created_at, u.username, u.image, (SELECT COUNT(*) FROM favorites WHERE article_id = a.id) as fav_count FROM articles a JOIN users u ON a.author_id = u.id ORDER BY a.created_at DESC LIMIT :limit OFFSET :offset",
    on: db,
    with: [sqlight.int(limit), sqlight.int(offset)],
    expecting: {
      use slug <- decode.field(0, decode.string)
      use title <- decode.field(1, decode.string)
      use description <- decode.field(2, decode.string)
      use created_at <- decode.field(3, decode.int)
      use username <- decode.field(4, decode.string)
      use image <- decode.field(5, decode.string)
      use fav_count <- decode.field(6, decode.optional(decode.string))
      decode.success(ListGlobalRow(
        slug:,
        title:,
        description:,
        created_at:,
        username:,
        image:,
        fav_count:,
      ))
    },
  )
}

pub fn update(
  db db: sqlight.Connection,
  slug slug: String,
  title title: String,
  description description: String,
  body body: String,
  now now: Int,
  article_id article_id: Int,
) -> Result(List(Nil), sqlight.Error) {
  sqlight.query(
    "UPDATE articles SET slug = :slug, title = :title, description = :description, body = :body, updated_at = :now WHERE id = :article_id",
    on: db,
    with: [
      sqlight.text(slug),
      sqlight.text(title),
      sqlight.text(description),
      sqlight.text(body),
      sqlight.int(now),
      sqlight.int(article_id),
    ],
    expecting: decode.success(Nil),
  )
}
