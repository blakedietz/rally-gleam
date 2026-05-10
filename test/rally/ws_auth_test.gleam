import gleam/option.{None, Some}
import gleam/string
import rally/generator/ws_handler
import rally/types.{
  type PageContract, type ScannedRoute, AuthConfig, PageContract, ScannedRoute,
  StaticSegment,
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

// -- Stable signature: hostname always present --

pub fn ws_no_auth_on_init_has_hostname_test() {
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
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      None,
      from_session_module: "client_context_server",
    )

  let assert True =
    string.contains(output, "hostname _hostname: String")
}

pub fn ws_no_auth_does_not_call_resolve_test() {
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
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      None,
      from_session_module: "client_context_server",
    )

  let assert False = string.contains(output, "auth.resolve")
  let assert False = string.contains(output, "from_session")
}

// -- Auth-enabled on_init: resolves and stores state --

pub fn ws_auth_on_init_resolves_identity_test() {
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
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
    )

  let assert True =
    string.contains(output, "auth.resolve(server_context, session_id)")
}

pub fn ws_auth_on_init_calls_from_session_with_identity_test() {
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
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
    )

  let assert True =
    string.contains(output, "identity: identity")
}

pub fn ws_auth_on_init_stores_auth_state_test() {
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
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
    )

  let assert True = string.contains(output, "effect.put_ws_identity(identity)")
  let assert True = string.contains(output, "effect.put_ws_hostname(hostname)")
  let assert True = string.contains(output, "effect.put_ws_auth_timestamp(")
}

// -- Page-init auth enforcement --

pub fn ws_page_init_required_emits_auth_redirect_error_test() {
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
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
    )

  // Must check is_authenticated before updating page state
  let assert True = string.contains(output, "auth.is_authenticated(identity)")
  // Must emit auth:redirect: error on failure
  let assert True =
    string.contains(output, "auth:redirect:\" <> auth.redirect_url")
}

pub fn ws_page_init_authorize_false_emits_forbidden_error_test() {
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
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      Some(AuthConfig(auth_module: "admin/auth")),
      from_session_module: "admin/client_context_server",
    )

  let assert True =
    string.contains(output, "auth:forbidden")
}

pub fn ws_page_init_no_auth_still_updates_state_test() {
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
    ws_handler.generate(
      contracts,
      "generated@rpc_atoms",
      "generated/rpc_dispatch",
      None,
      from_session_module: "client_context_server",
    )

  // No-auth page-init should still update state as before
  let assert True = string.contains(output, "effect.put_ws_state(conn, server_context, page)")
}
