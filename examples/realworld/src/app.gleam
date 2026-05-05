import generated/ws_handler
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http.{Get}
import gleam/http/request.{type Request, Request}
import gleam/http/response.{type Response}
import gleam/string
import lando_runtime/db
import lando_runtime/migrate
import lando_runtime/session
import lando_runtime/system
import mist.{type Connection, type ResponseData}
import server_context.{ServerContext}
import simplifile
import sqlight

const client_build_root = "client/build/dev/javascript"

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
      _ -> {
        case string.starts_with(path, "/_build/") {
          True -> serve_static(string.drop_start(path, 8))
          False ->
            case method {
              Get -> {
                let resp = serve_html_shell()
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
  }

  let assert Ok(_) =
    mist.new(handler)
    |> mist.port(8080)
    |> mist.start
  process.sleep_forever()
}

fn serve_html_shell() -> Response(ResponseData) {
  let html =
    "<!DOCTYPE html>
<html>
<head>
  <meta charset='utf-8'>
  <meta name='viewport' content='width=device-width, initial-scale=1.0'>
  <title>Conduit</title>
  <link href='https://code.ionicframework.com/ionicons/2.0.1/css/ionicons.min.css' rel='stylesheet' type='text/css'>
  <link href='https://fonts.googleapis.com/css?family=Titillium+Web:700|Source+Serif+Pro:400,700|Merriweather+Sans:400,700|Source+Sans+Pro:400,300,600,700,300italic,400italic,600italic,700italic' rel='stylesheet' type='text/css'>
  <link rel='stylesheet' href='https://demo.productionready.io/main.css'>
</head>
<body>
  <div id='app'></div>
  <script type='module' src='/_build/client/generated/app.mjs'></script>
</body>
</html>"
  response.new(200)
  |> response.set_header("content-type", "text/html")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(html)))
}

fn serve_static(path: String) -> Response(ResponseData) {
  let file_path = client_build_root <> "/" <> path
  case string.contains(path, "..") {
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
