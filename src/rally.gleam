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

fn read_configs() -> Result(List(ScanConfig), String) {
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

  case tom.get_array(rally_config, ["clients"]) {
    Ok(clients) -> {
      use configs <- result.try(
        list.try_map(clients, fn(client) {
          case client {
            tom.Table(client_config) | tom.InlineTable(client_config) ->
              read_client_config(client_config, server_deps, rally_package_path)
            _ -> Error("Each [[tools.rally.clients]] entry must be a table")
          }
        }),
      )
      case configs {
        [] ->
          Ok([read_legacy_config(rally_config, server_deps, rally_package_path)])
        _ -> Ok(configs)
      }
    }
    Error(_) ->
      Ok([read_legacy_config(rally_config, server_deps, rally_package_path)])
  }
}

fn read_client_config(
  client_config: dict.Dict(String, tom.Toml),
  server_deps: dict.Dict(String, tom.Toml),
  rally_package_path: String,
) -> Result(ScanConfig, String) {
  use namespace <- result.try(
    tom.get_string(client_config, ["namespace"])
    |> result.map_error(fn(_) {
      "Each [[tools.rally.clients]] entry needs namespace = \"...\""
    }),
  )
  let route_root =
    tom.get_string(client_config, ["route_root"])
    |> result.unwrap("/" <> namespace)
  Ok(ScanConfig(
    pages_root: "src/" <> namespace <> "/pages",
    output_route: "src/generated/" <> namespace <> "/router.gleam",
    output_dispatch: "src/generated/" <> namespace <> "/page_dispatch.gleam",
    output_server_dispatch: "src/generated/"
      <> namespace
      <> "/rpc_dispatch.gleam",
    output_server_atoms: "src/generated@" <> namespace <> "@rpc_atoms.erl",
    atoms_module: "generated@" <> namespace <> "@rpc_atoms",
    output_ssr: "src/generated/" <> namespace <> "/ssr_handler.gleam",
    output_ws: "src/generated/" <> namespace <> "/ws_handler.gleam",
    output_http: "src/generated/" <> namespace <> "/http_handler.gleam",
    client_root: ".generated_client/" <> namespace,
    route_root:,
    rally_package_path:,
    shell_file: "src/" <> namespace <> "/shell.html",
    server_deps:,
  ))
}

fn read_legacy_config(
  rally_config: dict.Dict(String, tom.Toml),
  server_deps: dict.Dict(String, tom.Toml),
  rally_package_path: String,
) -> ScanConfig {
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
    |> result.unwrap(".generated_client")
  let route_root =
    tom.get_string(rally_config, ["route_root"])
    |> result.unwrap("/")

  let shell_file =
    tom.get_string(rally_config, ["shell_file"])
    |> result.unwrap("src/shell.html")

  ScanConfig(
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
    route_root:,
    rally_package_path:,
    shell_file:,
    server_deps:,
  )
}

fn run() -> Result(String, String) {
  use configs <- result.try(read_configs())
  use Nil <- result.try(list.try_each(configs, generate_for_config))
  Ok(int.to_string(list.length(configs)) <> " client(s)")
}

fn generate_for_config(config: ScanConfig) -> Result(Nil, String) {
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

  // 3. Detect client_context.gleam and server_context.gleam
  let client_context_path =
    dirname(config.pages_root) <> "/client_context.gleam"
  let client_context_module = module_from_src_path(client_context_path)
  let has_client_context =
    simplifile.is_file(client_context_path) |> result.unwrap(False)
  let server_context_path = "src/server_context.gleam"
  let client_context_server_path =
    dirname(config.pages_root) <> "/client_context_server.gleam"
  let client_context_server_module =
    module_from_src_path(client_context_server_path)
  let #(has_from_session, from_session_module) = case
    simplifile.read(client_context_server_path)
  {
    Ok(source) ->
      case string.contains(source, "pub fn from_session") {
        True -> #(True, client_context_server_module)
        False -> check_server_context_from_session(server_context_path)
      }
    _ -> check_server_context_from_session(server_context_path)
  }
  let router_module = module_from_src_path(config.output_route)
  let rpc_dispatch_module = module_from_src_path(config.output_server_dispatch)

  // 4. Generate route type + page dispatch
  let route_source = generator.generate(routes)
  use _ <- result.try(write_file(config.output_route, route_source))
  let dispatch_source =
    generator.generate_dispatch(
      routes,
      contracts,
      has_client_context,
      router_module,
      client_context_module,
    )
  use _ <- result.try(write_file(config.output_dispatch, dispatch_source))

  // 5. Generate RPC dispatch via libero
  let sd_source = case handler_endpoints {
    [] -> generator.generate_empty_rpc_dispatch(config.atoms_module)
    _ ->
      libero.generate_dispatch(
        handler_endpoints,
        option.Some(config.atoms_module),
      )
  }
  let sd_source =
    sd_source
    |> generator.normalize_rpc_dispatch_context_import
    |> generator.normalize_rpc_dispatch_unused_fields
  use _ <- result.try(write_file(config.output_server_dispatch, sd_source))

  // 6. Generate SSR handler
  let shell_html = case simplifile.read(config.shell_file) {
    Ok(html) -> html
    Error(_) ->
      "<!DOCTYPE html>\n<html>\n<head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1.0'></head>\n<body><div id='app'></div><script type='module' src='/client.js'></script></body>\n</html>"
  }
  let ssr_source =
    ssr_handler.generate(
      contracts,
      has_client_context,
      has_from_session,
      from_session_module,
      router_module,
      shell_html,
      config.atoms_module,
    )
  use _ <- result.try(write_file(config.output_ssr, ssr_source))

  // 6. Generate WebSocket handler
  let ws_source =
    ws_handler.generate(contracts, config.atoms_module, rpc_dispatch_module)
  use _ <- result.try(write_file(config.output_ws, ws_source))

  // 6b. Generate HTTP handler (for non-WebSocket RPC clients)
  use _ <- result.try(case handler_endpoints {
    [] -> Ok(Nil)
    _ -> {
      let http_source =
        http_handler.generate(handler_endpoints, rpc_dispatch_module)
      write_file(config.output_http, http_source)
    }
  })

  // 7. Read rally transport JS runtime from the Rally package.
  // ETF codec files (rpc_ffi.mjs, decoders_prelude.mjs) come from
  // libero as a proper JS dependency of the generated client.
  let transport_ffi_path =
    config.rally_package_path <> "/src/rally_runtime/transport_ffi.mjs"
  use transport_ffi_content <- result.try(
    simplifile.read(transport_ffi_path)
    |> result.map_error(fn(e) {
      "Cannot read transport_ffi.mjs from rally package at "
      <> transport_ffi_path
      <> ": "
      <> string.inspect(e)
    }),
  )

  // 8. Walk type graph for codec generation.
  // Seeds come from handler endpoint params/return types AND
  // ClientContext types so the walker resolves field types properly.
  let client_context_source = case has_client_context {
    True ->
      case simplifile.read(client_context_path) {
        Ok(source) -> option.Some(source)
        Error(_) -> option.None
      }
    False -> option.None
  }
  let handler_seeds = libero.collect_seeds(handler_endpoints)
  let cc_seeds = case client_context_source {
    option.Some(source) ->
      codec.client_context_seeds(source, client_context_module)
    option.None -> []
  }
  let seeds = list.append(handler_seeds, cc_seeds)
  let discovered = case libero.walk(seeds) {
    Ok(types) -> types
    Error(errors) -> {
      list.each(errors, fn(e) {
        io.println_error("rally: walker error: " <> string.inspect(e))
      })
      []
    }
  }

  // 8b. Generate and write the atoms pre-registration file
  let atoms_erl =
    libero.generate_atoms(handler_endpoints, discovered, config.atoms_module)
  use _ <- result.try(write_file(config.output_server_atoms, atoms_erl))

  let server_symbols = collect_server_symbols(handler_endpoints)

  // 10. Generate codec files and per-page client modules
  use client_context_contract <- result.try(case client_context_source {
    option.Some(source) ->
      parser.parse_client_context(source)
      |> result.map(option.Some)
      |> result.map_error(fn(error) {
        "Cannot parse client_context.gleam: " <> error
      })
    option.None -> Ok(option.None)
  })
  let raw_codec_files =
    codec.generate(
      contracts,
      discovered,
      handler_endpoints,
      server_symbols,
    )
  let codec_files =
    list.map(raw_codec_files, fn(f: codec.CodecFile) {
      client.GeneratedFile(config.client_root <> "/" <> f.path, f.content)
    })

  // 11. Generate client package
  let client_files =
    client.generate_package_with_client_context_contract(
      routes,
      contracts,
      config,
      config.server_deps,
      transport_ffi_content,
      client_context_contract,
      client_context_module,
    )
  let client_context_files = case has_client_context {
    True -> {
      let assert Ok(cc_source) = simplifile.read(client_context_path)
      let shaken = tree_shaker.shake(cc_source, server_symbols:)
      let ffi_path = dirname(config.pages_root) <> "/client_context_ffi.mjs"
      let ffi_files = case simplifile.read(ffi_path) {
        Ok(ffi_content) -> [
          client.GeneratedFile(
            config.client_root <> "/src/" <> client_context_module <> "_ffi.mjs",
            ffi_content,
          ),
        ]
        Error(_) -> []
      }
      [
        client.GeneratedFile(
          config.client_root <> "/src/" <> client_context_module <> ".gleam",
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
          && string.starts_with(f.path, "src/")
          && string.contains(f.path, "/pages/")
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
          #(client_context_module, f.content)
        }),
    ])

  use dependency_files <- result.try(dependency_resolver.resolve(
    seed_sources:,
    src_root: source_root_for_pages(config.pages_root),
    client_root: config.client_root,
  ))

  reset_generated_client_src(config.client_root)

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

  // Clean up empty generated modules
  case simplifile.read(config.output_dispatch) {
    Ok(content) ->
      case
        !string.contains(content, "pub fn")
        && !string.contains(content, "pub type")
        && !string.contains(content, "pub const")
      {
        True -> {
          let _ = simplifile.delete(config.output_dispatch)
          Nil
        }
        False -> Nil
      }
    Error(_) -> Nil
  }

  Ok(Nil)
}

fn reset_generated_client_src(client_root: String) -> Nil {
  let _ = simplifile.delete_all(paths: [client_root <> "/src"])
  Nil
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
      use _ <- result.try(
        simplifile.create_directory_all(dirname(path))
        |> result.map_error(fn(e) {
          "Failed to create directory for " <> path <> ": " <> string.inspect(e)
        }),
      )
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

fn module_from_src_path(path: String) -> String {
  path
  |> string.drop_start(4)
  |> string.drop_end(6)
}

fn source_root_for_pages(pages_root: String) -> String {
  let parts = string.split(pages_root, "/")
  case split_before_pages(parts, []) {
    Ok(prefix_parts) ->
      case take_through_src(prefix_parts, []) {
        Ok(src_parts) -> string.join(src_parts, "/")
        Error(_) -> dirname(pages_root)
      }
    Error(_) -> dirname(pages_root)
  }
}

fn split_before_pages(
  parts: List(String),
  acc: List(String),
) -> Result(List(String), Nil) {
  case parts {
    [] -> Error(Nil)
    ["pages", ..] -> Ok(acc)
    [part, ..rest] -> split_before_pages(rest, list.append(acc, [part]))
  }
}

fn take_through_src(
  parts: List(String),
  acc: List(String),
) -> Result(List(String), Nil) {
  case parts {
    [] -> Error(Nil)
    ["src", ..] -> Ok(list.append(acc, ["src"]))
    [part, ..rest] -> take_through_src(rest, list.append(acc, [part]))
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

fn check_server_context_from_session(path: String) -> #(Bool, String) {
  case simplifile.read(path) {
    Ok(source) ->
      case string.contains(source, "pub fn from_session") {
        True -> #(True, "server_context")
        False -> #(False, "server_context")
      }
    _ -> #(False, "server_context")
  }
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
