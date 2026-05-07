import birdie
import gleam/dict
import gleam/list
import gleam/option.{None}
import gleam/string
import libero/field_type.{IntField}
import rally/generator
import rally/generator/client
import rally/generator/codec
import rally/generator/ssr_handler
import rally/types.{
  type PageContract, type ScanConfig, type ScannedRoute, DynamicSegment,
  IntParam, PageContract, ScanConfig, ScannedRoute, StaticSegment, VariantField,
  VariantInfo,
}

fn basic_routes() -> List(ScannedRoute) {
  [
    ScannedRoute(
      segments: [],
      variant_name: "Home",
      params: [],
      layout_module: None,
      module_path: "pages/home_",
    ),
    ScannedRoute(
      segments: [StaticSegment("about")],
      variant_name: "About",
      params: [],
      layout_module: None,
      module_path: "pages/about",
    ),
    ScannedRoute(
      segments: [StaticSegment("users"), DynamicSegment("id", IntParam)],
      variant_name: "UsersId",
      params: [#("id", IntParam)],
      layout_module: None,
      module_path: "pages/users/id_",
    ),
  ]
}

fn basic_contracts() -> List(#(ScannedRoute, PageContract)) {
  let routes = basic_routes()
  list.map(routes, fn(route) {
    #(
      route,
      PageContract(
        model_variants: [
          VariantInfo("Model", [VariantField("count", IntField)]),
        ],
        msg_variants: [],
        has_load: True,
        has_init: True,
        has_init_loaded: False,
        has_model: True,
        updates_client_context: False,
        param_names: [],
        source: "",
        view_source: "",
        init_source: "",
        update_source: "",
      ),
    )
  })
}

pub fn router_output_snapshot_test() {
  let routes = basic_routes()
  let output = generator.generate(routes)
  birdie.snap(output, "route_gleam")
}

pub fn dispatch_output_snapshot_test() {
  let routes = basic_routes()
  let output = generator.generate_dispatch(routes)
  birdie.snap(output, "page_dispatch_gleam")
}

pub fn ssr_handler_snapshot_test() {
  let contracts = basic_contracts()
  let shell =
    "<!DOCTYPE html>\n<html>\n<head><meta charset='utf-8'></head>\n<body><div id='app'></div><script type='module' src='/_build/client/generated/app.mjs'></script></body>\n</html>"
  let output =
    ssr_handler.generate(contracts, False, False, "server_context", shell)
  birdie.snap(output, "ssr_handler_gleam")
}

pub fn ssr_handler_with_client_context_snapshot_test() {
  let contracts = basic_contracts()
  let shell =
    "<!DOCTYPE html>\n<html>\n<head><meta charset='utf-8'></head>\n<body><div id='app'></div><script type='module' src='/_build/client/generated/app.mjs'></script></body>\n</html>"
  let output =
    ssr_handler.generate(contracts, True, True, "server_context", shell)
  birdie.snap(output, "ssr_handler_with_client_context_gleam")
}

pub fn app_gleam_with_client_context_snapshot_test() {
  let routes = basic_routes()
  let contracts = basic_contracts()
  let config = test_scan_config()
  let files =
    client.generate_package(routes, contracts, config, dict.new(), "", "", True)
  let app =
    list.find(files, fn(f: client.GeneratedFile) {
      string.ends_with(f.path, "app.gleam")
    })
  let assert Ok(file) = app
  birdie.snap(file.content, "client_app_with_client_context_gleam")
}

pub fn transport_gleam_snapshot_test() {
  let routes = basic_routes()
  let contracts = basic_contracts()
  let config = test_scan_config()
  let files =
    client.generate_package(
      routes,
      contracts,
      config,
      dict.new(),
      "",
      "",
      False,
    )
  let transport =
    list.find(files, fn(f: client.GeneratedFile) {
      string.ends_with(f.path, "transport.gleam")
    })
  let assert Ok(file) = transport
  birdie.snap(file.content, "client_transport_gleam")
}

pub fn app_gleam_snapshot_test() {
  let routes = basic_routes()
  let contracts = basic_contracts()
  let config = test_scan_config()
  let files =
    client.generate_package(
      routes,
      contracts,
      config,
      dict.new(),
      "",
      "",
      False,
    )
  let app =
    list.find(files, fn(f: client.GeneratedFile) {
      string.ends_with(f.path, "app.gleam")
    })
  let assert Ok(file) = app
  birdie.snap(file.content, "client_app_gleam")
}

pub fn types_gleam_snapshot_test() {
  let contracts = basic_contracts()
  let files = codec.generate(contracts, [], option.None, [], [])
  let types =
    list.find(files, fn(f: codec.CodecFile) {
      string.ends_with(f.path, "types.gleam")
    })
  let assert Ok(file) = types
  birdie.snap(file.content, "client_types_gleam")
}

pub fn codec_gleam_snapshot_test() {
  let contracts = basic_contracts()
  let files = codec.generate(contracts, [], option.None, [], [])
  let codec_file =
    list.find(files, fn(f: codec.CodecFile) {
      string.ends_with(f.path, "codec.gleam")
    })
  let assert Ok(file) = codec_file
  birdie.snap(file.content, "client_codec_gleam")
}

fn test_scan_config() -> ScanConfig {
  ScanConfig(
    pages_root: "src/pages",
    output_route: "",
    output_dispatch: "",
    output_server_dispatch: "",
    output_server_atoms: "",
    atoms_module: "",
    output_ssr: "",
    output_ws: "",
    output_http: "",
    client_root: "client",
    rally_package_path: "",
    shell_file: "",
    server_deps: dict.new(),
  )
}
