---
# lando-o2j9
title: Glance-based parser
status: done
type: task
created_at: 2026-05-03T14:34:11Z
updated_at: 2026-05-03T16:30:00Z
---

Replace string-matching parser.gleam with glance AST parser (from libero scanner)

## What was done

- Rewrote `parser.gleam` to use `glance.module()` for AST-based parsing
- Extracts ToBackend/ToFrontend custom types with full field type info (via VariantInfo with FieldType)
- Type resolution: builtin types (Int, String, etc.) map to FieldType directly; user types resolve via import maps
- Import map building (from libero scanner): `build_type_import_map`, `build_alias_resolution_map`, `build_type_alias_originals`
- Function detection via AST: `has_function` checks for public functions by name
- Init param extraction from the `init` function AST parameters
- Updated `PageContract` to store `List(VariantInfo)` with structured field types instead of `List(String)`
- Updated all tests and snapshots for new types; added `parse_page_with_server_init_test`
