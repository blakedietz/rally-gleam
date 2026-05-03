import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import simplifile
import lando/generator
import lando/scanner

const scanner_root = "../../clients/admin/src/admin/pages"

const output_path = "../../shared/src/shared/admin/route.gleam"

const dispatch_output_path = "../../clients/admin/src/generated/page_dispatch.gleam"

pub fn main() {
  case run() {
    Ok(count) ->
      io.println(
        "lando: generated route.gleam + page_dispatch.gleam with "
        <> int.to_string(count)
        <> " routes",
      )
    Error(msg) -> {
      io.println_error("lando error: " <> msg)
      halt(1)
    }
  }
}

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

fn run() -> Result(Int, String) {
  use routes <- result.try(scanner.scan(scanner_root))
  let route_source = generator.generate(routes)
  use _ <- result.try(write_file(output_path, route_source))
  let dispatch_source = generator.generate_dispatch(routes)
  use _ <- result.try(write_file(dispatch_output_path, dispatch_source))
  Ok(list.length(routes))
}

fn write_file(path: String, content: String) -> Result(Nil, String) {
  simplifile.write(path, content)
  |> result.map_error(fn(e) {
    "Failed to write " <> path <> ": " <> string.inspect(e)
  })
}
