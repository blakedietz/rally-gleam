import generated/router
import generated/ssr_handler
import generated/ws_handler
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http.{Get}
import gleam/http/request.{type Request, Request}
import gleam/http/response.{type Response}
import lando_runtime/migrate
import lando_runtime/session
import mist.{type Connection, type ResponseData}
import server_context.{ServerContext}
import simplifile
import sqlight

pub fn main() {
  let db = start_db()
  let ctx = ServerContext(db:)

  let handler = fn(req: Request(Connection)) -> Response(ResponseData) {
    let Request(path: path, method: method, ..) = req
    case path {
      "/ws" -> {
        let session_id = case request.get_header(req, "cookie") {
          Ok(cookie) ->
            case session.extract_session_id(cookie) {
              Ok(id) -> id
              Error(_) -> session.generate_id()
            }
          Error(_) -> session.generate_id()
        }
        mist.websocket(
          req,
          ws_handler.handler,
          fn(conn) { ws_handler.on_init(conn, ctx, session_id) },
          ws_handler.on_close,
        )
      }
      "/client.js" -> serve_client_js()
      _ -> {
        case method {
          Get -> {
            let route = router.parse_route(request.to_uri(req))
            let resp = ssr_handler.handle_request(route, ctx)
            case request.get_header(req, "cookie") {
              Ok(cookie) ->
                case session.extract_session_id(cookie) {
                  Ok(_) -> resp
                  Error(_) ->
                    response.set_header(
                      resp,
                      "set-cookie",
                      session.set_cookie_header(session.generate_id()),
                    )
                }
              Error(_) ->
                response.set_header(
                  resp,
                  "set-cookie",
                  session.set_cookie_header(session.generate_id()),
                )
            }
          }
          _ ->
            response.new(405)
            |> response.set_body(
              mist.Bytes(bytes_tree.from_string("Not found")),
            )
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
  case simplifile.read("client/build/dev/javascript/client/generated/app.mjs") {
    Ok(js) ->
      response.new(200)
      |> response.set_header("content-type", "application/javascript")
      |> response.set_body(mist.Bytes(bytes_tree.from_string(js)))
    Error(_) ->
      response.new(404)
      |> response.set_body(
        mist.Bytes(bytes_tree.from_string("Client JS not found")),
      )
  }
}

fn start_db() -> sqlight.Connection {
  let assert Ok(conn) = sqlight.open("app.db")
  let assert Ok(_) = migrate.run(conn:, dir: "migrations")
  conn
}
