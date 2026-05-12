// JS runtime test: two push payload types from different modules share
// the same constructor name "Updated". The type registry must distinguish
// them via full "<module>.<type>#<variant>" keys.
//
// Run from the project root with:
//   node test/js/push_decode_identity_test.mjs

import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { ok as assert, strictEqual, notStrictEqual } from "node:assert";

const __dirname = dirname(fileURLToPath(import.meta.url));
const buildDir = resolve(
  __dirname,
  "../../fixtures/json_protocol/.generated_clients/public/build/dev/javascript/client/generated",
);

const mod = await import(`file://${buildDir}/protocol_wire.mjs`);
const { typedJsonToGleamValue } = mod;

// ---- Test 1: home_.ToClient.Updated decodes to correct constructor ----
const homeUpdated = typedJsonToGleamValue({
  type: "public/pages/home_.ToClient",
  variant: "Updated",
  fields: { count: 5 },
});
strictEqual(
  homeUpdated.constructor.name,
  "Updated",
  "home_ Updated must be an Updated instance",
);
strictEqual(homeUpdated.count, 5, "home_ Updated.count must be 5");

// ---- Test 2: notifications_.ToClient.Updated decodes to correct constructor ----
const notifUpdated = typedJsonToGleamValue({
  type: "public/pages/notifications_.ToClient",
  variant: "Updated",
  fields: { msg: "hello" },
});
strictEqual(
  notifUpdated.constructor.name,
  "Updated",
  "notifications_ Updated must be an Updated instance",
);
strictEqual(notifUpdated.msg, "hello", "notifications_ Updated.msg must be 'hello'");

// ---- Test 3: same variant name, different modules -> distinct classes ----
// The instances may share constructor name "Updated" but they must be
// from different module namespaces (different prototype chains).
notStrictEqual(
  Object.getPrototypeOf(homeUpdated).constructor,
  Object.getPrototypeOf(notifUpdated).constructor,
  "home_.Updated and notifications_.Updated must have different prototypes",
);

console.log("OK: all push decode identity tests passed");
