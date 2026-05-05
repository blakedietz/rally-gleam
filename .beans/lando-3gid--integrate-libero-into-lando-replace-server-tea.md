---
# lando-3gid
title: Integrate libero into lando (replace server TEA)
status: todo
type: epic
created_at: 2026-05-05T02:28:12Z
updated_at: 2026-05-05T02:28:12Z
blocked_by:
    - lando-4crc
---

After libero is cleaned up: remove ServerModel/server_init/server_update from lando. Replace with libero handler-as-contract pattern. Lando scanner calls libero scanner for server_ functions, generates client stubs as Lustre effects fitting into the TEA app, generates HTTP handler and WS handler that both call libero dispatch. Page contract becomes: client TEA (init/update/view) + server handlers (server_login, server_create_article, etc). No ToServer/ToClient types needed.
