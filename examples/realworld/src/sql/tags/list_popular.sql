SELECT t.name
FROM tags t
JOIN article_tags at ON t.id = at.tag_id
GROUP BY t.id
ORDER BY COUNT(*) DESC
LIMIT 10
