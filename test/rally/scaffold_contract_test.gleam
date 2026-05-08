import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import rally/generator
import rally/generator/client
import rally/generator/ssr_handler
import rally/generator/ws_handler
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

pub fn rpc_dispatch_unused_fields_are_underscored_test() {
  let output =
    generator.normalize_rpc_dispatch_unused_fields(
      "            ServerLogin(email:, password:) -> {\n              Nil\n            }\n            ServerLogout -> {\n              Nil\n            }\n",
    )

  output
  |> string.contains("ServerLogin(email: _, password: _) -> {")
  |> should.equal(True)

  output
  |> string.contains("ServerLogin(email:, password:) -> {")
  |> should.equal(False)

  output
  |> string.contains("ServerLogout -> {")
  |> should.equal(True)
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
  |> string.contains("<script type=\"module\" src=\"/client.js\"></script>")
  |> should.equal(True)

  script
  |> string.contains(
    ".generated_client/public/build/dev/javascript/client/generated/app.mjs",
  )
  |> should.equal(True)

  script
  |> string.contains("gleam run -m app")
  |> should.equal(True)

  script
  |> string.contains("pub fn update(model: Model, msg: Msg)")
  |> should.equal(True)

  script
  |> string.contains("pub fn view(model: Model)")
  |> should.equal(True)
}

pub fn scaffold_uses_namespaced_client_config_test() {
  let assert Ok(script) = simplifile.read("bin/new")

  script
  |> string.contains("[[tools.rally.clients]]")
  |> should.equal(True)

  script
  |> string.contains("namespace = \"public\"")
  |> should.equal(True)

  script
  |> string.contains("route_root = \"/\"")
  |> should.equal(True)

  script
  |> string.contains("src/public/pages")
  |> should.equal(True)

  script
  |> string.contains(".generated_client/public")
  |> should.equal(True)
}

pub fn scaffold_routes_http_rpc_test() {
  let assert Ok(script) = simplifile.read("bin/new")

  script
  |> string.contains("import generated/public/http_handler as http_handler")
  |> should.equal(True)

  script
  |> string.contains("\"/rpc\" ->")
  |> should.equal(True)

  script
  |> string.contains("mist.read_body(req, max_body_limit: 16_000_000)")
  |> should.equal(True)

  script
  |> string.contains("http_handler.handle(body, server_context)")
  |> should.equal(True)
}

pub fn realworld_routes_http_rpc_test() {
  let assert Ok(source) =
    simplifile.read("examples/realworld/src/realworld.gleam")

  source
  |> string.contains("import generated/public/http_handler")
  |> should.equal(True)

  source
  |> string.contains("\"/rpc\" ->")
  |> should.equal(True)

  source
  |> string.contains("mist.read_body(req, max_body_limit: 16_000_000)")
  |> should.equal(True)

  source
  |> string.contains("http_handler.handle(body, server_context)")
  |> should.equal(True)
}

pub fn ws_handler_logs_decoded_rpc_value_test() {
  let output =
    ws_handler.generate([], "generated@rpc_atoms", "generated/rpc_dispatch")

  output
  |> string.contains(
    "system.log_to_server(system.get_conn(), session_id, Error(Nil), current_page, raw, data, elapsed_ms)",
  )
  |> should.equal(True)

  output
  |> string.contains("dynamic.nil()")
  |> should.equal(False)
}

pub fn codegen_resets_generated_client_src_test() {
  let assert Ok(source) = simplifile.read("src/rally.gleam")

  source
  |> string.contains("reset_generated_client_src(config.client_root)")
  |> should.equal(True)

  source
  |> string.contains("simplifile.delete_all(paths: [client_root <> \"/src\"])")
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
    client.generate_package([], [], test_scan_config(), deps, "", False)
  let assert Ok(file) =
    list.find(files, fn(file) { file.path == ".generated_client/gleam.toml" })

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
    client.generate_package([], [], test_scan_config(), deps, "", False)
  let assert Ok(file) =
    list.find(files, fn(file) { file.path == ".generated_client/gleam.toml" })

  file.content
  |> string.contains("mist")
  |> should.equal(False)

  file.content
  |> string.contains("sqlight")
  |> should.equal(False)

  file.content
  |> string.contains("libero")
  |> should.equal(True)
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
      "generated/router",
      "<html><head></head><body><div id=\"app\"></div></body></html>",
    )

  output
  |> string.contains("import pages/layout")
  |> should.equal(False)
}

pub fn run_does_not_swallow_generated_file_write_errors_test() {
  let assert Ok(source) = simplifile.read("src/rally.gleam")

  source
  |> string.contains("let _ = write_file(config.output_http, http_source)")
  |> should.equal(False)

  source
  |> string.contains("let _ = simplifile.create_directory_all(dirname(path))")
  |> should.equal(False)
}

pub fn ssr_missing_app_marker_falls_back_to_shell_test() {
  let output =
    ssr_handler.generate(
      [
        #(
          ScannedRoute(
            segments: [StaticSegment("home")],
            variant_name: "Home",
            params: [],
            layout_module: None,
            module_path: "pages/home_",
          ),
          PageContract(
            model_variants: [],
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
        ),
      ],
      False,
      False,
      "server_context",
      "generated/router",
      "<html><head></head><body><main></main></body></html>",
    )

  output
  |> string.contains("Error(_) -> shell")
  |> should.equal(True)
}

pub fn ssr_app_marker_preserves_tag_order_test() {
  let output =
    ssr_handler.generate(
      [
        #(
          ScannedRoute(
            segments: [StaticSegment("home")],
            variant_name: "Home",
            params: [],
            layout_module: None,
            module_path: "pages/home_",
          ),
          PageContract(
            model_variants: [],
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
        ),
      ],
      False,
      False,
      "server_context",
      "generated/router",
      "<html><head></head><body><main class=\"root\" id = \"app\"></main></body></html>",
    )

  output
  |> string.contains("let tag_start = \"<\" <> string.reverse(after_lt_rev)")
  |> should.equal(True)

  output
  |> string.contains("let id_dq_spaced = \"id = \\\"app\\\"\"")
  |> should.equal(True)
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
    client_root: ".generated_client",
    route_root: "/",
    rally_package_path: "",
    shell_file: "",
    server_deps: dict.new(),
  )
}
