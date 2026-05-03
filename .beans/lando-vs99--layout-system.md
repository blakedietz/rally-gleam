---
# lando-vs99
title: Layout system
status: done
type: task
created_at: 2026-05-03T14:34:11Z
updated_at: 2026-05-03T18:45:00Z
---

Nested layouts like elm-land

## What was done

- Added `layout_module: Option(String)` to ScannedRoute
- Scanner detects `layout.gleam` files and assigns nearest ancestor layout to each page
- Layout files are excluded from route generation (they're not pages)
- SSR handler generator: imports layout modules and wraps page views in `layout_module.layout(page_view)` when a layout is assigned
- Added example `layout.gleam` to bin/new scaffold
