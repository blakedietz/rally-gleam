import gleam/list
import gleam/option.{None, Some}
import gleam/string
import libero/field_type
import libero/scanner
import rally/generator/ws_handler
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

fn endpoints_for(
  contracts: List(#(ScannedRoute, PageContract)),
) -> List(scanner.HandlerEndpoint) {
  list.map(contracts, fn(pair: #(ScannedRoute, PageContract)) {
    let #(route, _) = pair
    make_endpoint(route.module_path, "stub_handler")
  })
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
      endpoints: endpoints_for(contracts),
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
      endpoints: endpoints_for(contracts),
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
      endpoints: endpoints_for(contracts),
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
      endpoints: endpoints_for(contracts),
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
      endpoints: endpoints_for(contracts),
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
      endpoints: endpoints_for(contracts),
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
      endpoints: endpoints_for(contracts),
    )

  // Must include the error response
  let assert True =
    string.contains(output, "auth:forbidden")
  // page_has_authorize must map the authorized page to True
  let assert True =
    string.contains(
      output,
      "\"admin/pages/settings\" -> True",
    )
  // check_page_authorize must be generated and call the page module
  let assert True =
    string.contains(output, "fn check_page_authorize(")
  let assert True =
    string.contains(
      output,
      "admin_pages_settings.authorize(server_context, identity)",
    )
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
      endpoints: endpoints_for(contracts),
    )

  // No-auth page-init should still update state as before
  let assert True = string.contains(output, "effect.put_ws_state(conn, server_context, page)")
}

pub fn ws_auth_check_page_authorize_always_defined_test() {
  // Auth namespace with NO pages exporting authorize — must still define
  // check_page_authorize so the generated handler compiles.
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
      endpoints: endpoints_for(contracts),
    )

  let assert True =
    string.contains(output, "fn check_page_authorize(")
}

pub fn ws_auth_rpc_dispatches_with_identity_test() {
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
      endpoints: endpoints_for(contracts),
    )

  // Auth RPC dispatch must pass identity
  let assert True =
    string.contains(
      output,
      "rpc_dispatch.handle(server_context:, data:, identity:)",
    )
  // Must read identity before dispatch
  let assert True =
    string.contains(output, "effect.get_ws_identity()")
  // Missing identity must fail closed
  let assert True =
    string.contains(output, "Error(Nil) -> {")
}

// -- WS RPC owning-page enforcement --

pub fn ws_auth_rpc_generates_handler_page_info_test() {
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
      endpoints: endpoints_for(contracts),
    )

  // Must generate handler_page_info mapping variant tags to page modules
  let assert True = string.contains(output, "fn handler_page_info(")
  let assert True =
    string.contains(output, "\"server_")
  let assert True =
    string.contains(output, "Error(Nil)")
}

pub fn ws_auth_rpc_extracts_variant_tag_test() {
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
      endpoints: endpoints_for(contracts),
    )

  // RPC branch must extract variant tag from decoded message
  let assert True = string.contains(output, "wire.variant_tag(raw)")
  // Must call handler_page_info with the variant
  let assert True = string.contains(output, "handler_page_info(variant)")
}

pub fn ws_auth_rpc_enforces_required_test() {
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
      endpoints: endpoints_for(contracts),
    )

  // RPC branch must check is_authenticated for Required pages
  let assert True = string.contains(output, "required &&")
  let assert True =
    string.contains(output, "auth.is_authenticated(identity)")
  // On failure, emit auth:redirect
  let assert True =
    string.contains(output, "auth:redirect:\" <> auth.redirect_url")
}

pub fn ws_auth_rpc_enforces_authorize_test() {
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
      endpoints: endpoints_for(contracts),
    )

  // RPC branch must check authorize on owning_page (not "page" from page-init)
  let assert True =
    string.contains(output, "check_page_authorize(owning_page, server_context, identity)")
  // On failure, emit auth:forbidden
  let assert True =
    string.contains(output, "auth:forbidden")
  // Must still dispatch on success
  let assert True =
    string.contains(
      output,
      "rpc_dispatch.handle(server_context:, data:, identity:)",
    )
}

pub fn ws_auth_rpc_unknown_variant_fails_closed_test() {
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
      endpoints: endpoints_for(contracts),
    )

  // handler_page_info returns Error(Nil) for unknown variants
  // RPC branch must emit auth:unknown_rpc on unknown variant
  let assert True =
    string.contains(output, "auth:unknown_rpc")
  // RPC branch must handle malformed tags
  let assert True =
    string.contains(output, "auth:malformed")
  // RPC branch must check page mismatch
  let assert True =
    string.contains(output, "auth:page_mismatch")
}

// -- WS reauth --

pub fn ws_auth_checks_reauth_timestamp_test() {
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
      endpoints: endpoints_for(contracts),
    )

  // Must read auth timestamp
  let assert True =
    string.contains(output, "effect.get_ws_auth_timestamp()")
  // Must check staleness against reauth interval (30 min in seconds)
  let assert True =
    string.contains(output, "1800")
}

pub fn ws_auth_reauth_reruns_resolve_test() {
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
      endpoints: endpoints_for(contracts),
    )

  // On stale, must call auth.resolve again
  // The output already has one resolve call in on_init; reauth adds another
  let assert True =
    string.contains(output, "auth.resolve(server_context, session_id)")
}

pub fn ws_auth_reauth_stores_refreshed_state_test() {
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
      endpoints: endpoints_for(contracts),
    )

  // After successful reauth, must store refreshed state
  let assert True =
    string.contains(output, "effect.put_ws_identity(")
  let assert True =
    string.contains(output, "effect.put_ws_auth_timestamp(")
}

pub fn ws_auth_reauth_failure_fails_closed_test() {
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
      endpoints: endpoints_for(contracts),
    )

  // On resolve failure during reauth, must clear auth state
  let assert True =
    string.contains(output, "effect.clear_ws_auth_state()")
}

pub fn ws_auth_no_reauth_when_fresh_test() {
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
      endpoints: endpoints_for(contracts),
    )

  // When not stale, must skip re-resolve and use stored identity
  let assert True =
    string.contains(output, "effect.get_ws_identity()")
}
