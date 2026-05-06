import gleam/option.{None}
import gleam/string
import rally/generator
import rally/types.{
  type ScannedRoute, DynamicSegment, IntParam, ScannedRoute, StaticSegment,
  StringParam,
}

fn sample_routes() -> List(ScannedRoute) {
  [
    ScannedRoute(
      segments: [],
      variant_name: "Home",
      params: [],
      layout_module: None,
      module_path: "pages/home_",
    ),
    ScannedRoute(
      segments: [StaticSegment("settings"), StaticSegment("general")],
      variant_name: "SettingsGeneral",
      params: [],
      layout_module: None,
      module_path: "pages/settings/general",
    ),
    ScannedRoute(
      segments: [
        StaticSegment("registration"),
        StaticSegment("orders"),
        DynamicSegment("id", IntParam),
      ],
      variant_name: "RegistrationOrdersId",
      params: [#("id", IntParam)],
      layout_module: None,
      module_path: "pages/registration/orders/id_",
    ),
    ScannedRoute(
      segments: [
        StaticSegment("registration"),
        StaticSegment("custom_questions"),
        DynamicSegment("key", StringParam),
      ],
      variant_name: "RegistrationCustomQuestionsKey",
      params: [#("key", StringParam)],
      layout_module: None,
      module_path: "pages/registration/custom_questions/key_",
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
      layout_module: None,
      module_path: "pages/registration/orders/id_/payments/payment_id_/edit",
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
  let assert True = string.contains(output, "[] -> Home")
  let assert True = string.contains(output, "[\"settings\", \"general\"]")
  let assert True = string.contains(output, "_ -> NotFound(uri:)")
}

pub fn generate_parse_route_ordering_test() {
  // Add a static "new" sibling to the dynamic :id route and check ordering
  let routes = [
    ScannedRoute(
      segments: [StaticSegment("orders"), StaticSegment("new")],
      variant_name: "OrdersNew",
      params: [],
      layout_module: None,
      module_path: "pages/orders/new",
    ),
    ScannedRoute(
      segments: [StaticSegment("orders"), DynamicSegment("id", IntParam)],
      variant_name: "OrdersId",
      params: [#("id", IntParam)],
      layout_module: None,
      module_path: "pages/orders/id_",
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
  let assert True = string.contains(output, "int.to_string(id)")
  let assert True =
    string.contains(output, "NotFound(uri:) -> uri.to_string(uri)")
}

pub fn generate_href_test() {
  let output = generator.generate(sample_routes())
  let assert True = string.contains(output, "pub fn href")
  let assert True = string.contains(output, "route_to_path(route: route)")
}

// ---------------------------------------------------------------------------
// generate_dispatch tests
// ---------------------------------------------------------------------------

pub fn generate_dispatch_stub_test() {
  let output = generator.generate_dispatch(sample_routes())
  let assert True = string.contains(output, "Generated by Rally")
  let assert True = string.contains(output, "Page dispatch")
}
