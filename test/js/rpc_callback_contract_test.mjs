// Verifies the browser RPC callback contract against the compiled generated
// runtime: wire Ok values are unwrapped before user callbacks, and framework
// Error values go through the global RPC error handler.
//
// Run from the rally root after building the realworld client:
//   node test/js/rpc_callback_contract_test.mjs

import { strict as assert } from "assert";
import * as rpc from "../../examples/realworld/.generated_client/public/build/dev/javascript/client/generated/rpc_ffi.mjs";
import {
  Ok,
  Error as ResultError,
} from "../../examples/realworld/.generated_client/public/build/dev/javascript/gleam_stdlib/gleam.mjs";

class FakeWebSocket {
  static OPEN = 1;
  static instances = [];

  constructor(url) {
    this.url = url;
    this.readyState = FakeWebSocket.OPEN;
    this.sent = [];
    this.listeners = new Map();
    FakeWebSocket.instances.push(this);
  }

  addEventListener(name, callback) {
    this.listeners.set(name, callback);
  }

  send(payload) {
    this.sent.push(payload);
  }

  close() {
    this.readyState = 3;
  }

  receive(bytes) {
    const callback = this.listeners.get("message");
    assert.ok(callback, "message listener registered");
    callback({ data: bytes.buffer });
  }
}

globalThis.WebSocket = FakeWebSocket;

function responseFrame(requestId, value) {
  const payload = rpc.encode_value(value).rawBuffer;
  const bytes = new Uint8Array(1 + 4 + payload.byteLength);
  bytes[0] = 0x00;
  new DataView(bytes.buffer).setUint32(1, requestId);
  bytes.set(payload, 5);
  return bytes;
}

assert.equal(
  typeof rpc.registerRpcErrorHandler,
  "function",
  "runtime exposes framework RPC error handler registration",
);

{
  let callbackValue = undefined;
  let callbackCalls = 0;

  rpc.send("/ws", "rpc", "request", (value) => {
    callbackCalls += 1;
    callbackValue = value;
  });

  FakeWebSocket.instances[0].receive(responseFrame(1, new Ok("handler value")));

  assert.equal(callbackCalls, 1);
  assert.equal(callbackValue, "handler value");
  console.log("PASS: wire Ok unwraps before user callback");
}

{
  let callbackCalls = 0;
  let callbackValue = undefined;
  let handlerValue = undefined;

  rpc.registerRpcErrorHandler((message) => {
    handlerValue = message;
  });

  rpc.send("/ws", "rpc", "request", (value) => {
    callbackCalls += 1;
    callbackValue = value;
  });

  FakeWebSocket.instances[0].receive(
    responseFrame(2, new Ok(new ResultError("Not yet implemented"))),
  );

  assert.equal(callbackCalls, 1);
  assert.ok(callbackValue instanceof ResultError);
  assert.equal(callbackValue[0], "Not yet implemented");
  assert.equal(handlerValue, undefined);
  console.log("PASS: domain Error inside wire Ok reaches user callback");
}

{
  let callbackCalls = 0;
  let handlerValue = undefined;

  rpc.registerRpcErrorHandler((message) => {
    handlerValue = message;
  });

  rpc.send("/ws", "rpc", "request", () => {
    callbackCalls += 1;
  });

  FakeWebSocket.instances[0].receive(responseFrame(3, new ResultError("boom")));

  assert.equal(callbackCalls, 0);
  assert.equal(handlerValue, "boom");
  console.log("PASS: framework Error routes to RPC error handler");
}
