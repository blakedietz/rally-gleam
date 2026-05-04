SELECT c.id, c.body, c.created_at, u.username, u.image
FROM comments c
JOIN users u ON c.author_id = u.id
WHERE c.article_id = :article_id
ORDER BY c.created_at ASC
