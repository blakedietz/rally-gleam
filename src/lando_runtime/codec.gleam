import gleam/bit_array
import gleam/result
import lando_runtime/wire

/// Encode any Gleam value to a base64 ETF string for embedding in HTML.
/// Used server-side during SSR to serialize the page model into flags.
pub fn encode_flags(value: a) -> String {
  value
  |> wire.encode
  |> bit_array.base64_encode(True)
}

/// Decode a base64 ETF string back to a Gleam value.
/// Used client-side during hydration to read the server-rendered model.
pub fn decode_flags(flags: String) -> Result(a, String) {
  use bits <- result.try(
    bit_array.base64_decode(flags)
    |> result.map_error(fn(_) { "Failed to base64-decode flags" })
  )
  case wire.decode_safe(bits) {
    Ok(value) -> Ok(value)
    Error(err) -> Error("Failed to ETF-decode flags: " <> err.message)
  }
}
