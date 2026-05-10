import gleam/option.{None, Some}
import gleam/string
import libero/field_type
import libero/scanner
import rally/generator/http_handler
import rally/types.{
  type PageContract, type ScannedRoute, AuthConfig, PageContract, ScannedRoute,
  StaticSegment,
}

fn make_endpoint(module: String, fn_name: String) -> scanner.HandlerEndpoint {
  scanner.HandlerEndpoint(
    module_path: module,
    fn_name: fn_name,
    return_ok: field_type.IntField,
    return_err: field_type.NilField,
    params: [],
    mutates_context: False,
    msg_type: None,
  )
}

fn make_contract(
  has_page_auth has_page_auth: Bool,
  page_auth_required page_auth_required: Bool,
  has_authorize has_authorize: Bool,
) -> PageContract {
  PageContract(
    model_variants: [],
    msg_variants: [],
    has_load: True,
    has_init: True,
    has_init_loaded: True,
    has_model: True,
    updates_client_context: False,
    param_names: [],
    source: "",
    view_source: "",
    init_source: "",
    update_source: "",
    has_page_auth:,
    page_auth_required:,
    has_authorize:,
  )
}

fn make_route(module: String) -> ScannedRoute {
  ScannedRoute(
    segments: [StaticSegment("test")],
    variant_name: "Test",
    params: [],
    module_path: module,
    layout_module: None,
  )
}

// -- Auth-enabled tests --

pub fn http_auth_imports_test() {
  let endpoints = [make_endpoint("admin/pages/dashboard", "load_data")]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
    )

  let assert True = string.contains(output, "import admin/auth")
}

pub fn http_auth_resolve_test() {
  let endpoints = [make_endpoint("admin/pages/dashboard", "load_data")]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
    )

  let assert True =
    string.contains(output, "auth.resolve(server_context, session_id)")
}

pub fn http_auth_500_on_error_test() {
  let endpoints = [make_endpoint("admin/pages/dashboard", "load_data")]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
    )

  let assert True = string.contains(output, "Error(Nil)")
  let assert True = string.contains(output, "500")
}

pub fn http_auth_from_session_identity_test() {
  let endpoints = [make_endpoint("admin/pages/dashboard", "load_data")]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
    )

  let assert True = string.contains(output, "identity: identity")
}

pub fn http_auth_dispatch_gets_identity_test() {
  let endpoints = [make_endpoint("admin/pages/dashboard", "load_data")]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
    )

  let assert True =
    string.contains(
      output,
      "rpc_dispatch.handle(server_context:, data: body, identity:)",
    )
}

pub fn http_auth_hostname_in_signature_test() {
  let endpoints = [make_endpoint("admin/pages/dashboard", "load_data")]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      contracts,
      from_session_module: "admin/client_context_server",
    )

  let assert True = string.contains(output, "hostname hostname: String")
}

// -- No-auth tests --

pub fn http_no_auth_unchanged_test() {
  let endpoints = [make_endpoint("admin/pages/dashboard", "load_data")]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: False,
        page_auth_required: False,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints,
      "generated/admin/rpc_dispatch",
      None,
      contracts,
      from_session_module: "admin/client_context_server",
    )

  let assert False = string.contains(output, "auth.resolve")
  let assert False = string.contains(output, "identity")
  let assert False = string.contains(output, "hostname")
  let assert True =
    string.contains(output, "rpc_dispatch.handle(server_context:, data: body)")
}
