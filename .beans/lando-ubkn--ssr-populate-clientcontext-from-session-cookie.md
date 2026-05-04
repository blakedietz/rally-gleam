---
# lando-ubkn
title: 'SSR: populate ClientContext from session cookie'
status: todo
type: task
created_at: 2026-05-04T23:46:13Z
updated_at: 2026-05-04T23:46:13Z
---

SSR handler currently uses client_context.init() (logged-out state). To show correct auth state on first render, pass the request's session cookie to a user-defined function (e.g. client_context.from_session) that looks up the user and returns a pre-populated context.
