---
# lando-wpll
title: Marmot SQL integration
status: done
type: task
created_at: 2026-05-03T14:34:11Z
updated_at: 2026-05-03T19:00:00Z
---

Wire sql/ directory scanning into lando codegen pipeline

## What was done

- Added `sql_dir` to ScanConfig (configurable in gleam.toml)
- Added `scan_sql_dir` function to scan for .sql files
- Added `run_marmot` step in codegen pipeline: shells out to `gleam run -m marmot` when SQL files are found
- Added `[tools.marmot]` config section to bin/new scaffold
- Output reports SQL query count (e.g. "1 routes, 3 SQL queries")
