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
import lando/generator/codec
import lando/generator/server_dispatch
import lando/generator/ssr_handler
import lando/generator/ws_handler
import lando/field_type
import lando/parser
import lando/scanner
import lando/types.{type PageContract, type ScanConfig, type ScannedRoute, type VariantInfo, ScanConfig}
import lando/walker

pub fn main() {
  case run() {
    Ok(msg) -> io.println("lando: " <> msg)
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
    |> result.unwrap("src/pages")
  let output_route =
    tom.get_string(lando_config, ["output_route"])
    |> result.unwrap("src/generated/router.gleam")
  let output_dispatch =
    tom.get_string(lando_config, ["output_dispatch"])
    |> result.unwrap("src/generated/page_dispatch.gleam")
  let output_server_dispatch =
    tom.get_string(lando_config, ["output_server_dispatch"])
    |> result.unwrap("src/generated/server_dispatch.gleam")
  let output_ssr =
    tom.get_string(lando_config, ["output_ssr"])
    |> result.unwrap("src/generated/ssr_handler.gleam")
  let output_ws =
    tom.get_string(lando_config, ["output_ws"])
    |> result.unwrap("src/generated/ws_handler.gleam")
  let sql_dir =
    tom.get_string(lando_config, ["sql_dir"])
    |> result.unwrap("src/sql")
  let client_root =
    tom.get_string(lando_config, ["client_root"])
    |> result.unwrap("client")
  let lando_package_path = {
    case tom.get_table(toml_map, ["dependencies"]) {
      Ok(deps) ->
        case tom.get_table(deps, ["lando"]) {
          Ok(lando_dep) ->
            tom.get_string(lando_dep, ["path"])
            |> result.unwrap("..")
          Error(_) -> ".."
        }
      Error(_) -> ".."
    }
  }

  Ok(ScanConfig(
    pages_root:,
    output_route:,
    output_dispatch:,
    output_server_dispatch:,
    output_ssr:,
    output_ws:,
    sql_dir:,
    client_root:,
    lando_package_path:,
  ))
}

fn run() -> Result(String, String) {
  use config <- result.try(read_config())

  // 1. Scan pages directory
  use routes <- result.try(scanner.scan(config))

  // 2. Parse each page module for its contract
  let contracts =
    list.filter_map(routes, fn(route) {
      let file_path =
        config.pages_root
        <> "/"
        <> last_module_segment(route.module_path)
        <> ".gleam"
      case simplifile.read(file_path) {
        Ok(source) -> {
          case parser.parse_page(source) {
            Ok(contract) -> Ok(#(route, contract))
            Error(_) -> {
              io.println_error(
                "warning: failed to parse " <> file_path <> ", skipping",
              )
              Error(Nil)
            }
          }
        }
        Error(_) -> {
          io.println_error(
            "warning: cannot read " <> file_path <> ", skipping",
          )
          Error(Nil)
        }
      }
    })

  // 3. Generate route type + page dispatch (existing)
  let route_source = generator.generate(routes)
  use _ <- result.try(write_file(config.output_route, route_source))
  let dispatch_source = generator.generate_dispatch(routes)
  use _ <- result.try(write_file(config.output_dispatch, dispatch_source))

  // 4. Detect client_context.gleam (needed by SSR handler and client codegen)
  let client_context_path = dirname(config.pages_root) <> "/client_context.gleam"
  let has_client_context = case simplifile.read(client_context_path) {
    Ok(_) -> True
    Error(_) -> False
  }

  // 5. Generate server dispatch
  let sd_source = server_dispatch.generate(contracts)
  use _ <- result.try(write_file(config.output_server_dispatch, sd_source))

  // 6. Generate SSR handler
  let ssr_source = ssr_handler.generate(contracts, has_client_context)
  use _ <- result.try(write_file(config.output_ssr, ssr_source))

  // 6. Generate WebSocket handler
  let ws_source = ws_handler.generate(contracts)
  use _ <- result.try(write_file(config.output_ws, ws_source))

  // 7. Read JS runtime files from the lando package
  let rpc_ffi_path =
    config.lando_package_path <> "/src/lando_runtime/rpc_ffi.mjs"
  use rpc_ffi_content <- result.try(
    simplifile.read(rpc_ffi_path)
    |> result.map_error(fn(e) {
      "Cannot read rpc_ffi.mjs from lando package at "
      <> rpc_ffi_path
      <> ": "
      <> string.inspect(e)
    }),
  )
  let decoders_prelude_path =
    config.lando_package_path <> "/src/lando_runtime/decoders_prelude.mjs"
  use decoders_prelude_content <- result.try(
    simplifile.read(decoders_prelude_path)
    |> result.map_error(fn(e) {
      "Cannot read decoders_prelude.mjs from lando package at "
      <> decoders_prelude_path
      <> ": "
      <> string.inspect(e)
    }),
  )

  // 8. Walk type graph for codec generation
  let seeds = collect_codec_seeds(contracts)
  let page_file_paths =
    list.map(routes, fn(r) {
      config.pages_root
      <> "/"
      <> last_module_segment(r.module_path)
      <> ".gleam"
    })
  let discovered =
    walker.walk(seeds, page_file_paths, config.pages_root)

  // 10. Generate codec files for the client package
  let codec_files =
    list.map(codec.generate(contracts, discovered, has_client_context), fn(f: codec.CodecFile) {
      client.GeneratedFile(config.client_root <> "/" <> f.path, f.content)
    })

  // 11. Generate client package (includes rpc_ffi.mjs and decoders_prelude.mjs)
  let client_files =
    client.generate_package(routes, contracts, config, rpc_ffi_content, decoders_prelude_content, has_client_context)
  let client_context_files = case has_client_context {
    True -> {
      let assert Ok(cc_source) = simplifile.read(client_context_path)
      [client.GeneratedFile(config.client_root <> "/src/client_context.gleam", cc_source)]
    }
    False -> []
  }
  use _ <- result.try(write_generated_files(
    list.flatten([codec_files, client_files, client_context_files]),
  ))

  // 11. Run marmot for SQL query generation
  let sql_count = run_marmot(config.sql_dir)

  Ok(
    int.to_string(list.length(routes))
    <> " routes"
    <> case sql_count {
      0 -> ""
      n -> ", " <> int.to_string(n) <> " SQL queries"
    },
  )
}

/// Collect (module_path, type_name) seed pairs from all page contracts.
/// Walks the field types of ToServer/ToClient variants to find
/// user-defined types that need decoder generation.
fn collect_codec_seeds(
  contracts: List(#(ScannedRoute, PageContract)),
) -> List(#(String, String)) {
  contracts
  |> list.flat_map(fn(pair) {
    let #(_, contract) = pair
    let to_server_types =
      list.flat_map(contract.to_server_variants, collect_variant_user_types)
    let to_client_types =
      list.flat_map(contract.to_client_variants, collect_variant_user_types)
    list.append(to_server_types, to_client_types)
  })
}

fn collect_variant_user_types(v: VariantInfo) -> List(#(String, String)) {
  list.flat_map(v.fields, fn(f) { field_type.collect_user_types(f.type_) })
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

/// Scan a directory for .sql files and shell out to marmot if any are found.
/// Returns the number of SQL files found.
fn run_marmot(sql_dir: String) -> Int {
  let sql_files = scan_sql_dir(sql_dir)
  case sql_files {
    [] -> 0
    files -> {
      let _ = run_executable("gleam", ["run", "-m", "marmot"])
      list.length(files)
    }
  }
}

fn scan_sql_dir(dir: String) -> List(String) {
  case simplifile.read_directory(at: dir) {
    Ok(entries) -> {
      entries
      |> list.sort(string.compare)
      |> list.filter(fn(entry) { string.ends_with(entry, ".sql") })
    }
    Error(_) -> []
  }
}

@external(erlang, "lando_cli_ffi", "run_executable")
fn run_executable(program: String, args: List(String)) -> Int
