// JS runtime test: prove that the type registry rejects a mismatched
// parent type. The registry keys use "<module>.<type>#<variant>" so
// { type: "some/module.OldType", variant: "Discount" } must NOT resolve.
//
// Run from the project root with:
//   node --experimental-vm-modules test/rally/identity_decode_test.mjs
// or via the Gleam test that invokes it.

import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { ok as assert, strictEqual, throws } from "node:assert";

const __dirname = dirname(fileURLToPath(import.meta.url));
const buildDir = resolve(
  __dirname,
  "../../test_fixtures/json_protocol/.generated_clients/public/build/dev/javascript/client/generated",
);

// Dynamic import so relative imports inside protocol_wire.mjs resolve
// correctly from the build directory.
const mod = await import(
  `file://${buildDir}/protocol_wire.mjs`
);
const { typedJsonToGleamValue } = mod;

// ---- Test 1: unknown type throws ----
// The registry has "public/pages/home_.IncrementResult#IncrementResult".
// Feeding a mismatched parent type with same variant name must throw.
throws(
  () =>
    typedJsonToGleamValue({
      type: "public/pages/home_.WrongType",
      variant: "IncrementResult",
      fields: { old: 0, new: 1 },
    }),
  /Unknown type in JSON decode/,
  "Mismatched parent type must throw, not silently resolve to a different type",
);

// ---- Test 2: correct type decodes correctly ----
// The registry has "public/pages/home_.IncrementResult#IncrementResult".
// This must produce an IncrementResult instance, not CustomType.
const result = typedJsonToGleamValue({
  type: "public/pages/home_.IncrementResult",
  variant: "IncrementResult",
  fields: { old: 0, new: 1 },
});

// Must not be a generic CustomType
strictEqual(
  result.constructor.name,
  "IncrementResult",
  "Decoded value must be an IncrementResult instance",
);
strictEqual(result.old, 0, "field 'old' must be 0");
strictEqual(result.new, 1, "field 'new' must be 1");

// ---- Test 3: same variant name from different module fails ----
// The registry has "public/pages/home_.ServerIncrement#ServerIncrement"
// (zero-field) and "public/pages/home_.IncrementResult#IncrementResult"
// (with fields). Feeding a fully unknown module+type must throw.
throws(
  () =>
    typedJsonToGleamValue({
      type: "completely/different.Module",
      variant: "ServerIncrement",
      fields: {},
    }),
  /Unknown type in JSON decode/,
  "Unknown module must throw",
);

// ---- Test 4: Result wrapping still works ----
// Nested user types inside Result must go through the registry.
const okResult = typedJsonToGleamValue({
  type: "gleam/result.Result",
  variant: "Ok",
  fields: [
    {
      type: "public/pages/home_.IncrementResult",
      variant: "IncrementResult",
      fields: { old: 1, new: 2 },
    },
  ],
});
strictEqual(okResult.constructor.name, "Ok", "outer must be Ok");
strictEqual(
  okResult[0].constructor.name,
  "IncrementResult",
  "inner must be IncrementResult",
);
strictEqual(okResult[0].old, 1);
strictEqual(okResult[0].new, 2);

console.log("OK: all identity decode tests passed");
