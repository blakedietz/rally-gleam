import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import tom
import simplifile
import lando/format
import lando/generator
import lando/generator/client
import lando/generator/server_dispatch
import lando/generator/ssr_handler
import lando/parser
import lando/scanner
import lando/types.{type ScanConfig, ScanConfig}

pub fn main() {
  case run() {
    Ok(count) ->
      io.println(
        "lando: generated route.gleam + page_dispatch.gleam + server_dispatch.gleam + ssr_handler.gleam + client package with "
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

  // 1. Scan pages directory
  use routes <- result.try(scanner.scan(config))

  // 2. Parse each page module for its contract
  let contracts =
    list.filter_map(routes, fn(route) {
      // Derive the file path from the module path
      let file_path =
        config.pages_root
        <> "/"
        <> last_module_segment(route.module_path)
        <> ".gleam"
      case simplifile.read(file_path) {
        Ok(source) -> {
          case parser.parse_page(source) {
            Ok(contract) -> Ok(#(route, contract))
            Error(_) -> Error(Nil)
          }
        }
        Error(_) -> Error(Nil)
      }
    })

  // 3. Generate route type + page dispatch (existing)
  let route_source = generator.generate(routes)
  use _ <- result.try(write_file(config.output_route, route_source))
  let dispatch_source = generator.generate_dispatch(routes)
  use _ <- result.try(write_file(config.output_dispatch, dispatch_source))

  // 4. Generate server dispatch
  let sd_source = server_dispatch.generate(contracts)
  use _ <- result.try(write_file(config.output_server_dispatch, sd_source))

  // 5. Generate SSR handler
  let ssr_source = ssr_handler.generate(contracts)
  use _ <- result.try(write_file(config.output_ssr, ssr_source))

  // 6. Generate client package
  let client_files = client.generate_package(routes, contracts, config)
  use _ <- result.try(write_generated_files(client_files))

  Ok(list.length(routes))
}

/// Extract the last path segment of a module path for file lookup.
/// "admin/pages/settings/general" -> "settings/general"
fn last_module_segment(module_path: String) -> String {
  case string.split_once(module_path, "pages/") {
    Ok(#(_, rest)) -> rest
    Error(_) -> module_path
  }
}

fn write_file(path: String, content: String) -> Result(Nil, String) {
  let formatted = case string.ends_with(path, ".gleam") {
    True -> format.format_gleam(content)
    False -> content
  }
  let _ = simplifile.create_directory_all(dirname(path))
  simplifile.write(path, formatted)
  |> result.map_error(fn(e) {
    "Failed to write " <> path <> ": " <> string.inspect(e)
  })
}

fn write_generated_files(
  files: List(client.GeneratedFile),
) -> Result(Nil, String) {
  list.try_fold(files, Nil, fn(_, file) {
    let formatted = case string.ends_with(file.path, ".gleam") {
      True -> format.format_gleam(file.content)
      False -> file.content
    }
    let _ = simplifile.create_directory_all(dirname(file.path))
    simplifile.write(file.path, formatted)
    |> result.map_error(fn(e) {
      "Failed to write " <> file.path <> ": " <> string.inspect(e)
    })
  })
}

fn dirname(path: String) -> String {
  case string.split(path, "/") |> list.reverse {
    [_last, ..rest] -> string.join(list.reverse(rest), "/")
    [] -> "."
  }
}
