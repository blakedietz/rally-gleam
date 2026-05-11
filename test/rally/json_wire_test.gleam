import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleeunit/should
import libero/field_type as libero_field_type
import libero/scanner.{type HandlerEndpoint, HandlerEndpoint}
import rally/generator
import rally/generator/ssr_handler
import rally/generator/ws_handler
import rally/parser
import rally/scanner as rally_scanner
import rally/types.{type ScanConfig, ScanConfig}
import simplifile

const fixture_root = "fixtures/json_protocol"

@external(erlang, "libero_ffi", "find_executable")
fn find_executable(name: String) -> Option(String)

@external(erlang, "libero_ffi", "run_executable_capturing")
fn run_executable_capturing_ffi(
  path: String,
  args: List(String),
) -> #(Int, String)

fn run_gleam(cwd: String, args: List(String)) -> #(Int, String) {
  case find_executable("sh"), find_executable("gleam") {
    Some(sh), Some(gleam) -> {
      let command =
        "cd " <> cwd <> " && " <> gleam <> " " <> string.join(args, " ")
      run_executable_capturing_ffi(sh, ["-c", command])
    }
    _, None -> #(-1, "gleam executable not found on PATH")
    None, _ -> #(-1, "sh executable not found on PATH")
  }
}

fn json_config() -> ScanConfig {
  ScanConfig(
    pages_root: fixture_root <> "/src/public/pages",
    output_route: "",
    output_dispatch: "",
    output_server_dispatch: "",
    output_server_atoms: "",
    atoms_module: "",
    output_server_wire: "",
    wire_module: "",
    output_ssr: "",
    output_ws: "",
    output_http: "",
    client_root: "",
    route_root: "/",
    rally_package_path: "",
    shell_file: fixture_root <> "/src/public/shell.html",
    server_deps: dict.new(),
    protocol: "json",
  )
}

fn last_module_segment(module_path: String) -> String {
  case string.split_once(module_path, "pages/") {
    Ok(#(_, rest)) -> rest
    Error(_) -> module_path
  }
}

// =============================================================================
// E2E pipeline test
// =============================================================================

pub fn json_wire_e2e_fixture_scan_test() {
  let config = json_config()

  // 1. Scanner discovers route
  let assert Ok(routes) = rally_scanner.scan(config)
  list.length(routes) |> should.equal(1)
  let assert Ok(route) = list.first(routes)
  route.variant_name |> should.equal("Home")
  route.params |> should.equal([])

  // 2. Parser extracts page contract
  let file_path =
    config.pages_root
    <> "/"
    <> last_module_segment(route.module_path)
    <> ".gleam"
  let assert Ok(source) = simplifile.read(file_path)
  let assert Ok(contract) =
    parser.parse_page(source, module_path: route.module_path)
  contract.has_model |> should.be_true()
  contract.has_init |> should.be_true()

  // 3. Generator produces router
  let router_src = generator.generate(routes)
  router_src |> string.contains("pub type Route {") |> should.be_true()
  router_src |> string.contains("Home") |> should.be_true()
  router_src |> string.contains("pub fn parse_route") |> should.be_true()
  router_src |> string.contains("pub fn route_to_path") |> should.be_true()

  // 4. Generator produces dispatch
  let dispatch_src =
    generator.generate_dispatch(
      routes,
      [#(route, contract)],
      False,
      "generated/router",
      "client_context",
    )
  dispatch_src |> string.contains("pub type PageModel") |> should.be_true()
  dispatch_src |> string.contains("pub type PageMsg") |> should.be_true()
  dispatch_src |> string.contains("pub fn init_page") |> should.be_true()
  dispatch_src |> string.contains("NoPageModel") |> should.be_true()
  dispatch_src |> string.contains("NoPageMsg") |> should.be_true()
}

// =============================================================================
// Guard tests
// =============================================================================

pub fn json_wire_protocol_wire_is_json_mode_test() {
  let source =
    generator.generate_protocol_wire(
      "json",
      "generated@rpc_atoms",
      "test_hash_123",
    )
  source |> string.contains("libero/json/wire") |> should.be_true()
  source |> string.contains("libero/wire") |> should.be_false()
}

pub fn json_wire_no_raw_json_in_runtime_test() {
  // WS handler with JSON protocol should not contain raw JS JSON calls
  let ws =
    ws_handler.generate(
      [],
      "",
      "",
      None,
      "server_context",
      [],
      "generated/protocol_wire",
      "json",
    )
  ws |> string.contains("JSON.parse") |> should.be_false()
  ws |> string.contains("JSON.stringify") |> should.be_false()

  // SSR handler with JSON protocol should not contain raw JS JSON calls
  let ssr =
    ssr_handler.generate(
      [],
      False,
      False,
      "server_context",
      "generated/router",
      "<html></html>",
      "",
      Some("generated@rpc_wire"),
      None,
      None,
      "generated/protocol_wire",
      "json",
    )
  ssr |> string.contains("JSON.parse") |> should.be_false()
  ssr |> string.contains("JSON.stringify") |> should.be_false()
}

pub fn json_wire_no_byte_tags_in_app_test() {
  // WS handler with JSON protocol should not contain ETF byte tags
  // (0x00, 0x01 are ETF call/response markers from the binary wire protocol)
  let ws =
    ws_handler.generate(
      [],
      "",
      "",
      None,
      "server_context",
      [],
      "generated/protocol_wire",
      "json",
    )
  ws |> string.contains("0x00") |> should.be_false()
  ws |> string.contains("0x01") |> should.be_false()

  // SSR handler with JSON protocol should not contain ETF byte tags
  let ssr =
    ssr_handler.generate(
      [],
      False,
      False,
      "server_context",
      "generated/router",
      "<html></html>",
      "",
      Some("generated@rpc_wire"),
      None,
      None,
      "generated/protocol_wire",
      "json",
    )
  ssr |> string.contains("0x00") |> should.be_false()
  ssr |> string.contains("0x01") |> should.be_false()
}

pub fn json_wire_ws_handler_has_text_branch_test() {
  let ws =
    ws_handler.generate(
      [],
      "",
      "",
      None,
      "server_context",
      [],
      "generated/protocol_wire",
      "json",
    )
  ws |> string.contains("mist.Text") |> should.be_true()
  // ETF mode uses mist.Binary, JSON adds mist.Text
  ws |> string.contains("mist.Text(data)") |> should.be_true()
}

pub fn json_wire_facade_is_only_wire_import_test() {
  // Generated WS handler should import protocol_wire facade, not libero wire modules
  let ws =
    ws_handler.generate(
      [],
      "",
      "",
      None,
      "server_context",
      [],
      "generated/protocol_wire",
      "json",
    )
  ws |> string.contains("libero/wire") |> should.be_false()
  ws |> string.contains("libero/json/wire") |> should.be_false()

  // Generated SSR handler should not import libero wire modules directly
  let ssr =
    ssr_handler.generate(
      [],
      False,
      False,
      "server_context",
      "generated/router",
      "<html></html>",
      "",
      Some("generated@rpc_wire"),
      None,
      None,
      "generated/protocol_wire",
      "json",
    )
  ssr |> string.contains("libero/wire") |> should.be_false()
  ssr |> string.contains("libero/json/wire") |> should.be_false()
}

// =============================================================================
// Compile test — proves the generated JSON WS handler actually compiles
// =============================================================================

pub fn json_ws_handler_with_endpoint_compiles_test() {
  let endpoint =
    HandlerEndpoint(
      module_path: "public/pages/home_",
      fn_name: "increment",
      return_ok: libero_field_type.IntField,
      return_err: libero_field_type.NilField,
      params: [],
      mutates_context: False,
      msg_type: Some(#("public/pages/home_", "ServerIncrement")),
    )

  let ws_source =
    ws_handler.generate(
      [],
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      None,
      "server_context",
      [endpoint],
      "generated/public/protocol_wire",
      "json",
    )

  // Set up temp project
  let root = "build/.test_json_ws"
  let src = root <> "/src"
  let _ = simplifile.delete_all([root])
  let assert Ok(Nil) =
    simplifile.create_directory_all(src <> "/generated/public")
    |> result.map_error(string.inspect)
  let assert Ok(Nil) =
    simplifile.create_directory_all(src <> "/public/pages")
    |> result.map_error(string.inspect)

  // Write gleam.toml
  let assert Ok(Nil) =
    simplifile.write(root <> "/gleam.toml", json_compile_toml())
    |> result.map_error(string.inspect)

  // Write server_context
  let assert Ok(Nil) =
    simplifile.write(
      src <> "/server_context.gleam",
      "pub type ServerContext { ServerContext }\n",
    )
    |> result.map_error(string.inspect)

  // Write JSON protocol_wire facade (minimal stub that compiles)
  let stub_dir = "build/test_json_stubs"
  let assert Ok(protocol_wire_stub) =
    simplifile.read(stub_dir <> "/protocol_wire_stub.gleam")
    |> result.map_error(string.inspect)
  let assert Ok(Nil) =
    simplifile.write(
      src <> "/generated/public/protocol_wire.gleam",
      protocol_wire_stub,
    )
    |> result.map_error(string.inspect)

  // Write JSON codec stub
  let assert Ok(codec_stub) =
    simplifile.read(stub_dir <> "/codec_stub.gleam")
    |> result.map_error(string.inspect)
  let assert Ok(Nil) =
    simplifile.write(src <> "/generated/public/json_codecs.gleam", codec_stub)
    |> result.map_error(string.inspect)

  // Write handler page stub
  let assert Ok(handler_stub) =
    simplifile.read(stub_dir <> "/handler_stub.gleam")
    |> result.map_error(string.inspect)
  let assert Ok(Nil) =
    simplifile.write(src <> "/public/pages/home_.gleam", handler_stub)
    |> result.map_error(string.inspect)

  // Write generated WS handler
  let assert Ok(Nil) =
    simplifile.write(src <> "/generated/public/ws_handler.gleam", ws_source)
    |> result.map_error(string.inspect)

  // Compile
  let #(status, output) = run_gleam(root, ["build"])
  let _ = simplifile.delete_all([root])
  let msg =
    "JSON WS handler compile failed (exit "
    <> int.to_string(status)
    <> "):\n"
    <> output
  case status {
    0 -> Nil
    _ -> panic as msg
  }

  // Verify generated code has correct dispatch structure
  ws_source
  |> string.contains("public/pages/home_.ServerIncrement")
  |> should.be_true()
  ws_source
  |> string.contains(
    "json_codecs.json_decode_public_pages_home__server_increment",
  )
  |> should.be_true()
  ws_source
  |> string.contains("json.encode_gleam_result__result")
  |> should.be_true()
  ws_source
  |> string.contains("fn(x) { json.int(x) }")
  |> should.be_true()
  ws_source
  |> string.contains("fn(x) { json.null() }")
  |> should.be_true()
}

fn json_compile_toml() -> String {
  "name = \"json_ws_compile_test\"
version = \"1.0.0\"

[dependencies]
gleam_stdlib = \">= 0.69.0 and < 2.0.0\"
rally = { path = \"../..\" }
mist = \">= 6.0.0 and < 7.0.0\"
"
}
