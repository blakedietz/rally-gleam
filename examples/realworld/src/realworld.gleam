import generated/public/http_handler
import generated/public/router
import generated/public/ssr_handler
import generated/public/ws_handler
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http.{Get, Post}
import gleam/http/request.{type Request, Request}
import gleam/http/response.{type Response}
import gleam/list
import gleam/result
import gleam/string
import mist.{type Connection, type ResponseData}
import rally_runtime/db
import rally_runtime/env
import rally_runtime/migrate
import rally_runtime/session
import rally_runtime/system
import server_context.{ServerContext}
import simplifile
import sqlight

const client_build_root = ".generated_client/public/build/dev/javascript"

pub fn main() {
  let db = start_db()
  system.start("system.db")
  let server_context = ServerContext(db:)

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
          fn(conn) { ws_handler.on_init(conn, server_context, session_id) },
          ws_handler.on_close,
        )
      }
      "/rpc" -> {
        case method {
          Post -> {
            case mist.read_body(req, max_body_limit: 16_000_000) {
              Ok(Request(body: body, ..)) ->
                http_handler.handle(body, server_context)
              Error(_) ->
                response.new(413)
                |> response.set_body(
                  mist.Bytes(bytes_tree.from_string("Request body too large")),
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
      _ -> {
        case string.starts_with(path, "/_build/") {
          True -> serve_static(string.drop_start(path, 8))
          False ->
            case method {
              Get -> {
                let session_id = case request.get_header(req, "cookie") {
                  Ok(cookie) ->
                    case session.extract_session_id(cookie) {
                      Ok(id) -> id
                      Error(_) -> session.generate_id()
                    }
                  Error(_) -> session.generate_id()
                }
                let route = router.parse_route(request.to_uri(req))
                let hostname =
                  request.get_header(req, "host") |> result.unwrap("")
                let resp =
                  ssr_handler.handle_request(
                    route,
                    server_context,
                    session_id,
                    hostname,
                  )
                case request.get_header(req, "cookie") {
                  Ok(cookie) ->
                    case session.extract_session_id(cookie) {
                      Ok(_) -> resp
                      Error(_) ->
                        response.set_header(
                          resp,
                          "set-cookie",
                          session.set_cookie_header(
                            session_id:,
                            secure: env.secure_cookies(),
                          ),
                        )
                    }
                  Error(_) ->
                    response.set_header(
                      resp,
                      "set-cookie",
                      session.set_cookie_header(
                        session_id:,
                        secure: env.secure_cookies(),
                      ),
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
  }

  let assert Ok(_) =
    mist.new(handler)
    |> mist.port(8080)
    |> mist.start
  process.sleep_forever()
}

fn serve_static(path: String) -> Response(ResponseData) {
  let file_path = client_build_root <> "/" <> path
  let has_traversal =
    string.split(path, "/")
    |> list.any(fn(seg) { seg == ".." || seg == "." })
  case has_traversal {
    True ->
      response.new(403)
      |> response.set_body(mist.Bytes(bytes_tree.from_string("Forbidden")))
    False ->
      case simplifile.read(file_path) {
        Ok(content) -> {
          let content_type = case string.ends_with(path, ".mjs") {
            True -> "application/javascript"
            False ->
              case string.ends_with(path, ".js") {
                True -> "application/javascript"
                False -> "application/octet-stream"
              }
          }
          response.new(200)
          |> response.set_header("content-type", content_type)
          |> response.set_body(mist.Bytes(bytes_tree.from_string(content)))
        }
        Error(_) ->
          response.new(404)
          |> response.set_body(mist.Bytes(bytes_tree.from_string("Not found")))
      }
  }
}

fn start_db() -> sqlight.Connection {
  let assert Ok(conn) = db.open("app.db")
  let assert Ok(_) = migrate.run(conn:, dir: "migrations")
  conn
}
