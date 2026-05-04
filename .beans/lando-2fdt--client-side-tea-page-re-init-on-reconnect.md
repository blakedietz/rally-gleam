---
# lando-2fdt
title: 'Client-side TEA: page re-init on reconnect'
status: todo
type: task
created_at: 2026-05-04T16:05:59Z
updated_at: 2026-05-04T16:05:59Z
---

When WebSocket reconnects, server_init runs again but the client page model isn't reset. May cause stale state. Consider re-running page init on reconnect.
