//// Guard: Rally's transport_ffi.mjs must not contain byte-level frame
//// awareness. Libero owns the frame boundary. If this test fails,
//// someone reintroduced tag-byte inspection or raw decode imports.
////
//// Step 2 of the contract boundary spec.

import gleam/string
import simplifile

pub fn transport_ffi_has_no_byte_level_frame_awareness_test() {
  let assert Ok(content) = simplifile.read(
    "src/rally_runtime/transport_ffi.mjs",
  )

  // Must NOT inspect frame tag bytes
  let assert False = string.contains(content, "0x00")
  let assert False = string.contains(content, "0x01")

  // Must NOT import raw decode functions
  let assert False = string.contains(content, "import { encode_call, decode_value }")
  let assert False = string.contains(content, "import { decode_value")
  let assert False = string.contains(content, "decode_value(")

  // Must NOT slice frame headers manually
  let assert False = string.contains(content, "DataView")
  let assert False = string.contains(content, "getUint32")

  // Must USE the boundary API
  let assert True = string.contains(content, "decode_server_frame")
}
