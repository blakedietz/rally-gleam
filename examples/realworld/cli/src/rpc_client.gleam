import libero/wire

pub type RpcError {
  HttpError(String)
  ServerError(String)
}

pub fn call(base_url base_url: String, msg msg: a) -> Result(b, RpcError) {
  let body = wire.encode_request(module: "rpc", request_id: 1, msg:)
  case http_post(base_url <> "/rpc", body) {
    Ok(response_bytes) -> {
      case wire.decode_response_frame(response_bytes) {
        Ok(wire.Response(request_id: _, value:)) -> {
          let decoded: Result(b, c) = wire.coerce(value)
          case decoded {
            Ok(value) -> Ok(value)
            Error(_err) -> Error(ServerError("Server returned an error"))
          }
        }
        Error(_) -> Error(ServerError("Unexpected response format"))
      }
    }
    Error(reason) -> Error(HttpError(reason))
  }
}

@external(erlang, "rpc_client_ffi", "http_post")
fn http_post(url: String, body: BitArray) -> Result(BitArray, String)
