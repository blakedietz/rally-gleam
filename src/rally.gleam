import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import libero
import libero/scanner as libero_scanner
import rally/dependency_resolver
import rally/format
import rally/generator
import rally/generator/client
import rally/generator/codec
import rally/generator/http_handler
import rally/generator/ssr_handler
import rally/generator/ws_handler
import rally/parser
import rally/scanner
import rally/tree_shaker
import rally/types.{type ScanConfig, ScanConfig}
import simplifile
import tom

pub fn main() {
  case run() {
    Ok(msg) -> io.println("rally: " <> msg)
    Error(msg) -> {
      io.println_error("rally error: " <> msg)
      halt(1)
    }
  }
}

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

fn read_config() -> Result(ScanConfig, String) {
  use toml_str <- result.try(
    simplifile.read("gleam.toml")
    |> result.map_error(fn(e) {
      "Cannot read gleam.toml: " <> string.inspect(e)
    }),
  )
  use toml_map <- result.try(
    tom.parse(toml_str)
    |> result.map_error(fn(e) { "Invalid gleam.toml: " <> string.inspect(e) }),
  )

  let rally_config =
    tom.get_table(toml_map, ["tools", "rally"])
    |> result.unwrap(dict.new())

  let pages_root =
    tom.get_string(rally_config, ["pages_root"])
    |> result.unwrap("src/pages")
  let output_route =
    tom.get_string(rally_config, ["output_route"])
    |> result.unwrap("src/generated/router.gleam")
  let output_dispatch =
    tom.get_string(rally_config, ["output_dispatch"])
    |> result.unwrap("src/generated/page_dispatch.gleam")
  let output_server_dispatch =
    tom.get_string(rally_config, ["output_server_dispatch"])
    |> result.unwrap("src/generated/rpc_dispatch.gleam")
  let output_server_atoms =
    tom.get_string(rally_config, ["output_server_atoms"])
    |> result.unwrap("src/generated@rpc_atoms.erl")
  let atoms_module = "generated@rpc_atoms"
  let output_ssr =
    tom.get_string(rally_config, ["output_ssr"])
    |> result.unwrap("src/generated/ssr_handler.gleam")
  let output_ws =
    tom.get_string(rally_config, ["output_ws"])
    |> result.unwrap("src/generated/ws_handler.gleam")
  let output_http =
    tom.get_string(rally_config, ["output_http"])
    |> result.unwrap("src/generated/http_handler.gleam")
  let client_root =
    tom.get_string(rally_config, ["client_root"])
    |> result.unwrap("client")
  let server_deps =
    tom.get_table(toml_map, ["dependencies"])
    |> result.unwrap(dict.new())

  let rally_package_path = {
    case dict.get(server_deps, "rally") {
      Ok(tom.InlineTable(rally_dep)) | Ok(tom.Table(rally_dep)) ->
        case dict.get(rally_dep, "path") {
          Ok(tom.String(path)) -> path
          _ -> ".."
        }
      _ -> ".."
    }
  }

  let shell_file =
    tom.get_string(rally_config, ["shell_file"])
    |> result.unwrap("src/shell.html")

  Ok(ScanConfig(
    pages_root:,
    output_route:,
    output_dispatch:,
    output_server_dispatch:,
    output_server_atoms:,
    atoms_module:,
    output_ssr:,
    output_ws:,
    output_http:,
    client_root:,
    rally_package_path:,
    shell_file:,
    server_deps:,
  ))
}

fn run() -> Result(String, String) {
  use config <- result.try(read_config())

  // 1. Scan pages directory
  use routes <- result.try(scanner.scan(config))

  // 1b. Scan for server_ handler endpoints via libero
  let handler_endpoints = case libero.scan() {
    Ok(endpoints) -> {
      case endpoints {
        [] -> Nil
        _ ->
          io.println(
            "rally: discovered "
            <> int.to_string(list.length(endpoints))
            <> " handler endpoints via libero",
          )
      }
      endpoints
    }
    Error(errors) -> {
      list.each(errors, fn(e) {
        io.println_error("rally: libero scanner error: " <> string.inspect(e))
      })
      []
    }
  }

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
          case parser.parse_page(source, module_path: route.module_path) {
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
          io.println_error("warning: cannot read " <> file_path <> ", skipping")
          Error(Nil)
        }
      }
    })

  // 3. Generate route type + page dispatch (existing)
  let route_source = generator.generate(routes)
  use _ <- result.try(write_file(config.output_route, route_source))
  let dispatch_source = generator.generate_dispatch(routes)
  use _ <- result.try(write_file(config.output_dispatch, dispatch_source))

  // 4. Detect client_context.gleam and server_context.gleam
  let client_context_path =
    dirname(config.pages_root) <> "/client_context.gleam"
  let has_client_context =
    simplifile.is_file(client_context_path) |> result.unwrap(False)
  let server_context_path =
    dirname(config.pages_root) <> "/server_context.gleam"
  let has_from_session = case simplifile.read(server_context_path) {
    Ok(source) -> string.contains(source, "pub fn from_session")
    Error(_) -> False
  }

  // 5. Generate RPC dispatch via libero
  let sd_source =
    libero.generate_dispatch(
      handler_endpoints,
      option.Some(config.atoms_module),
    )
  use _ <- result.try(write_file(config.output_server_dispatch, sd_source))

  // 5b. Generate and write the atoms pre-registration file
  let atoms_erl = libero.generate_atoms(handler_endpoints, config.atoms_module)
  use _ <- result.try(write_file(config.output_server_atoms, atoms_erl))

  // 6. Generate SSR handler
  let shell_html = case simplifile.read(config.shell_file) {
    Ok(html) -> html
    Error(_) ->
      "<!DOCTYPE html>\n<html>\n<head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1.0'></head>\n<body><div id='app'></div><script type='module' src='/_build/client/generated/app.mjs'></script></body>\n</html>"
  }
  let ssr_source =
    ssr_handler.generate(
      contracts,
      has_client_context,
      has_from_session,
      shell_html,
    )
  use _ <- result.try(write_file(config.output_ssr, ssr_source))

  // 6. Generate WebSocket handler
  let ws_source = ws_handler.generate(contracts, config.atoms_module)
  use _ <- result.try(write_file(config.output_ws, ws_source))

  // 6b. Generate HTTP handler (for non-WebSocket RPC clients)
  case handler_endpoints {
    [] -> Nil
    _ -> {
      let http_source = http_handler.generate(handler_endpoints)
      let _ = write_file(config.output_http, http_source)
      Nil
    }
  }

  // 7. Read JS runtime files from the Rally package
  let rpc_ffi_path =
    config.rally_package_path <> "/src/rally_runtime/rpc_ffi.mjs"
  use rpc_ffi_content <- result.try(
    simplifile.read(rpc_ffi_path)
    |> result.map_error(fn(e) {
      "Cannot read rpc_ffi.mjs from rally package at "
      <> rpc_ffi_path
      <> ": "
      <> string.inspect(e)
    }),
  )
  let decoders_prelude_path =
    config.rally_package_path <> "/src/rally_runtime/decoders_prelude.mjs"
  use decoders_prelude_content <- result.try(
    simplifile.read(decoders_prelude_path)
    |> result.map_error(fn(e) {
      "Cannot read decoders_prelude.mjs from rally package at "
      <> decoders_prelude_path
      <> ": "
      <> string.inspect(e)
    }),
  )

  // 8. Walk type graph for codec generation.
  // Seeds come from handler endpoint params/return types discovered by libero.
  let seeds = libero.collect_seeds(handler_endpoints)
  let discovered = case libero.walk(seeds) {
    Ok(types) -> types
    Error(errors) -> {
      list.each(errors, fn(e) {
        io.println_error("rally: walker error: " <> string.inspect(e))
      })
      []
    }
  }

  let server_symbols = collect_server_symbols(handler_endpoints)

  // 10. Generate codec files and per-page client modules
  let client_context_source = case has_client_context {
    True ->
      case simplifile.read(client_context_path) {
        Ok(source) -> option.Some(source)
        Error(_) -> option.None
      }
    False -> option.None
  }
  let raw_codec_files =
    codec.generate(
      contracts,
      discovered,
      client_context_source,
      handler_endpoints,
      server_symbols,
    )
  let codec_files =
    list.map(raw_codec_files, fn(f: codec.CodecFile) {
      client.GeneratedFile(config.client_root <> "/" <> f.path, f.content)
    })

  // 11. Generate client package (includes rpc_ffi.mjs and decoders_prelude.mjs)
  let client_files =
    client.generate_package(
      routes,
      contracts,
      config,
      config.server_deps,
      rpc_ffi_content,
      decoders_prelude_content,
      has_client_context,
    )
  let client_context_files = case has_client_context {
    True -> {
      let assert Ok(cc_source) = simplifile.read(client_context_path)
      let shaken = tree_shaker.shake(cc_source, server_symbols:)
      let ffi_path =
        dirname(config.pages_root) <> "/client_context_ffi.mjs"
      let ffi_files = case simplifile.read(ffi_path) {
        Ok(ffi_content) -> [
          client.GeneratedFile(
            config.client_root <> "/src/client_context_ffi.mjs",
            ffi_content,
          ),
        ]
        Error(_) -> []
      }
      [
        client.GeneratedFile(
          config.client_root <> "/src/client_context.gleam",
          shaken,
        ),
        ..ffi_files
      ]
    }
    False -> []
  }

  // Copy layout modules to client package (tree-shaken)
  let layout_files = copy_layout_modules(routes, config, server_symbols)

  // 12. Resolve transitive local dependencies from client sources
  let seed_sources =
    list.flatten([
      raw_codec_files
        |> list.filter(fn(f: codec.CodecFile) {
          string.ends_with(f.path, ".gleam")
          && string.starts_with(f.path, "src/pages/")
        })
        |> list.map(fn(f: codec.CodecFile) {
          let module_path =
            f.path
            |> string.drop_start(4)
            |> string.drop_end(6)
          #(module_path, f.content)
        }),
      layout_files
        |> list.filter(fn(f: client.GeneratedFile) {
          string.ends_with(f.path, ".gleam")
        })
        |> list.map(fn(f: client.GeneratedFile) {
          let module_path =
            f.path
            |> string.replace(config.client_root <> "/src/", "")
            |> string.drop_end(6)
          #(module_path, f.content)
        }),
      client_context_files
        |> list.map(fn(f: client.GeneratedFile) {
          #("client_context", f.content)
        }),
    ])

  use dependency_files <- result.try(
    dependency_resolver.resolve(
      seed_sources:,
      src_root: dirname(config.pages_root),
      client_root: config.client_root,
    ),
  )

  use _ <- result.try(
    write_generated_files(
      list.flatten([
        codec_files,
        client_files,
        client_context_files,
        layout_files,
        dependency_files,
      ]),
    ),
  )

  Ok(int.to_string(list.length(routes)) <> " routes")
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
  write_if_changed(path, formatted)
}

fn write_generated_files(
  files: List(client.GeneratedFile),
) -> Result(Nil, String) {
  list.try_fold(files, Nil, fn(_, file) {
    let formatted = case string.ends_with(file.path, ".gleam") {
      True -> format.format_gleam(file.content)
      False -> file.content
    }
    write_if_changed(file.path, formatted)
  })
}

fn write_if_changed(path: String, content: String) -> Result(Nil, String) {
  case simplifile.read(path) {
    Ok(existing) if existing == content -> Ok(Nil)
    _ -> {
      let _ = simplifile.create_directory_all(dirname(path))
      simplifile.write(path, content)
      |> result.map_error(fn(e) {
        "Failed to write " <> path <> ": " <> string.inspect(e)
      })
    }
  }
}

fn dirname(path: String) -> String {
  case string.split(path, "/") |> list.reverse {
    [_last, ..rest] -> string.join(list.reverse(rest), "/")
    [] -> "."
  }
}

fn copy_layout_modules(
  routes: List(types.ScannedRoute),
  config: ScanConfig,
  server_symbols: List(String),
) -> List(client.GeneratedFile) {
  routes
  |> list.filter_map(fn(route) {
    case route.layout_module {
      option.Some(layout_module) -> Ok(layout_module)
      option.None -> Error(Nil)
    }
  })
  |> list.unique
  |> list.filter_map(fn(layout_module) {
    let file_path =
      config.pages_root <> "/" <> last_module_segment(layout_module) <> ".gleam"
    case simplifile.read(file_path) {
      Ok(source) -> {
        let shaken = tree_shaker.shake(source, server_symbols:)
        let dest = config.client_root <> "/src/" <> layout_module <> ".gleam"
        Ok(client.GeneratedFile(dest, shaken))
      }
      Error(_) -> Error(Nil)
    }
  })
}

fn collect_server_symbols(
  endpoints: List(libero_scanner.HandlerEndpoint),
) -> List(String) {
  let handler_type_names =
    list.filter_map(endpoints, fn(e) {
      case e.msg_type_name {
        option.Some(name) -> Ok(name)
        option.None -> Error(Nil)
      }
    })
  ["ServerContext", ..handler_type_names]
}
