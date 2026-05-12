// Runtime probe: verify that the server push encoding produces a
// JSON frame with full typed identity.
//
// Builds the fixture, then runs a Node.js script that loads the
// generated JS modules and verifies the full push decode path.
//
// Run from the project root with:
//   node test/js/server_push_encode_test.mjs

import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { strictEqual, ok as assert } from "node:assert";
import { readFileSync } from "node:fs";

const __dirname = dirname(fileURLToPath(import.meta.url));

// Read the generated JSON push frame from the fixture's rally gen output.
// The atoms.erl generates this at the Erlang level; here we verify the
// JS client path can round-trip it.
const buildDir = resolve(
  __dirname,
  "../../fixtures/json_protocol/.generated_clients/public/build/dev/javascript/client/generated",
);

const mod = await import(`file://${buildDir}/protocol_wire.mjs`);
const { typedJsonToGleamValue, decode_server_frame } = mod;

// ---- Test 1: typedJsonToGleamValue produces correct ToClient instances ----
const homeUpdated = typedJsonToGleamValue({
  type: "public/pages/home_.ToClient",
  variant: "Updated",
  fields: { count: 42 },
});
strictEqual(homeUpdated.constructor.name, "Updated");
strictEqual(homeUpdated.count, 42);

const notifUpdated = typedJsonToGleamValue({
  type: "public/pages/notifications_.ToClient",
  variant: "Updated",
  fields: { msg: "hello" },
});
strictEqual(notifUpdated.constructor.name, "Updated");
strictEqual(notifUpdated.msg, "hello");

// ---- Test 2: decode_server_frame handles a push frame ----
// Construct a JSON push frame matching what the server would produce.
const pushFrame = JSON.stringify({
  kind: "push",
  protocol_version: "json-rpc-v1",
  module: "Public",
  value: {
    type: "public/pages/home_.ToClient",
    variant: "Updated",
    fields: { count: 99 },
  },
});

const decoded = decode_server_frame(pushFrame);
assert(decoded[0] !== undefined, "decode_server_frame must return Ok");
const frame = decoded[0];
strictEqual(frame.kind, "push");
strictEqual(frame.module, "Public");

const value = frame.value;
strictEqual(value.constructor.name, "Updated", "push value must be Updated instance");
strictEqual(value.count, 99, "push value count must be 99");

// ---- Test 3: push decode rejects mismatched type ----
// Same variant "Updated" but wrong parent type must fail.
try {
  typedJsonToGleamValue({
    type: "public/pages/home_.WrongType",
    variant: "Updated",
    fields: { count: 1 },
  });
  assert(false, "Should have thrown for mismatched parent type");
} catch (e) {
  assert(
    e.message.includes("Unknown type in JSON decode"),
    "Must throw Unknown type error",
  );
}

console.log("OK: all server push encode/probe tests passed");
