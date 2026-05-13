# Test Fixtures

This directory contains small apps used by Rally's tests. They are not user
examples.

`json_protocol/` is an executable Gleam app used to test JSON protocol codegen,
HTTP dispatch, generated client modules, and JS decode behavior. It lives here
instead of under `test/` because Gleam compiles real `.gleam` files under
`test/` as part of the root test package.
