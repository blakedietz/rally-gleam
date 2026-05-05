import gleam/dynamic.{type Dynamic}
import libero/error.{type DecodeError}
import libero/wire as libero_wire

pub fn encode(value: a) -> BitArray {
  libero_wire.encode(value)
}

pub fn decode(data: BitArray) -> a {
  libero_wire.decode(data)
}

pub fn decode_safe(data: BitArray) -> Result(a, DecodeError) {
  libero_wire.decode_safe(data)
}

pub fn decode_call(
  data: BitArray,
) -> Result(#(String, Int, Dynamic), DecodeError) {
  libero_wire.decode_call(data)
}

pub fn encode_call(
  module module: String,
  request_id request_id: Int,
  msg msg: a,
) -> BitArray {
  libero_wire.encode_call(module:, request_id:, msg:)
}

pub fn tag_response(
  request_id request_id: Int,
  data data: BitArray,
) -> BitArray {
  libero_wire.tag_response(request_id:, data:)
}

pub fn tag_push(module module: String, msg msg: a) -> BitArray {
  let data = libero_wire.encode(#(module, msg))
  <<1, data:bits>>
}

pub fn variant_tag(value: Dynamic) -> Result(String, Nil) {
  libero_wire.variant_tag(value)
}

pub fn coerce(value: a) -> b {
  do_coerce(value)
}

@external(erlang, "lando_runtime_wire_ffi", "tuple_element")
pub fn tuple_element(tuple: Dynamic, index: Int) -> Dynamic {
  let _ = tuple
  let _ = index
  panic as "lando_runtime/wire.tuple_element: server-side only"
}

@external(erlang, "gleam_stdlib", "identity")
fn do_coerce(value: a) -> b
