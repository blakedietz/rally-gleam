# CLAUDE.md

After any significant change to the codebase, update `llms.txt` to reflect the new state. This file is the canonical description of the lando framework.

Use `./tmp` for creating test apps.

## Lamdera as reference, not gospel

Lamdera is the primary inspiration for Lando's architecture (ToServer/ToClient message types, server_update, shared state). Follow Lamdera's patterns as a starting point, but Gleam on the BEAM gives us more powerful primitives for process management, WebSocket connections, and server state than Elm has access to. When we find a better way to do something, take it.
