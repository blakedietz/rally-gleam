import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import libero
import libero/codegen_dispatch.{ExtraParam}
import libero/codegen_wire_erl
import libero/field_type
import libero/gen_error
import libero/json/contract as json_contract
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

type RallyError {
  RallyError(message: String)
}

pub fn main() -> Nil {
  case run() {
    Ok(msg) -> io.println("rally: " <> msg)
    Error(RallyError(msg)) -> {
      io.println_error("rally error: " <> msg)
      halt(1)
    }
  }
}

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

fn read_configs() -> Result(List(ScanConfig), RallyError) {
  use toml_str <- result.try(
    simplifile.read("gleam.toml")
    |> result.map_error(fn(e) {
      RallyError("Cannot read gleam.toml: " <> simplifile.describe_error(e))
    }),
  )
  use toml_map <- result.try(
    tom.parse(toml_str)
    |> result.map_error(fn(e) {
      RallyError("Invalid gleam.toml: " <> tom_error_to_string(e))
    }),
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
            tom.Table(cfg) | tom.InlineTable(cfg) ->
              read_client_config(
                client_config: cfg,
                server_deps:,
                rally_package_path:,
              )
            _ ->
              Error(RallyError(
                "Each [[tools.rally.clients]] entry must be a table",
              ))
          }
        }),
      )
      case configs {
        [] ->
          Ok([
            read_legacy_config(rally_config:, server_deps:, rally_package_path:),
          ])
        _ -> Ok(configs)
      }
    }
    _ ->
      Ok([read_legacy_config(rally_config:, server_deps:, rally_package_path:)])
  }
}

fn read_client_config(
  client_config client_config: dict.Dict(String, tom.Toml),
  server_deps server_deps: dict.Dict(String, tom.Toml),
  rally_package_path rally_package_path: String,
) -> Result(ScanConfig, RallyError) {
  use namespace <- result.try(
    tom.get_string(client_config, ["namespace"])
    |> result.map_error(fn(e) {
      RallyError(
        "Each [[tools.rally.clients]] entry needs namespace = \"...\": "
        <> tom_get_error_to_string(e),
      )
    }),
  )
  let route_root =
    tom.get_string(client_config, ["route_root"])
    |> result.unwrap("/" <> namespace)
  let protocol =
    tom.get_string(client_config, ["protocol"])
    |> result.unwrap("etf")
  let protocol = case protocol {
    "etf" -> protocol
    "json" -> protocol
    other -> {
      io.println_error(
        "warning: unknown protocol \""
        <> other
        <> "\" in [[tools.rally.clients]], defaulting to \"etf\"",
      )
      "etf"
    }
  }
  Ok(ScanConfig(
    pages_root: "src/" <> namespace <> "/pages",
    output_route: "src/generated/" <> namespace <> "/router.gleam",
    output_dispatch: "src/generated/" <> namespace <> "/page_dispatch.gleam",
    output_server_dispatch: "src/generated/"
      <> namespace
      <> "/rpc_dispatch.gleam",
    output_server_atoms: "src/generated@" <> namespace <> "@rpc_atoms.erl",
    atoms_module: "generated@" <> namespace <> "@rpc_atoms",
    output_server_wire: "src/generated@" <> namespace <> "@rpc_wire.erl",
    wire_module: "generated@" <> namespace <> "@rpc_wire",
    output_ssr: "src/generated/" <> namespace <> "/ssr_handler.gleam",
    output_ws: "src/generated/" <> namespace <> "/ws_handler.gleam",
    output_http: "src/generated/" <> namespace <> "/http_handler.gleam",
    client_root: ".generated_clients/" <> namespace,
    route_root:,
    rally_package_path:,
    shell_file: "src/" <> namespace <> "/shell.html",
    server_deps:,
    protocol:,
  ))
}

fn read_legacy_config(
  rally_config rally_config: dict.Dict(String, tom.Toml),
  server_deps server_deps: dict.Dict(String, tom.Toml),
  rally_package_path rally_package_path: String,
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
  let wire_module = "generated@rpc_wire"
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
    |> result.unwrap(".generated_clients")
  let route_root =
    tom.get_string(rally_config, ["route_root"])
    |> result.unwrap("/")
  let shell_file =
    tom.get_string(rally_config, ["shell_file"])
    |> result.unwrap("src/shell.html")
  let protocol = "etf"

  ScanConfig(
    pages_root:,
    output_route:,
    output_dispatch:,
    output_server_dispatch:,
    output_server_atoms:,
    atoms_module:,
    output_server_wire: "src/generated@rpc_wire.erl",
    wire_module:,
    output_ssr:,
    output_ws:,
    output_http:,
    client_root:,
    route_root:,
    rally_package_path:,
    shell_file:,
    server_deps:,
    protocol:,
  )
}

fn run() -> Result(String, RallyError) {
  use configs <- result.try(read_configs())
  use Nil <- result.try(list.try_each(configs, generate_for_config))
  Ok(int.to_string(list.length(configs)) <> " client(s)")
}

fn generate_for_config(config: ScanConfig) -> Result(Nil, RallyError) {
  use routes <- result.try(
    scanner.scan(config)
    |> result.map_error(fn(msg) { RallyError("scan error: " <> msg) }),
  )

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
      list.each(errors, gen_error.print_error)
      []
    }
  }

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
            _ -> {
              io.println_error(
                "warning: failed to parse " <> file_path <> ", skipping",
              )
              Error(Nil)
            }
          }
        }
        _ -> {
          io.println_error("warning: cannot read " <> file_path <> ", skipping")
          Error(Nil)
        }
      }
    })

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
  let auth_path = dirname(config.pages_root) <> "/auth.gleam"
  let auth_config = case simplifile.read(auth_path) {
    Ok(source) -> {
      let auth_module = module_from_src_path(auth_path)
      case
        string.contains(source, "pub type Identity")
        && string.contains(source, "pub fn resolve")
        && string.contains(source, "pub fn is_authenticated")
        && string.contains(source, "pub const redirect_url")
      {
        True -> option.Some(types.AuthConfig(auth_module:))
        False -> {
          io.println_error(
            "rally: auth.gleam found at "
            <> auth_path
            <> " but missing required exports (Identity, resolve, is_authenticated, redirect_url)",
          )
          option.None
        }
      }
    }
    _ -> option.None
  }

  let router_module = module_from_src_path(config.output_route)
  let rpc_dispatch_module = module_from_src_path(config.output_server_dispatch)

  let route_source = generator.generate(routes)
  let dispatch_source =
    generator.generate_dispatch(
      routes,
      contracts,
      has_client_context,
      router_module,
      client_context_module,
    )

  let extra_dispatch_params = case auth_config {
    option.Some(types.AuthConfig(auth_module:)) -> {
      let auth_ref = last_segment(auth_module)
      [
        ExtraParam(
          name: "identity",
          type_ref: auth_ref <> ".Identity",
          import_line: import_as_string(auth_module, auth_ref),
        ),
      ]
    }
    option.None -> []
  }
  let namespace_prefix =
    config.pages_root
    |> string.drop_start(4)
    |> fn(p) { string.replace(p, "/pages", "") }
  let ns_endpoints =
    list.filter(handler_endpoints, fn(ep) {
      string.starts_with(ep.module_path, namespace_prefix <> "/")
    })
  let sd_source = case ns_endpoints {
    [] ->
      generator.generate_empty_rpc_dispatch(
        config.atoms_module,
        extra_dispatch_params,
      )
    _ ->
      case extra_dispatch_params {
        [] ->
          libero.generate_dispatch(
            ns_endpoints,
            option.Some(config.atoms_module),
            option.Some(config.wire_module),
          )
        params ->
          libero.generate_dispatch_with_extra_params(
            ns_endpoints,
            option.Some(config.atoms_module),
            option.Some(config.wire_module),
            params,
          )
      }
  }
  let sd_source =
    sd_source
    |> generator.normalize_rpc_dispatch_context_import
    |> generator.normalize_rpc_dispatch_unused_fields

  let shell_html = case simplifile.read(config.shell_file) {
    Ok(html) -> html
    _ ->
      "<!DOCTYPE html>\n<html>\n<head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1.0'></head>\n<body><div id='app'></div><script type='module' src='/client.js'></script></body>\n</html>"
  }

  // Read client context source and walk discovered types early
  // (needed for contract hash computation before writing protocol_wire)
  let client_context_source = case has_client_context {
    True ->
      case simplifile.read(client_context_path) {
        Ok(source) -> option.Some(source)
        _ -> option.None
      }
    False -> option.None
  }
  let handler_seeds = libero.collect_seeds(ns_endpoints)
  let cc_seeds = case client_context_source {
    option.Some(source) ->
      codec.client_context_seeds(source, client_context_module)
    option.None -> []
  }
  let page_model_seeds =
    list.filter_map(contracts, fn(pair) {
      let #(route, contract) = pair
      case contract.has_model {
        True -> Ok(#(route.module_path, "Model"))
        False -> Error(Nil)
      }
    })
  let to_client_seeds =
    list.filter_map(contracts, fn(pair) {
      let #(route, contract) = pair
      case has_to_client_type(route, contract) {
        True -> Ok(#(route.module_path, "ToClient"))
        False -> Error(Nil)
      }
    })
  let seeds =
    list.flatten([handler_seeds, cc_seeds, page_model_seeds, to_client_seeds])
  let discovered = case libero.walk(seeds) {
    Ok(types) -> types
    Error(errors) -> {
      list.each(errors, gen_error.print_error)
      []
    }
  }

  let push_dispatches = {
    let page_dispatches =
      list.filter_map(contracts, fn(pair) {
        let #(route, contract) = pair
        case has_to_client_type(route, contract) {
          True -> {
            let type_atom =
              libero.qualified_atom_name(
                module_path: route.module_path,
                variant_name: "ToClient",
              )
            Ok(codegen_wire_erl.PushDispatch(
              page_tag: route.variant_name,
              type_atom: type_atom,
            ))
          }
          False -> Error(Nil)
        }
      })
    let cc_dispatch = case has_client_context, client_context_source {
      True, option.Some(_) -> {
        let type_atom =
          libero.qualified_atom_name(
            module_path: client_context_module,
            variant_name: "ClientContextMsg",
          )
        [
          codegen_wire_erl.PushDispatch(
            page_tag: "__ClientContext__",
            type_atom: type_atom,
          ),
        ]
      }
      _, _ -> []
    }
    list.append(page_dispatches, cc_dispatch)
  }

  // Compute contract hash for JSON protocol
  let push_contracts =
    list.filter_map(contracts, fn(pair) {
      let #(route, contract) = pair
      case has_to_client_type(route, contract) {
        True ->
          Ok(json_contract.PushContract(
            module: route.module_path,
            type_module: route.module_path,
            type_name: "ToClient",
          ))
        False -> Error(Nil)
      }
    })
  let ssr_model_contracts =
    list.filter_map(contracts, fn(pair) {
      let #(route, contract) = pair
      case contract.has_load && contract.has_model {
        True ->
          Ok(json_contract.SsrModelContract(
            route_module: route.module_path,
            type_module: route.module_path,
            type_name: "Model",
          ))
        False -> Error(Nil)
      }
    })
  let contract_hash = case config.protocol {
    "json" ->
      json_contract.generate_hash(
        ns_endpoints,
        discovered,
        push_contracts,
        ssr_model_contracts,
      )
    _ -> ""
  }

  let protocol_wire_output =
    string.replace(config.output_ws, "ws_handler.gleam", "protocol_wire.gleam")
  let protocol_wire_module =
    protocol_wire_output
    |> string.drop_start(4)
    |> string.drop_end(6)

  let ssr_source =
    ssr_handler.generate(
      contracts,
      has_client_context,
      has_from_session,
      from_session_module,
      router_module,
      shell_html,
      config.atoms_module,
      option.Some(config.wire_module),
      case has_client_context {
        True -> option.Some(client_context_module)
        False -> option.None
      },
      auth_config,
      wire_import_module: protocol_wire_module,
    )

  // Write generated files, aborting on first failure
  let result =
    do_write_files(
      config:,
      route_source:,
      dispatch_source:,
      sd_source:,
      ssr_source:,
      contracts:,
      handler_endpoints:,
      rpc_dispatch_module:,
      auth_config:,
      from_session_module:,
      protocol_wire_module:,
      contract_hash:,
    )
  use _ <- result.try(result)

  let transport_ffi_path =
    config.rally_package_path <> "/src/rally_runtime/transport_ffi.mjs"
  use transport_ffi_content <- result.try(
    simplifile.read(transport_ffi_path)
    |> result.map_error(fn(e) {
      RallyError(
        "Cannot read transport_ffi.mjs from rally package at "
        <> transport_ffi_path
        <> ": "
        <> simplifile.describe_error(e),
      )
    }),
  )

  let atoms_erl =
    libero.generate_atoms(
      ns_endpoints,
      discovered,
      config.atoms_module,
      option.Some(config.wire_module),
    )
  use _ <- result.try(
    write_file(config.output_server_atoms, atoms_erl)
    |> result.map_error(fn(msg) { RallyError("write error: " <> msg) }),
  )

  let wire_erl = case
    libero.generate_wire_erl(
      discovered:,
      wire_module: config.wire_module,
      endpoints: ns_endpoints,
      push_dispatches: push_dispatches,
    )
  {
    Ok(src) -> src
    Error(err) -> {
      gen_error.print_error(err)
      ""
    }
  }
  use _ <- result.try(
    write_file(config.output_server_wire, wire_erl)
    |> result.map_error(fn(msg) { RallyError("write error: " <> msg) }),
  )

  let server_symbols = collect_server_symbols(ns_endpoints)

  use client_context_contract <- result.try(case client_context_source {
    option.Some(source) ->
      parser.parse_client_context(source)
      |> result.map(option.Some)
      |> result.map_error(fn(error) {
        RallyError("Cannot parse client_context.gleam: " <> error)
      })
    option.None -> Ok(option.None)
  })
  let raw_codec_files =
    codec.generate(contracts, discovered, ns_endpoints, server_symbols)
  let codec_files =
    list.map(raw_codec_files, fn(f: codec.CodecFile) {
      client.GeneratedFile(config.client_root <> "/" <> f.path, f.content)
    })

  // Add JSON typed codecs when protocol is json
  let codec_files = case config.protocol {
    "json" ->
      list.append(
        codec_files,
        codec.generate_json_codecs(discovered, ns_endpoints)
          |> list.map(fn(f: codec.CodecFile) {
            client.GeneratedFile(config.client_root <> "/" <> f.path, f.content)
          }),
      )
    _ -> codec_files
  }

  let client_files =
    client.generate_package_with_client_context_contract(
      routes,
      contracts,
      config,
      config.server_deps,
      transport_ffi_content,
      client_context_contract,
      client_context_module,
      config.protocol,
    )
    |> list.append([
      client.GeneratedFile(
        config.client_root <> "/src/generated/protocol_wire.mjs",
        generator.generate_protocol_wire_js(config.protocol, contract_hash),
      ),
    ])
  let client_context_files = case has_client_context {
    True -> {
      case simplifile.read(client_context_path) {
        Ok(cc_source) -> {
          let shaken = tree_shaker.shake(cc_source, server_symbols:)
          let ffi_path = dirname(config.pages_root) <> "/client_context_ffi.mjs"
          let ffi_files = case simplifile.read(ffi_path) {
            Ok(ffi_content) -> [
              client.GeneratedFile(
                config.client_root
                  <> "/src/"
                  <> client_context_module
                  <> "_ffi.mjs",
                ffi_content,
              ),
            ]
            _ -> []
          }
          [
            client.GeneratedFile(
              config.client_root <> "/src/" <> client_context_module <> ".gleam",
              shaken,
            ),
            ..ffi_files
          ]
        }
        _ -> []
      }
    }
    False -> []
  }

  let layout_files = copy_layout_modules(routes:, config:, server_symbols:)

  let seed_sources =
    list.flatten([
      raw_codec_files
        |> list.filter(fn(f: codec.CodecFile) {
          string.ends_with(f.path, ".gleam")
          && string.starts_with(f.path, "src/")
          && string.contains(f.path, "/pages/")
        })
        |> list.map(fn(f: codec.CodecFile) {
          let module_path = f.path |> string.drop_start(4) |> string.drop_end(6)
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

  use dependency_files <- result.try(
    dependency_resolver.resolve(
      seed_sources:,
      src_root: source_root_for_pages(config.pages_root),
      client_root: config.client_root,
    )
    |> result.map_error(fn(msg) {
      RallyError("dependency resolution error: " <> msg)
    }),
  )

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
    )
    |> result.map_error(fn(msg) { RallyError("write error: " <> msg) }),
  )

  let _dispatch_result = case simplifile.read(config.output_dispatch) {
    Ok(content) ->
      case
        !string.contains(content, "pub fn")
        && !string.contains(content, "pub type")
        && !string.contains(content, "pub const")
      {
        True -> simplifile.delete(config.output_dispatch)
        False -> Ok(Nil)
      }
    _ -> Ok(Nil)
  }

  Ok(Nil)
}

fn do_write_files(
  config config: ScanConfig,
  route_source route_source: String,
  dispatch_source dispatch_source: String,
  sd_source sd_source: String,
  ssr_source ssr_source: String,
  contracts contracts: List(#(types.ScannedRoute, types.PageContract)),
  handler_endpoints handler_endpoints: List(libero_scanner.HandlerEndpoint),
  rpc_dispatch_module rpc_dispatch_module: String,
  auth_config auth_config: option.Option(types.AuthConfig),
  from_session_module from_session_module: String,
  protocol_wire_module protocol_wire_module: String,
  contract_hash contract_hash: String,
) -> Result(Nil, RallyError) {
  let namespace_prefix =
    config.pages_root
    |> string.drop_start(4)
    |> fn(p) { string.replace(p, "/pages", "") }
  let ns_endpoints =
    list.filter(handler_endpoints, fn(ep) {
      string.starts_with(ep.module_path, namespace_prefix <> "/")
    })
  let ws_source =
    ws_handler.generate(
      contracts,
      config.atoms_module,
      rpc_dispatch_module,
      auth_config,
      from_session_module:,
      endpoints: ns_endpoints,
      wire_import_module: protocol_wire_module,
    )
  use _ <- result.try(
    write_file(config.output_route, route_source)
    |> result.map_error(fn(msg) { RallyError("write error: " <> msg) }),
  )
  use _ <- result.try(
    write_file(config.output_dispatch, dispatch_source)
    |> result.map_error(fn(msg) { RallyError("write error: " <> msg) }),
  )
  use _ <- result.try(
    write_file(config.output_server_dispatch, sd_source)
    |> result.map_error(fn(msg) { RallyError("write error: " <> msg) }),
  )
  use _ <- result.try(
    write_file(config.output_ssr, ssr_source)
    |> result.map_error(fn(msg) { RallyError("write error: " <> msg) }),
  )
  use _ <- result.try(
    write_file(config.output_ws, ws_source)
    |> result.map_error(fn(msg) { RallyError("write error: " <> msg) }),
  )
  use _ <- result.try(case ns_endpoints {
    [] -> Ok(Nil)
    _ -> {
      let http_source =
        http_handler.generate(
          ns_endpoints,
          rpc_dispatch_module,
          auth_config,
          contracts,
          from_session_module:,
          wire_import_module: protocol_wire_module,
        )
      write_file(config.output_http, http_source)
      |> result.map_error(fn(msg) { RallyError("write error: " <> msg) })
    }
  })

  // Write protocol_wire facade (Gleam)
  let protocol_wire_output =
    string.replace(config.output_ws, "ws_handler.gleam", "protocol_wire.gleam")
  let protocol_wire_source =
    generator.generate_protocol_wire(
      config.protocol,
      config.atoms_module,
      contract_hash,
    )
  use _ <- result.try(
    write_file(protocol_wire_output, protocol_wire_source)
    |> result.map_error(fn(msg) { RallyError("write error: " <> msg) }),
  )

  Ok(Nil)
}

fn reset_generated_client_src(client_root: String) -> Nil {
  let _delete_result = simplifile.delete_all(paths: [client_root <> "/src"])
  Nil
}

fn last_module_segment(module_path: String) -> String {
  case string.split_once(module_path, "pages/") {
    Ok(#(_, rest)) -> rest
    _ -> module_path
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
          "Failed to create directory for "
          <> path
          <> ": "
          <> simplifile.describe_error(e)
        }),
      )
      simplifile.write(path, content)
      |> result.map_error(fn(e) {
        "Failed to write " <> path <> ": " <> simplifile.describe_error(e)
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
  path |> string.drop_start(4) |> string.drop_end(6)
}

fn last_segment(module_path: String) -> String {
  case string.split(module_path, "/") |> list.last {
    Ok(seg) -> seg
    Error(Nil) -> module_path
  }
}

fn import_as_string(module_path: String, alias: String) -> String {
  case last_segment(module_path) == alias {
    True -> "import " <> module_path
    False -> "import " <> module_path <> " as " <> alias
  }
}

fn source_root_for_pages(pages_root: String) -> String {
  let parts = string.split(pages_root, "/")
  case split_before_pages(parts, []) {
    Ok(prefix_parts) ->
      case take_through_src(prefix_parts, []) {
        Ok(src_parts) -> string.join(src_parts, "/")
        _ -> dirname(pages_root)
      }
    _ -> dirname(pages_root)
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
  routes routes: List(types.ScannedRoute),
  config config: ScanConfig,
  server_symbols server_symbols: List(String),
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
      _ -> Error(Nil)
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
      case e.msg_type {
        option.Some(#(_module_path, name)) -> Ok(name)
        option.None -> Error(Nil)
      }
    })
  ["ServerContext", ..handler_type_names]
}

fn has_to_client_type(
  route: types.ScannedRoute,
  contract: types.PageContract,
) -> Bool {
  list.any(contract.msg_variants, fn(variant) {
    case variant.fields {
      [field] ->
        case field.type_ {
          field_type.UserType(module_path:, type_name: "ToClient", args: [])
            if module_path == route.module_path
          -> True
          _ -> False
        }
      _ -> False
    }
  })
}

fn tom_error_to_string(e: tom.ParseError) -> String {
  case e {
    tom.Unexpected(got:, expected:) ->
      "unexpected character '" <> got <> "', expected " <> expected
    tom.KeyAlreadyInUse(key:) -> "duplicate key: " <> string.join(key, ".")
  }
}

fn tom_get_error_to_string(e: tom.GetError) -> String {
  case e {
    tom.NotFound(key:) -> "key not found: " <> string.join(key, ".")
    tom.WrongType(key:, expected:, got:) ->
      "expected "
      <> expected
      <> ", got "
      <> got
      <> " at "
      <> string.join(key, ".")
  }
}
