import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import tom
import simplifile
import lando/generator
import lando/scanner
import lando/types.{type ScanConfig, ScanConfig}

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

fn read_config() -> Result(ScanConfig, String) {
  use toml_str <- result.try(
    simplifile.read("gleam.toml")
    |> result.map_error(fn(e) { "Cannot read gleam.toml: " <> string.inspect(e) })
  )
  use toml_map <- result.try(
    tom.parse(toml_str)
    |> result.map_error(fn(e) { "Invalid gleam.toml: " <> string.inspect(e) })
  )

  let lando_config =
    tom.get_table(toml_map, ["tools", "lando"])
    |> result.unwrap(dict.new())

  let pages_root =
    tom.get_string(lando_config, ["pages_root"])
    |> result.unwrap("../../clients/admin/src/admin/pages")
  let output_route =
    tom.get_string(lando_config, ["output_route"])
    |> result.unwrap("../../shared/src/shared/admin/route.gleam")
  let output_dispatch =
    tom.get_string(lando_config, ["output_dispatch"])
    |> result.unwrap("../../clients/admin/src/generated/page_dispatch.gleam")
  let output_server_dispatch =
    tom.get_string(lando_config, ["output_server_dispatch"])
    |> result.unwrap("src/generated/server_dispatch.gleam")
  let output_ssr =
    tom.get_string(lando_config, ["output_ssr"])
    |> result.unwrap("src/generated/ssr_handler.gleam")
  let client_root =
    tom.get_string(lando_config, ["client_root"])
    |> result.unwrap("client")

  Ok(ScanConfig(
    pages_root:,
    output_route:,
    output_dispatch:,
    output_server_dispatch:,
    output_ssr:,
    client_root:,
  ))
}

fn run() -> Result(Int, String) {
  use config <- result.try(read_config())
  use routes <- result.try(scanner.scan(config))
  let route_source = generator.generate(routes)
  use _ <- result.try(write_file(config.output_route, route_source))
  let dispatch_source = generator.generate_dispatch(routes)
  use _ <- result.try(write_file(config.output_dispatch, dispatch_source))
  Ok(list.length(routes))
}

fn write_file(path: String, content: String) -> Result(Nil, String) {
  simplifile.write(path, content)
  |> result.map_error(fn(e) {
    "Failed to write " <> path <> ": " <> string.inspect(e)
  })
}
