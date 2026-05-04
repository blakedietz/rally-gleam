UPDATE articles
SET slug = :slug, title = :title, description = :description, body = :body, updated_at = :now
WHERE id = :article_id
