import gleam/string
import lando/generator
import lando/types.{
  type ScannedRoute, DynamicSegment, IntParam, ScannedRoute, StaticSegment,
  StringParam,
}

fn sample_routes() -> List(ScannedRoute) {
  [
    ScannedRoute(
      segments: [],
      variant_name: "Home",
      params: [],
      module_path: "admin/pages/home_",
    ),
    ScannedRoute(
      segments: [StaticSegment("settings"), StaticSegment("general")],
      variant_name: "SettingsGeneral",
      params: [],
      module_path: "admin/pages/settings/general",
    ),
    ScannedRoute(
      segments: [
        StaticSegment("registration"),
        StaticSegment("orders"),
        DynamicSegment("id", IntParam),
      ],
      variant_name: "RegistrationOrdersId",
      params: [#("id", IntParam)],
      module_path: "admin/pages/registration/orders/id_",
    ),
    ScannedRoute(
      segments: [
        StaticSegment("registration"),
        StaticSegment("custom_questions"),
        DynamicSegment("key", StringParam),
      ],
      variant_name: "RegistrationCustomQuestionsKey",
      params: [#("key", StringParam)],
      module_path: "admin/pages/registration/custom_questions/key_",
    ),
  ]
}

pub fn generate_route_type_test() {
  let output = generator.generate(sample_routes())
  let assert True = string.contains(output, "pub type Route {")
  let assert True = string.contains(output, "Home")
  let assert True = string.contains(output, "SettingsGeneral")
  let assert True = string.contains(output, "RegistrationOrdersId")
  let assert True = string.contains(output, "RegistrationCustomQuestionsKey")
  let assert True = string.contains(output, "NotFound(uri: Uri)")
}

pub fn generate_multi_param_variant_test() {
  let routes = [
    ScannedRoute(
      segments: [
        StaticSegment("registration"),
        StaticSegment("orders"),
        DynamicSegment("id", IntParam),
        StaticSegment("payments"),
        DynamicSegment("payment_id", IntParam),
        StaticSegment("edit"),
      ],
      variant_name: "RegistrationOrdersIdPaymentsPaymentIdEdit",
      params: [#("id", IntParam), #("payment_id", IntParam)],
      module_path: "admin/pages/registration/orders/id_/payments/payment_id_/edit",
    ),
  ]
  let output = generator.generate(routes)
  let assert True =
    string.contains(
      output,
      "RegistrationOrdersIdPaymentsPaymentIdEdit(id: Int, payment_id: Int)",
    )
}

pub fn generate_parse_route_test() {
  let output = generator.generate(sample_routes())
  let assert True = string.contains(output, "pub fn parse_route")
  let assert True = string.contains(output, "[_lang, \"admin\"] -> Home")
  let assert True =
    string.contains(output, "[_lang, \"admin\", \"settings\", \"general\"]")
  let assert True = string.contains(output, "_ -> NotFound(uri:)")
}

pub fn generate_parse_route_ordering_test() {
  // Add a static "new" sibling to the dynamic :id route and check ordering
  let routes = [
    ScannedRoute(
      segments: [StaticSegment("orders"), StaticSegment("new")],
      variant_name: "OrdersNew",
      params: [],
      module_path: "admin/pages/orders/new",
    ),
    ScannedRoute(
      segments: [StaticSegment("orders"), DynamicSegment("id", IntParam)],
      variant_name: "OrdersId",
      params: [#("id", IntParam)],
      module_path: "admin/pages/orders/id_",
    ),
  ]
  let output = generator.generate(routes)
  let assert Ok(new_pos) =
    string.split(output, "\"new\"")
    |> fn(parts) {
      case parts {
        [before, ..] -> Ok(string.length(before))
        [] -> Error(Nil)
      }
    }
  let assert Ok(id_pos) =
    string.split(output, "int.parse(id)")
    |> fn(parts) {
      case parts {
        [before, ..] -> Ok(string.length(before))
        [] -> Error(Nil)
      }
    }
  let assert True = new_pos < id_pos
}

pub fn generate_parse_route_int_param_test() {
  let output = generator.generate(sample_routes())
  let assert True = string.contains(output, "int.parse(")
  let assert True =
    string.contains(output, "Ok(id_val) -> RegistrationOrdersId(id: id_val)")
  let assert True = string.contains(output, "Error(_) -> NotFound(uri:)")
}

pub fn generate_route_to_path_test() {
  let output = generator.generate(sample_routes())
  let assert True = string.contains(output, "pub fn route_to_path")
  let assert True =
    string.contains(output, "let prefix = \"/\" <> lang <> \"/admin\"")
  let assert True = string.contains(output, "int.to_string(id)")
  let assert True =
    string.contains(output, "NotFound(uri:) -> uri.to_string(uri)")
}

pub fn generate_href_test() {
  let output = generator.generate(sample_routes())
  let assert True = string.contains(output, "pub fn href")
  let assert True =
    string.contains(output, "route_to_path(route: route, lang: lang)")
}

// ---------------------------------------------------------------------------
// generate_dispatch tests
// ---------------------------------------------------------------------------

pub fn generate_dispatch_page_model_test() {
  let output = generator.generate_dispatch(sample_routes())
  let assert True = string.contains(output, "pub type PageModel {")
  let assert True = string.contains(output, "HomeModel(page_home.Model)")
  let assert True =
    string.contains(output, "SettingsGeneralModel(page_settings_general.Model)")
  let assert True =
    string.contains(
      output,
      "RegistrationOrdersIdModel(page_registration_orders_id.Model)",
    )
  let assert True = string.contains(output, "NotFoundModel")
}

pub fn generate_dispatch_page_msg_test() {
  let output = generator.generate_dispatch(sample_routes())
  let assert True = string.contains(output, "pub type PageMsg {")
  let assert True = string.contains(output, "HomeMsg(page_home.Msg)")
  let assert True =
    string.contains(output, "SettingsGeneralMsg(page_settings_general.Msg)")
}

pub fn generate_dispatch_init_test() {
  let output = generator.generate_dispatch(sample_routes())
  let assert True = string.contains(output, "pub fn init(")
  let assert True = string.contains(output, "route.Home ->")
  let assert True = string.contains(output, "page_home.init(context)")
  let assert True =
    string.contains(output, "page_registration_orders_id.init(context, id)")
  let assert True = string.contains(output, "route.NotFound(_) ->")
}

pub fn generate_dispatch_update_test() {
  let output = generator.generate_dispatch(sample_routes())
  let assert True = string.contains(output, "pub fn update(")
  let assert True = string.contains(output, "HomeModel(m), HomeMsg(pm) ->")
  let assert True = string.contains(output, "page_home.update(context, m, pm)")
}

pub fn generate_dispatch_view_test() {
  let output = generator.generate_dispatch(sample_routes())
  let assert True = string.contains(output, "pub fn view(")
  let assert True = string.contains(output, "page_home.view(m)")
  let assert True = string.contains(output, "element.map(")
  let assert True = string.contains(output, "HomeMsg)")
}

pub fn generate_dispatch_imports_test() {
  let output = generator.generate_dispatch(sample_routes())
  let assert True =
    string.contains(output, "import admin/pages/home_ as page_home")
  let assert True =
    string.contains(
      output,
      "import admin/pages/settings/general as page_settings_general",
    )
  let assert True =
    string.contains(
      output,
      "import admin/pages/registration/orders/id_ as page_registration_orders_id",
    )
}

pub fn generate_dispatch_breadcrumb_test() {
  let output = generator.generate_dispatch(sample_routes())
  let assert True = string.contains(output, "pub fn breadcrumb(")
  let assert True =
    string.contains(output, "client_ctx client_ctx: ClientContext")
  let assert True =
    string.contains(output, ".breadcrumb(client_ctx:, model: m)")
  let assert True = string.contains(output, "List(breadcrumb.Crumb)")
  let assert True = string.contains(output, "import admin/breadcrumb")
}
