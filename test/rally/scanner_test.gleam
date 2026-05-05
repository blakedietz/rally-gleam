import gleam/list
import gleeunit/should
import simplifile
import rally/scanner
import gleam/option.{None, Some}
import rally/types.{
  DynamicSegment, IntParam, ScanConfig, type ScanConfig, ScannedRoute,
  StaticSegment, StringParam,
}

fn test_config(dir: String) -> ScanConfig {
  ScanConfig(
    pages_root: dir,
    output_route: "",
    output_dispatch: "",
    output_server_dispatch: "",
    output_ssr: "",
    output_ws: "",
    output_http: "",
    sql_dir: "",
    client_root: "",
    rally_package_path: "",
    shell_file: "",
  )
}

fn make_temp_dir(name: String) -> String {
  let path = "/tmp/rally_test_" <> name
  let assert Ok(Nil) = simplifile.create_directory_all(path)
  path
}

fn cleanup(path: String) -> Nil {
  let _ = simplifile.delete(file_or_dir_at: path)
  Nil
}

fn touch(path: String) -> Nil {
  let assert Ok(Nil) = simplifile.write(to: path, contents: "")
  Nil
}

fn mkdir(path: String) -> Nil {
  let assert Ok(Nil) = simplifile.create_directory_all(path)
  Nil
}

pub fn scan_home_test() {
  let dir = make_temp_dir("home")
  touch(dir <> "/home_.gleam")
  let assert Ok(routes) = scanner.scan(test_config(dir))
  let assert True =
    list.contains(
      routes,
      ScannedRoute(
        segments: [],
        variant_name: "Home",
        params: [],
        layout_module: None, module_path: "pages/home_",
      ),
    )
  cleanup(dir)
}

pub fn scan_static_route_test() {
  let dir = make_temp_dir("static")
  mkdir(dir <> "/settings")
  touch(dir <> "/settings/general.gleam")
  let assert Ok(routes) = scanner.scan(test_config(dir))
  let assert True =
    list.contains(
      routes,
      ScannedRoute(
        segments: [StaticSegment("settings"), StaticSegment("general")],
        variant_name: "SettingsGeneral",
        params: [],
        layout_module: None, module_path: "pages/settings/general",
      ),
    )
  cleanup(dir)
}

pub fn scan_dynamic_int_route_test() {
  let dir = make_temp_dir("dynamic_int")
  mkdir(dir <> "/registration/orders")
  touch(dir <> "/registration/orders/id_.gleam")
  let assert Ok(routes) = scanner.scan(test_config(dir))
  let assert True =
    list.contains(
      routes,
      ScannedRoute(
        segments: [
          StaticSegment("registration"),
          StaticSegment("orders"),
          DynamicSegment("id", IntParam),
        ],
        variant_name: "RegistrationOrdersId",
        params: [#("id", IntParam)],
        layout_module: None, module_path: "pages/registration/orders/id_",
      ),
    )
  cleanup(dir)
}

pub fn scan_dynamic_string_route_test() {
  let dir = make_temp_dir("dynamic_string")
  mkdir(dir <> "/registration/custom_questions")
  touch(dir <> "/registration/custom_questions/key_.gleam")
  let assert Ok(routes) = scanner.scan(test_config(dir))
  let assert True =
    list.contains(
      routes,
      ScannedRoute(
        segments: [
          StaticSegment("registration"),
          StaticSegment("custom_questions"),
          DynamicSegment("key", StringParam),
        ],
        variant_name: "RegistrationCustomQuestionsKey",
        params: [#("key", StringParam)],
        layout_module: None, module_path: "pages/registration/custom_questions/key_",
      ),
    )
  cleanup(dir)
}

pub fn scan_nested_dynamic_route_test() {
  let dir = make_temp_dir("nested_dynamic")
  mkdir(dir <> "/registration/orders/id_/payments/payment_id_")
  touch(dir <> "/registration/orders/id_/payments/payment_id_/edit.gleam")
  let assert Ok(routes) = scanner.scan(test_config(dir))
  let assert True =
    list.contains(
      routes,
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
        layout_module: None, module_path: "pages/registration/orders/id_/payments/payment_id_/edit",
      ),
    )
  cleanup(dir)
}

pub fn scan_file_and_directory_coexist_test() {
  let dir = make_temp_dir("coexist")
  mkdir(dir <> "/orders/id_")
  touch(dir <> "/orders.gleam")
  touch(dir <> "/orders/new.gleam")
  touch(dir <> "/orders/id_.gleam")
  let assert Ok(routes) = scanner.scan(test_config(dir))
  let assert True = list.length(routes) == 3
  let assert True =
    list.contains(
      routes,
      ScannedRoute(
        segments: [StaticSegment("orders")],
        variant_name: "Orders",
        params: [],
        layout_module: None, module_path: "pages/orders",
      ),
    )
  let assert True =
    list.contains(
      routes,
      ScannedRoute(
        segments: [StaticSegment("orders"), StaticSegment("new")],
        variant_name: "OrdersNew",
        params: [],
        layout_module: None, module_path: "pages/orders/new",
      ),
    )
  let assert True =
    list.contains(
      routes,
      ScannedRoute(
        segments: [StaticSegment("orders"), DynamicSegment("id", IntParam)],
        variant_name: "OrdersId",
        params: [#("id", IntParam)],
        layout_module: None, module_path: "pages/orders/id_",
      ),
    )
  cleanup(dir)
}

pub fn scan_ignores_non_gleam_files_test() {
  let dir = make_temp_dir("ignore_ext")
  touch(dir <> "/home_.gleam")
  touch(dir <> "/README.md")
  touch(dir <> "/notes.txt")
  let assert Ok(routes) = scanner.scan(test_config(dir))
  let assert True = list.length(routes) == 1
  cleanup(dir)
}

pub fn scan_underscore_name_pascal_case_test() {
  let dir = make_temp_dir("pascal")
  mkdir(dir <> "/settings")
  touch(dir <> "/settings/item_subtypes.gleam")
  let assert Ok(routes) = scanner.scan(test_config(dir))
  let assert True =
    list.contains(
      routes,
      ScannedRoute(
        segments: [StaticSegment("settings"), StaticSegment("item_subtypes")],
        variant_name: "SettingsItemSubtypes",
        params: [],
        layout_module: None, module_path: "pages/settings/item_subtypes",
      ),
    )
  cleanup(dir)
}

pub fn scan_layout_assigned_to_page_test() {
  let dir = make_temp_dir("layout")
  touch(dir <> "/layout.gleam")
  touch(dir <> "/home_.gleam")
  let assert Ok(routes) = scanner.scan(test_config(dir))

  let assert True = list.length(routes) == 1
  let assert [route] = routes
  route.layout_module |> should.equal(Some("pages/layout"))
  route.variant_name |> should.equal("Home")

  cleanup(dir)
}

pub fn scan_nested_layout_test() {
  let dir = make_temp_dir("nested_layout")
  touch(dir <> "/layout.gleam")
  mkdir(dir <> "/settings")
  touch(dir <> "/settings/layout.gleam")
  touch(dir <> "/settings/profile.gleam")
  let assert Ok(routes) = scanner.scan(test_config(dir))

  let assert True = list.length(routes) == 1
  let assert [route] = routes
  route.layout_module |> should.equal(Some("pages/settings/layout"))
  route.variant_name |> should.equal("SettingsProfile")

  cleanup(dir)
}

pub fn scan_no_layout_when_none_present_test() {
  let dir = make_temp_dir("no_layout")
  mkdir(dir <> "/admin")
  touch(dir <> "/admin/users.gleam")
  let assert Ok(routes) = scanner.scan(test_config(dir))

  let assert [route] = routes
  route.layout_module |> should.equal(None)
  route.variant_name |> should.equal("AdminUsers")

  cleanup(dir)
}
