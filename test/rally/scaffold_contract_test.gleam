import gleam/dict
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should
import rally/generator
import rally/generator/client
import rally/generator/ssr_handler
import rally/types.{
  type ScanConfig, PageContract, ScanConfig, ScannedRoute, StaticSegment,
}
import simplifile
import tom

pub fn empty_rpc_dispatch_handles_bad_variant_tags_test() {
  let output = generator.generate_empty_rpc_dispatch("generated@rpc_atoms")

  output
  |> string.contains("Error(_) ->")
  |> should.equal(True)

  output
  |> string.contains("UnknownFunction(\"rpc\")")
  |> should.equal(True)
}

pub fn rpc_dispatch_context_import_is_local_test() {
  let output =
    generator.normalize_rpc_dispatch_context_import(
      "import server/server_context.{type ServerContext}\n",
    )

  output
  |> should.equal("import server_context.{type ServerContext}\n")
}

pub fn scaffold_uses_app_env_and_no_client_context_page_arity_test() {
  let assert Ok(script) = simplifile.read("bin/new")

  script
  |> string.contains("APP_ENV=dev")
  |> should.equal(True)

  script
  |> string.contains("import rally_runtime/env")
  |> should.equal(True)

  script
  |> string.contains(
    "session.set_cookie_header(session_id:, secure: env.secure_cookies())",
  )
  |> should.equal(True)

  script
  |> string.contains("import server_context.{ServerContext}")
  |> should.equal(True)

  script
  |> string.contains("ssr_handler.handle_request(route)")
  |> should.equal(True)

  script
  |> string.contains("pub fn update(model: Model, msg: Msg)")
  |> should.equal(True)

  script
  |> string.contains("pub fn view(model: Model)")
  |> should.equal(True)
}

pub fn client_package_keeps_absolute_dependency_paths_test() {
  let deps =
    dict.from_list([
      #(
        "shared_widgets",
        tom.InlineTable(
          dict.from_list([#("path", tom.String("/tmp/shared_widgets"))]),
        ),
      ),
    ])
  let files =
    client.generate_package([], [], test_scan_config(), deps, "", "", False)
  let assert Ok(file) =
    list.find(files, fn(file) { file.path == "client/gleam.toml" })

  file.content
  |> string.contains("shared_widgets = { path = \"/tmp/shared_widgets\" }")
  |> should.equal(True)
}

pub fn client_package_does_not_copy_server_runtime_deps_test() {
  let deps =
    dict.from_list([
      #("mist", tom.String(">= 6.0.0 and < 7.0.0")),
      #("sqlight", tom.String(">= 1.0.0 and < 2.0.0")),
      #(
        "libero",
        tom.InlineTable(dict.from_list([#("path", tom.String("/tmp/libero"))])),
      ),
    ])
  let files =
    client.generate_package([], [], test_scan_config(), deps, "", "", False)
  let assert Ok(file) =
    list.find(files, fn(file) { file.path == "client/gleam.toml" })

  file.content
  |> string.contains("mist")
  |> should.equal(False)

  file.content
  |> string.contains("sqlight")
  |> should.equal(False)

  file.content
  |> string.contains("libero")
  |> should.equal(False)
}

pub fn ssr_omits_layout_import_when_no_load_arm_uses_it_test() {
  let route =
    ScannedRoute(
      segments: [StaticSegment("home")],
      variant_name: "Home",
      params: [],
      layout_module: Some("pages/layout"),
      module_path: "pages/home_",
    )
  let contract =
    PageContract(
      model_variants: [],
      msg_variants: [],
      has_load: False,
      has_init: True,
      has_init_loaded: False,
      has_model: True,
      updates_client_context: False,
      param_names: [],
      source: "",
      view_source: "",
      init_source: "",
      update_source: "",
    )
  let output =
    ssr_handler.generate(
      [#(route, contract)],
      False,
      False,
      "server_context",
      "<html><head></head><body><div id=\"app\"></div></body></html>",
    )

  output
  |> string.contains("import pages/layout")
  |> should.equal(False)
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
