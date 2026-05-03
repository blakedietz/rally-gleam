import birdie
import lando/generator
import lando/types.{
  IntParam, ScannedRoute, type ScannedRoute, StaticSegment,
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
