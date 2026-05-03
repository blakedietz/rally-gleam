---
# lando-xieg
title: Framework-owned async UX
status: done
type: task
created_at: 2026-05-03T14:34:11Z
updated_at: 2026-05-03T18:15:00Z
---

Generic loading overlay, error toast, reconnect indicator

## What was done

- Updated generated client app.gleam with framework-owned async UX:
  - Connection state tracking: Connected, Disconnected, Reconnecting
  - Transport init via lustre/effect.from — properly wires callbacks to Msg dispatch
  - Reconnect banner — shows "Disconnected from server. Reconnecting..." when WebSocket drops
  - Loading bar — ready for page transition loading state
  - Toast notification system — error/info toasts with dismiss buttons
- Push handler registrations moved inside main() function
