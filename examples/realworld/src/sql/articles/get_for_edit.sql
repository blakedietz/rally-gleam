SELECT id, title, description, body, author_id
FROM articles
WHERE slug = :slug
