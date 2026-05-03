import birdie
import gleam/list
import lando/generator
import lando/generator/server_dispatch
import lando/generator/ssr_handler
import lando/types.{
  IntParam, PageContract, type PageContract, type ScannedRoute, ScannedRoute,
  StaticSegment,
}

fn basic_routes() -> List(ScannedRoute) {
  [
    ScannedRoute(
      segments: [],
      variant_name: "Home",
      params: [],
      module_path: "pages/home_",
    ),
    ScannedRoute(
      segments: [StaticSegment("about")],
      variant_name: "About",
      params: [],
      module_path: "pages/about",
    ),
    ScannedRoute(
      segments: [StaticSegment("products"), StaticSegment("new")],
      variant_name: "ProductsNew",
      params: [],
      module_path: "pages/products/new",
    ),
    ScannedRoute(
      segments: [StaticSegment("products"), StaticSegment("id")],
      variant_name: "ProductsId",
      params: [#("id", IntParam)],
      module_path: "pages/products/id_",
    ),
  ]
}

fn basic_contracts() -> List(#(ScannedRoute, PageContract)) {
  let routes = basic_routes()
  list.map(routes, fn(route) {
    #(
      route,
      PageContract(
        to_backend_variants: ["Increment", "Decrement"],
        to_frontend_variants: ["CounterNewValue"],
        has_server_update: True,
        has_load: True,
        has_init: True,
        has_model: True,
        param_names: [],
      ),
    )
  })
}

pub fn router_output_snapshot_test() {
  let routes = basic_routes()
  let output = generator.generate(routes)
  birdie.snap(output, "route_gleam")
}

pub fn dispatch_output_snapshot_test() {
  let routes = basic_routes()
  let output = generator.generate_dispatch(routes)
  birdie.snap(output, "page_dispatch_gleam")
}

pub fn server_dispatch_snapshot_test() {
  let contracts = basic_contracts()
  let output = server_dispatch.generate(contracts)
  birdie.snap(output, "server_dispatch_gleam")
}

pub fn ssr_handler_snapshot_test() {
  let contracts = basic_contracts()
  let output = ssr_handler.generate(contracts)
  birdie.snap(output, "ssr_handler_gleam")
}
