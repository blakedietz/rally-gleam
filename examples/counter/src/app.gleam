import app_config.{Context}
import mist.{type Connection, type ResponseData}
import gleam/bytes_tree
import gleam/dict
import gleam/erlang/process
import gleam/http.{Get}
import gleam/http/request.{type Request, Request}
import gleam/http/response.{type Response}
import gleam/option.{None}
import simplifile
import sqlight
import generated/router
import generated/ssr_handler

pub fn main() {
  let db = start_db()
  let ctx = Context(db:)

  let handler = fn(req: Request(Connection)) -> Response(ResponseData) {
    let Request(path: path, method: method, ..) = req
    case path {
      "/ws" -> mist.websocket(
        req,
        fn(state, _msg, _conn) { mist.continue(state) },
        fn(_conn) { #(dict.new(), None) },
        fn(_state) { Nil },
      )
      "/client.js" -> serve_client_js()
      _ -> {
        case method {
          Get -> {
            let route = router.parse_route(request.to_uri(req))
            ssr_handler.handle_request(route, ctx)
          }
          _ -> response.new(405)
            |> response.set_body(mist.Bytes(bytes_tree.from_string("Not found")))
        }
      }
    }
  }

  let assert Ok(_) =
    mist.new(handler)
    |> mist.port(8080)
    |> mist.start
  process.sleep_forever()
}

fn serve_client_js() -> Response(ResponseData) {
  case simplifile.read("client/build/dev/javascript/client/app.mjs") {
    Ok(js) ->
      response.new(200)
      |> response.set_header("content-type", "application/javascript")
      |> response.set_body(mist.Bytes(bytes_tree.from_string(js)))
    Error(_) ->
      response.new(404)
      |> response.set_body(mist.Bytes(bytes_tree.from_string("Client JS not found")))
  }
}

fn start_db() -> sqlight.Connection {
  let assert Ok(conn) = sqlight.open("app.db")
  conn
}
