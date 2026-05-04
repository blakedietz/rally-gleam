INSERT INTO articles (slug, title, description, body, author_id, created_at, updated_at)
VALUES (:slug, :title, :description, :body, :author_id, :created_at, :updated_at)
RETURNING id, slug
