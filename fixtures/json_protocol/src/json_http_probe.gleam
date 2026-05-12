import generated/public/http_handler
import generated/public/json_codecs
import generated/public/protocol_wire as wire
import gleam/bit_array
import gleam/bytes_tree
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/http/response
import gleam/json
import gleam/option.{Some}
import libero/frame
import libero/json/error.{type JsonError, JsonError}
import mist
import public/pages/home_
import server_context

pub fn main() {
  assert_success_response()
  assert_unknown_rpc_error_frame()
}

fn assert_success_response() {
  let request =
    wire.encode_request(
      module: "rpc",
      request_id: 123,
      msg: json_codecs.json_encode_public_pages_home___server_increment(
        home_.ServerIncrement,
      ),
    )

  let resp =
    http_handler.handle(
      body: bit_array.from_string(request),
      server_context: server_context.ServerContext,
      session_id: "test-session",
    )

  expect_int("success status", resp.status, 200)
  expect_header(resp, "content-type", "application/json")

  let frame_text = response_body_text(resp.body)
  case wire.decode_server_frame(frame_text) {
    Ok(frame.Response(request_id: 123, value: value)) -> {
      case
        json_codecs.json_decode_gleam_result__result(
          value,
          decode_int,
          decode_string,
        )
      {
        Ok(Ok(42)) -> Nil
        other -> panic as { "expected Ok(42), got " <> result_label(other) }
      }
    }
    _ -> panic as "expected response frame for request 123"
  }
}

fn assert_unknown_rpc_error_frame() {
  let request =
    wire.encode_request(
      module: "rpc",
      request_id: 124,
      msg: json.object([
        #("type", json.string("public/pages/home_.UnknownRpc")),
        #("variant", json.string("UnknownRpc")),
        #("fields", json.object([])),
      ]),
    )

  let resp =
    http_handler.handle(
      body: bit_array.from_string(request),
      server_context: server_context.ServerContext,
      session_id: "test-session",
    )

  expect_int("unknown rpc status", resp.status, 200)
  expect_header(resp, "content-type", "application/json")

  let frame_text = response_body_text(resp.body)
  case wire.decode_server_frame(frame_text) {
    Ok(frame.Error(request_id: Some(124), errors: errors)) ->
      case errors {
        [#("type", "unknown: public/pages/home_.UnknownRpc")] -> Nil
        _ -> panic as "expected unknown RPC JSON error frame"
      }
    _ -> panic as "expected error frame for request 124"
  }
}

fn response_body_text(body: mist.ResponseData) -> String {
  case body {
    mist.Bytes(tree) ->
      case bytes_tree.to_bit_array(tree) |> bit_array.to_string {
        Ok(text) -> text
        Error(_) -> panic as "response body was not valid UTF-8"
      }
    _ -> panic as "expected byte response body"
  }
}

fn expect_header(
  resp: response.Response(mist.ResponseData),
  name: String,
  expected: String,
) {
  case response.get_header(resp, name) {
    Ok(actual) -> expect_string(name, actual, expected)
    Error(Nil) -> panic as { "missing response header " <> name }
  }
}

fn expect_int(label: String, actual: Int, expected: Int) {
  case actual == expected {
    True -> Nil
    False -> panic as { label <> " did not match" }
  }
}

fn expect_string(label: String, actual: String, expected: String) {
  case actual == expected {
    True -> Nil
    False -> panic as { label <> " did not match" }
  }
}

fn decode_int(value: Dynamic) -> Result(Int, List(JsonError)) {
  case decode.run(value, decode.int) {
    Ok(value) -> Ok(value)
    Error(_) -> Error([JsonError("value", "expected int")])
  }
}

fn decode_string(value: Dynamic) -> Result(String, List(JsonError)) {
  case decode.run(value, decode.string) {
    Ok(value) -> Ok(value)
    Error(_) -> Error([JsonError("value", "expected string")])
  }
}

fn result_label(
  _result: Result(Result(Int, String), List(JsonError)),
) -> String {
  "unexpected result"
}
