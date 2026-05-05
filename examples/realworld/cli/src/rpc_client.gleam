import libero/wire

pub type RpcError {
  HttpError(String)
  ServerError(String)
}

pub fn call(
  base_url base_url: String,
  msg msg: a,
) -> Result(b, RpcError) {
  let body = wire.encode(#("rpc", 1, msg))
  case http_post(base_url <> "/rpc", body) {
    Ok(response_bytes) -> {
      // Response is tag_response format: <<0x00, request_id:32, payload_etf>>
      case response_bytes {
        <<0, _request_id:32, payload:bits>> -> {
          let decoded: Result(b, c) = wire.decode(payload)
          case decoded {
            Ok(value) -> Ok(value)
            Error(_err) -> Error(ServerError("Server returned an error"))
          }
        }
        _ -> Error(ServerError("Unexpected response format"))
      }
    }
    Error(reason) -> Error(HttpError(reason))
  }
}

@external(erlang, "rpc_client_ffi", "http_post")
fn http_post(url: String, body: BitArray) -> Result(BitArray, String)
