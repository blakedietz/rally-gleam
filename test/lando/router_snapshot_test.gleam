import birdie
import gleam/list
import gleam/string
import lando/field_type.{IntField}
import lando/generator
import lando/generator/client
import lando/generator/codec
import lando/generator/server_dispatch
import lando/generator/ssr_handler
import gleam/option.{None}
import lando/types.{
  IntParam, PageContract, type PageContract, type ScannedRoute, ScannedRoute,
  type ScanConfig, ScanConfig, StaticSegment, VariantField, VariantInfo,
}

fn basic_routes() -> List(ScannedRoute) {
  [
    ScannedRoute(
      segments: [],
      variant_name: "Home",
      params: [],
      layout_module: None, module_path: "pages/home_",
    ),
    ScannedRoute(
      segments: [StaticSegment("about")],
      variant_name: "About",
      params: [],
      layout_module: None, module_path: "pages/about",
    ),
    ScannedRoute(
      segments: [StaticSegment("products"), StaticSegment("new")],
      variant_name: "ProductsNew",
      params: [],
      layout_module: None, module_path: "pages/products/new",
    ),
    ScannedRoute(
      segments: [StaticSegment("products"), StaticSegment("id")],
      variant_name: "ProductsId",
      params: [#("id", IntParam)],
      layout_module: None, module_path: "pages/products/id_",
    ),
  ]
}

fn basic_contracts() -> List(#(ScannedRoute, PageContract)) {
  let routes = basic_routes()
  list.map(routes, fn(route) {
    #(
      route,
      PageContract(
        to_server_variants: [
          VariantInfo("Increment", []),
          VariantInfo("Decrement", []),
        ],
        to_client_variants: [
          VariantInfo("CounterNewValue", [VariantField("value", IntField)]),
        ],
        has_server_update: True,
        has_server_init: True,
        has_load: True,
        has_init: True,
        has_model: True,
        param_names: [],
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

pub fn server_dispatch_snapshot_test() {
  let contracts = basic_contracts()
  let output = server_dispatch.generate(contracts)
  birdie.snap(output, "server_dispatch_gleam")
}

pub fn ssr_handler_snapshot_test() {
  let contracts = basic_contracts()
  let output = ssr_handler.generate(contracts)
  birdie.snap(output, "ssr_handler_gleam")
}

pub fn transport_gleam_snapshot_test() {
  let routes = basic_routes()
  let contracts = basic_contracts()
  let config = test_scan_config()
  let files = client.generate_package(routes, contracts, config, "", "")
  // Find the transport.gleam file
  let transport = list.find(files, fn(f: client.GeneratedFile) {
    string.ends_with(f.path, "transport.gleam")
  })
  let assert Ok(file) = transport
  birdie.snap(file.content, "client_transport_gleam")
}

pub fn app_gleam_snapshot_test() {
  let routes = basic_routes()
  let contracts = basic_contracts()
  let config = test_scan_config()
  let files = client.generate_package(routes, contracts, config, "", "")
  let app = list.find(files, fn(f: client.GeneratedFile) {
    string.ends_with(f.path, "app.gleam")
  })
  let assert Ok(file) = app
  birdie.snap(file.content, "client_app_gleam")
}

pub fn types_gleam_snapshot_test() {
  let contracts = basic_contracts()
  let files = codec.generate(contracts, [])
  let types = list.find(files, fn(f: codec.CodecFile) {
    string.ends_with(f.path, "types.gleam")
  })
  let assert Ok(file) = types
  birdie.snap(file.content, "client_types_gleam")
}

pub fn codec_gleam_snapshot_test() {
  let contracts = basic_contracts()
  let files = codec.generate(contracts, [])
  let codec_file = list.find(files, fn(f: codec.CodecFile) {
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
    output_ssr: "",
    output_ws: "",
    sql_dir: "",
    client_root: "client",
    lando_package_path: "",
  )
}
