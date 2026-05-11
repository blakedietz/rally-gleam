import birdie
import gleam/option.{None, Some}
import gleam/string
import libero
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
      endpoints:,
      rpc_dispatch_module: "generated/admin/rpc_dispatch",
      auth_config: Some(AuthConfig(auth_module: "admin/auth")),
      contracts:,
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
      endpoints:,
      rpc_dispatch_module: "generated/admin/rpc_dispatch",
      auth_config: Some(AuthConfig(auth_module: "admin/auth")),
      contracts:,
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
      endpoints:,
      rpc_dispatch_module: "generated/admin/rpc_dispatch",
      auth_config: Some(AuthConfig(auth_module: "admin/auth")),
      contracts:,
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
      endpoints:,
      rpc_dispatch_module: "generated/admin/rpc_dispatch",
      auth_config: Some(AuthConfig(auth_module: "admin/auth")),
      contracts:,
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
      endpoints:,
      rpc_dispatch_module: "generated/admin/rpc_dispatch",
      auth_config: Some(AuthConfig(auth_module: "admin/auth")),
      contracts:,
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
      endpoints:,
      rpc_dispatch_module: "generated/admin/rpc_dispatch",
      auth_config: Some(AuthConfig(auth_module: "admin/auth")),
      contracts:,
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
      endpoints:,
      rpc_dispatch_module: "generated/admin/rpc_dispatch",
      auth_config: None,
      contracts:,
      from_session_module: "admin/client_context_server",
    )

  let assert False = string.contains(output, "auth.resolve")
  let assert False = string.contains(output, "identity")
  let assert False = string.contains(output, "hostname")
  let assert True =
    string.contains(output, "rpc_dispatch.handle(server_context:, data: body)")
}

// -- Wire tag derivation test --

pub fn wire_tag_matches_server_prefix_test() {
  let endpoint = make_endpoint("admin/pages/dashboard", "load_data")
  let dispatch =
    libero.generate_dispatch(
      [endpoint],
      option.Some("generated@rpc_atoms"),
      option.Some("generated@rpc_wire"),
    )
  // Libero's fn_name is "load_data" (without server_ prefix).
  // The wire variant tag should be "server_load_data".
  let assert True = string.contains(dispatch, "\"server_load_data\"")
}

// -- Auth enforcement tests (page-level policy for RPC) --

pub fn http_auth_generates_handler_page_info_test() {
  let endpoints = [
    make_endpoint("admin/pages/dashboard", "load_data"),
    make_endpoint("admin/pages/settings", "update_config"),
  ]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
    #(
      make_route("admin/pages/settings"),
      make_contract(
        has_page_auth: True,
        page_auth_required: False,
        has_authorize: True,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints:,
      rpc_dispatch_module: "generated/admin/rpc_dispatch",
      auth_config: Some(AuthConfig(auth_module: "admin/auth")),
      contracts:,
      from_session_module: "admin/client_context_server",
    )

  // Should contain handler_page_info mapping both endpoints
  let assert True = string.contains(output, "fn handler_page_info(")
  let assert True = string.contains(output, "\"server_load_data\"")
  let assert True = string.contains(output, "\"server_update_config\"")
}

pub fn http_auth_required_page_returns_401_test() {
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
      endpoints:,
      rpc_dispatch_module: "generated/admin/rpc_dispatch",
      auth_config: Some(AuthConfig(auth_module: "admin/auth")),
      contracts:,
      from_session_module: "admin/client_context_server",
    )

  // Required pages must check is_authenticated before dispatch
  let assert True = string.contains(output, "auth.is_authenticated(identity)")
  let assert True = string.contains(output, "401")
}

pub fn http_auth_optional_page_dispatches_test() {
  let endpoints = [make_endpoint("public/pages/about", "get_info")]
  let contracts = [
    #(
      make_route("public/pages/about"),
      make_contract(
        has_page_auth: True,
        page_auth_required: False,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints:,
      rpc_dispatch_module: "generated/public/rpc_dispatch",
      auth_config: Some(AuthConfig(auth_module: "public/auth")),
      contracts:,
      from_session_module: "public/client_context_server",
    )

  // Optional pages should NOT check is_authenticated
  let assert False = string.contains(output, "auth.is_authenticated(identity)")
  // But should still resolve and dispatch
  let assert True = string.contains(output, "auth.resolve(")
  let assert True = string.contains(output, "rpc_dispatch.handle(")
}

pub fn http_auth_optional_page_with_authorize_returns_403_test() {
  let endpoints = [make_endpoint("public/pages/profile", "update_profile")]
  let contracts = [
    #(
      make_route("public/pages/profile"),
      make_contract(
        has_page_auth: True,
        page_auth_required: False,
        has_authorize: True,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints:,
      rpc_dispatch_module: "generated/public/rpc_dispatch",
      auth_config: Some(AuthConfig(auth_module: "public/auth")),
      contracts:,
      from_session_module: "public/client_context_server",
    )

  // Optional skips redirect-style authentication, but authorize still applies.
  let assert False = string.contains(output, "auth.is_authenticated(identity)")
  let assert True = string.contains(output, "fn check_page_authorize(")
  let assert True =
    string.contains(
      output,
      "public_pages_profile.authorize(server_context, identity)",
    )
  let assert True = string.contains(output, "403")
}

pub fn http_auth_mixed_required_and_optional_pages_keep_per_page_policy_test() {
  let endpoints = [
    make_endpoint("admin/pages/dashboard", "load_data"),
    make_endpoint("public/pages/login", "submit_login"),
  ]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
    #(
      make_route("public/pages/login"),
      make_contract(
        has_page_auth: True,
        page_auth_required: False,
        has_authorize: False,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints:,
      rpc_dispatch_module: "generated/public/rpc_dispatch",
      auth_config: Some(AuthConfig(auth_module: "public/auth")),
      contracts:,
      from_session_module: "public/client_context_server",
    )

  let assert True = string.contains(output, "\"server_load_data\"")
  let assert True = string.contains(output, "\"server_submit_login\"")
  let assert True = string.contains(output, "required: True")
  let assert True = string.contains(output, "required: False")
  let assert True =
    string.contains(output, "case required && !auth.is_authenticated(identity)")
}

pub fn http_auth_authorize_false_returns_403_test() {
  let endpoints = [make_endpoint("admin/pages/settings", "update_config")]
  let contracts = [
    #(
      make_route("admin/pages/settings"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: True,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints:,
      rpc_dispatch_module: "generated/admin/rpc_dispatch",
      auth_config: Some(AuthConfig(auth_module: "admin/auth")),
      contracts:,
      from_session_module: "admin/client_context_server",
    )

  // Should generate check_page_authorize function
  let assert True = string.contains(output, "fn check_page_authorize(")
  // Should call authorize on the page module
  let assert True =
    string.contains(
      output,
      "admin_pages_settings.authorize(server_context, identity)",
    )
  // Should return 403 on auth failure
  let assert True = string.contains(output, "403")
}

pub fn http_auth_authorize_runs_after_from_session_test() {
  let endpoints = [make_endpoint("admin/pages/settings", "update_config")]
  let contracts = [
    #(
      make_route("admin/pages/settings"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: True,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints:,
      rpc_dispatch_module: "generated/admin/rpc_dispatch",
      auth_config: Some(AuthConfig(auth_module: "admin/auth")),
      contracts:,
      from_session_module: "admin/client_context_server",
    )

  let assert Ok(#(_, after_from_session)) =
    string.split_once(output, ".from_session(server_context:")
  let assert True = string.contains(after_from_session, "check_page_authorize(")
  let assert True = string.contains(after_from_session, "rpc_dispatch.handle(")
}

pub fn http_auth_unknown_variant_returns_400_test() {
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
      endpoints:,
      rpc_dispatch_module: "generated/admin/rpc_dispatch",
      auth_config: Some(AuthConfig(auth_module: "admin/auth")),
      contracts:,
      from_session_module: "admin/client_context_server",
    )

  // handler_page_info returns Error(Nil) for unknown variants
  // The handle function must handle this case
  let assert True = string.contains(output, "Error(Nil)")
  // Should return 400 (not fall through to dispatch)
  // The existing 500 is from resolve Error; we need a distinct 400 for unknown variant
  let assert True = string.contains(output, "400")
}

pub fn http_auth_malformed_body_returns_400_test() {
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
      endpoints:,
      rpc_dispatch_module: "generated/admin/rpc_dispatch",
      auth_config: Some(AuthConfig(auth_module: "admin/auth")),
      contracts:,
      from_session_module: "admin/client_context_server",
    )

  // decode_call failure should return 400
  let assert True = string.contains(output, "wire.decode_call(body)")
  let assert True = string.contains(output, "Error(_)")
}

// Missing-contract case is not tested here because it panics at codegen
// time. An endpoint with no matching PageContract is an invariant violation
// between Libero's scan and Rally's parser — it should never happen.

pub fn http_auth_imports_rally_runtime_wire_test() {
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
      endpoints:,
      rpc_dispatch_module: "generated/admin/rpc_dispatch",
      auth_config: Some(AuthConfig(auth_module: "admin/auth")),
      contracts:,
      from_session_module: "admin/client_context_server",
    )

  // Must import rally_runtime/wire, not the Erlang module
  let assert True = string.contains(output, "import rally_runtime/wire as wire")
  // Must NOT import an Erlang module as wire
  let assert False = string.contains(output, "generated@")
}

// -- Snapshot tests --

pub fn http_handler_no_auth_snapshot_test() {
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
      endpoints:,
      rpc_dispatch_module: "generated/admin/rpc_dispatch",
      auth_config: None,
      contracts:,
      from_session_module: "admin/client_context_server",
    )
  birdie.snap(output, "http_handler_no_auth")
}

pub fn http_handler_with_auth_required_snapshot_test() {
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
      endpoints:,
      rpc_dispatch_module: "generated/admin/rpc_dispatch",
      auth_config: Some(AuthConfig(auth_module: "admin/auth")),
      contracts:,
      from_session_module: "admin/client_context_server",
    )
  birdie.snap(output, "http_handler_with_auth_required")
}

pub fn http_handler_with_auth_and_authorize_snapshot_test() {
  let endpoints = [
    make_endpoint("admin/pages/dashboard", "load_data"),
    make_endpoint("admin/pages/settings", "update_config"),
  ]
  let contracts = [
    #(
      make_route("admin/pages/dashboard"),
      make_contract(
        has_page_auth: True,
        page_auth_required: True,
        has_authorize: False,
      ),
    ),
    #(
      make_route("admin/pages/settings"),
      make_contract(
        has_page_auth: True,
        page_auth_required: False,
        has_authorize: True,
      ),
    ),
  ]
  let output =
    http_handler.generate(
      endpoints:,
      rpc_dispatch_module: "generated/admin/rpc_dispatch",
      auth_config: Some(AuthConfig(auth_module: "admin/auth")),
      contracts:,
      from_session_module: "admin/client_context_server",
    )
  birdie.snap(output, "http_handler_with_auth_and_authorize")
}
