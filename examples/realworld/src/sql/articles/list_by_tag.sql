SELECT a.slug, a.title, a.description, a.created_at,
       u.username, u.image,
       (SELECT COUNT(*) FROM favorites WHERE article_id = a.id) as fav_count
FROM articles a
JOIN users u ON a.author_id = u.id
JOIN article_tags at ON a.id = at.article_id
JOIN tags t ON at.tag_id = t.id
WHERE t.name = :tag
ORDER BY a.created_at DESC
LIMIT :limit OFFSET :offset
