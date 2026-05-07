// Rally owns generated ClientMsg now. This test builds a real generated
// client package, imports its compiled ClientMsg constructors, encodes
// RPC envelopes with Rally's runtime, and asks Erlang to decode the ETF.
//
// Run from the rally root:
//   node test/js/rally_encode_e2e_test.mjs

import { strict as assert } from "node:assert";
import { execFileSync } from "node:child_process";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

execFileSync("gleam", ["run", "-m", "rally"], {
  cwd: "examples/realworld",
  stdio: "inherit",
});
execFileSync("gleam", ["build"], {
  cwd: "examples/realworld/.generated_client",
  stdio: "inherit",
});

const clientRoot = join(
  process.cwd(),
  "examples/realworld/.generated_client/build/dev/javascript/client",
);
const rpc = await import(
  pathToFileURL(join(clientRoot, "generated/rpc_ffi.mjs")).href
);
const types = await import(
  pathToFileURL(join(clientRoot, "generated/types.mjs")).href
);
const gleam = await import(pathToFileURL(join(clientRoot, "gleam.mjs")).href);

class ServerRecordMeasurements extends gleam.CustomType {
  constructor(values) {
    super();
    this.values = values;
  }
}

const cases = [
  [
    "login",
    42,
    new types.ServerLogin("me@example.com", "secret"),
    "{server_login,<<109,101,64,101,120,97,109,112,108,101,46,99,111,109>>,<<115,101,99,114,101,116>>}",
  ],
  [
    "register",
    42,
    new types.ServerRegister("dave", "dave@example.com", "hunter2"),
    "{server_register,<<100,97,118,101>>,<<100,97,118,101,64,101,120,97,109,112,108,101,46,99,111,109>>,<<104,117,110,116,101,114,50>>}",
  ],
];

const erlangCases = cases.map(([name, requestId, msg]) => {
  const payload = rpc.encode_call("rpc", requestId, msg);
  return `{${JSON.stringify(name)},${JSON.stringify(Buffer.from(payload).toString("base64"))}}`;
});

rpc.registerFieldTypes("server_record_measurements", [
  { kind: "list", element: "float" },
]);
const nestedFloatPayload = rpc.encode_call(
  "rpc",
  43,
  new ServerRecordMeasurements(gleam.toList([2.0, 3.5])),
);
erlangCases.push(
  `{${JSON.stringify("nested_float_list")},${JSON.stringify(Buffer.from(nestedFloatPayload).toString("base64"))}}`,
);
cases.push([
  "nested_float_list",
  43,
  null,
  "{server_record_measurements,[2.0,3.5]}",
]);

const printed = execFileSync(
  "erl",
  [
    "-noshell",
    "-eval",
    `Cases = [${erlangCases.join(",")}], lists:foreach(fun({Name, B64}) -> {Module, RequestId, Msg} = binary_to_term(base64:decode(B64)), io:format("~s|~w|~w|~w~n", [Name, Module, RequestId, Msg]) end, Cases), halt().`,
  ],
  { encoding: "utf8" },
);

const terms = new Map(
  printed.trim().split("\n").map((line) => {
    const [name, module, requestId, term] = line.split("|");
    return [name, { module, requestId, term }];
  }),
);

for (const [name, expectedRequestId, _msg, expected] of cases) {
  const actual = terms.get(name);
  assert.equal(actual.module, "<<114,112,99>>", `${name} module`);
  assert.equal(actual.requestId, String(expectedRequestId), `${name} request id`);
  assert.equal(actual.term, expected, name);
}

console.log(`rally encode e2e test passed (${cases.length} cases)`);
