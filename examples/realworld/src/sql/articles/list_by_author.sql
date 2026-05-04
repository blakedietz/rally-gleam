SELECT a.slug, a.title, a.description, a.created_at,
       u.username, u.image,
       (SELECT COUNT(*) FROM favorites WHERE article_id = a.id) as fav_count
FROM articles a
JOIN users u ON a.author_id = u.id
WHERE a.author_id = :author_id
ORDER BY a.created_at DESC
LIMIT 20
