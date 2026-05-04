---
# lando-gr9y
title: Route params in server_init
status: todo
type: task
created_at: 2026-05-04T22:51:13Z
updated_at: 2026-05-04T22:51:13Z
---

server_init doesn't receive route params. Client sends Load message as workaround (extra round-trip). Include params in first WebSocket message for the page.
