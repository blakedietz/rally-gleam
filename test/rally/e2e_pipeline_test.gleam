import gleam/dict
import gleam/list
import gleam/string
import gleeunit/should
import rally/generator
import rally/parser
import rally/scanner
import rally/types.{type ScanConfig, ScanConfig, StringParam}
import simplifile

fn make_temp_dir(name: String) -> String {
  let path = "/tmp/rally_test_e2e_" <> name
  let _ = simplifile.delete(file_or_dir_at: path)
  let assert Ok(Nil) = simplifile.create_directory_all(path)
  path
}

fn test_config(pages_root: String) -> ScanConfig {
  ScanConfig(
    pages_root:,
    output_route: "",
    output_dispatch: "",
    output_server_dispatch: "",
    output_server_atoms: "",
    atoms_module: "",
    output_server_wire: "",
    wire_module: "",
    output_ssr: "",
    output_ws: "",
    output_http: "",
    client_root: "",
    route_root: "/",
    rally_package_path: "",
    shell_file: "",
    server_deps: dict.new(),
  )
}

fn last_module_segment(module_path: String) -> String {
  case string.split_once(module_path, "pages/") {
    Ok(#(_, rest)) -> rest
    Error(_) -> module_path
  }
}

pub fn pipeline_with_dynamic_route_test() {
  let dir = make_temp_dir("dynamic_route")
  let pages = dir <> "/pages"
  let page_path = pages <> "/articles/slug_.gleam"

  let assert Ok(Nil) = simplifile.create_directory_all(pages <> "/articles")
  let assert Ok(Nil) =
    simplifile.write(
      to: page_path,
      contents: "import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html

pub type Model {
  Model(title: String, body: String)
}

pub type Msg {
  GotArticle(String, String)
}

pub fn init(slug: String) -> #(Model, Effect(Msg)) {
  #(Model(title: slug, body: \"\"), effect.none())
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    GotArticle(title, body) -> #(Model(..model, title:, body:), effect.none())
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([], [
    html.h1([], [html.text(model.title)]),
    html.p([], [html.text(model.body)]),
  ])
}
",
    )

  let config = test_config(pages)

  // 1. Scanner discovers routes from filesystem
  let assert Ok(routes) = scanner.scan(config)
  list.length(routes) |> should.equal(1)
  let assert Ok(route) = list.first(routes)
  route.variant_name |> should.equal("ArticlesSlug")
  route.params |> should.equal([#("slug", StringParam)])
  route.module_path |> should.equal("pages/articles/slug_")

  // 2. Parser extracts page contract
  let file_path =
    pages <> "/" <> last_module_segment(route.module_path) <> ".gleam"
  let assert Ok(source) = simplifile.read(file_path)
  let assert Ok(contract) =
    parser.parse_page(source, module_path: route.module_path)
  contract.has_model |> should.be_true()
  contract.has_init |> should.be_true()
  contract.param_names |> should.equal(["slug"])

  // 3. Generator produces router with route type, parse_route, route_to_path
  let router_src = generator.generate(routes)
  router_src |> string.contains("pub type Route {") |> should.be_true()
  router_src
  |> string.contains("ArticlesSlug(slug: String)")
  |> should.be_true()
  router_src |> string.contains("pub fn parse_route") |> should.be_true()
  router_src |> string.contains("pub fn route_to_path") |> should.be_true()
  router_src |> string.contains("NotFound(uri: Uri)") |> should.be_true()
  // Dynamic string param gets percent-encoded in path
  router_src
  |> string.contains("uri.percent_encode(slug)")
  |> should.be_true()

  // 4. Generator produces dispatch wiring the page's init/update/view
  let dispatch_src =
    generator.generate_dispatch(
      routes,
      [#(route, contract)],
      False,
      "generated/router",
      "client_context",
    )
  dispatch_src |> string.contains("pub type PageModel") |> should.be_true()
  dispatch_src |> string.contains("pub type PageMsg") |> should.be_true()
  dispatch_src |> string.contains("pub fn init_page") |> should.be_true()
  dispatch_src |> string.contains("pub fn update_page") |> should.be_true()
  dispatch_src |> string.contains("pub fn view_page") |> should.be_true()
  dispatch_src
  |> string.contains("pages_articles_slug_.init")
  |> should.be_true()
  dispatch_src
  |> string.contains("ArticlesSlugPageModel")
  |> should.be_true()
  dispatch_src
  |> string.contains("ArticlesSlugPageMsg")
  |> should.be_true()

  let _ = simplifile.delete(file_or_dir_at: dir)
  Nil
}
