// Tests the auth error detection in transport_ffi.mjs.
//
// The server sends Error("auth:redirect:<url>") and Error("auth:forbidden")
// as wire error responses for auth policy failures. The transport must
// detect these exact patterns and handle them before user callbacks.
//
// This imports the real detectAuthError from a copy of transport_ffi.mjs
// placed in tmp/auth_error_test/ by run_auth_error_test.sh. Shims for
// gleam_stdlib and libero live alongside it so relative imports resolve.
//
// Run: test/js/run_auth_error_test.sh

import { strict as assert } from "assert";
import { detectAuthError } from "../../tmp/auth_error_test/src/generated/transport_ffi.mjs";
import { Ok, Error as ResultError } from "../../tmp/auth_error_test/gleam_stdlib/gleam.mjs";

// --- Redirect detection ---

{
  const err = detectAuthError(new ResultError("auth:redirect:/login"));
  assert.notEqual(err, null);
  assert.equal(err.kind, "redirect");
  assert.equal(err.url, "/login");
  console.log("PASS: auth:redirect:/login detected");
}

{
  const err = detectAuthError(
    new ResultError("auth:redirect:/admin/login?from=/dashboard"),
  );
  assert.notEqual(err, null);
  assert.equal(err.kind, "redirect");
  assert.equal(err.url, "/admin/login?from=/dashboard");
  console.log("PASS: auth:redirect: with query params detected");
}

{
  const err = detectAuthError(new ResultError("auth:redirect:"));
  assert.notEqual(err, null);
  assert.equal(err.kind, "redirect");
  assert.equal(err.url, "");
  console.log("PASS: auth:redirect: with empty URL detected");
}

// --- Forbidden detection ---

{
  const err = detectAuthError(new ResultError("auth:forbidden"));
  assert.notEqual(err, null);
  assert.equal(err.kind, "forbidden");
  console.log("PASS: auth:forbidden detected");
}

// --- Unknown auth:* falls through ---

{
  const err = detectAuthError(new ResultError("auth:unknown"));
  assert.equal(err, null);
  console.log("PASS: unknown auth:* falls through");
}

{
  const err = detectAuthError(new ResultError("auth:redirect"));
  // No colon after "redirect" — not a valid redirect error
  assert.equal(err, null);
  console.log("PASS: auth:redirect (no colon) falls through");
}

{
  const err = detectAuthError(new ResultError("auth:forbidden_extra"));
  assert.equal(err, null);
  console.log("PASS: auth:forbidden_extra falls through");
}

// --- Non-string Error falls through ---

{
  const err = detectAuthError(new ResultError(42));
  assert.equal(err, null);
  console.log("PASS: numeric Error falls through");
}

{
  const err = detectAuthError(new ResultError({ code: "auth:forbidden" }));
  assert.equal(err, null);
  console.log("PASS: object Error falls through");
}

{
  const err = detectAuthError(new ResultError(null));
  assert.equal(err, null);
  console.log("PASS: null Error falls through");
}

// --- Ok values are not auth errors ---

{
  const err = detectAuthError(new Ok("auth:redirect:/login"));
  assert.equal(err, null);
  console.log("PASS: Ok wrapping auth:redirect: is not an auth error");
}

{
  const err = detectAuthError(new Ok("some data"));
  assert.equal(err, null);
  console.log("PASS: Ok success value passes through");
}

// --- Non-ResultError values ---

{
  const err = detectAuthError("auth:redirect:/login");
  assert.equal(err, null);
  console.log("PASS: plain string is not an auth error");
}

{
  const err = detectAuthError(null);
  assert.equal(err, null);
  console.log("PASS: null is not an auth error");
}

{
  const err = detectAuthError(undefined);
  assert.equal(err, null);
  console.log("PASS: undefined is not an auth error");
}

// --- Instanceof works across imports ---
// Verify that ResultError from our import is the same class that
// detectAuthError checks against (both imported from the same shim).

{
  const ourError = new ResultError("test");
  assert.ok(ourError instanceof ResultError);
  // detectAuthError must recognize this as a ResultError
  const err = detectAuthError(ourError);
  // "test" is not an auth error, so should return null (not crash)
  assert.equal(err, null);
  console.log("PASS: shared ResultError class between test and transport");
}

console.log("\nAll auth error detection tests passed.");
