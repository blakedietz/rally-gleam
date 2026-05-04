INSERT INTO comments (body, article_id, author_id, created_at)
VALUES (:body, :article_id, :author_id, :now)
RETURNING id
