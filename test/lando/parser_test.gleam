import gleeunit/should
import lando/parser

pub fn parse_page_with_to_backend_test() {
  let source = "
pub type ToBackend { LoadProduct(id: Int); SaveProduct(data: ProductData) }
pub type ToFrontend { ProductLoaded(Product); SaveError(String) }
pub fn server_update(model: ServerModel, msg: ToBackend, ctx: Context) -> #(ServerModel, Effect(ToFrontend)) { ... }
pub fn init(id: Int) -> #(Model, Effect(Msg)) { ... }
pub fn load(id: Int, ctx: Context) -> Result(Model, LoadError) { ... }
"
  let assert Ok(contract) = parser.parse_page(source)
  contract.to_backend_variants |> should.equal(["LoadProduct", "SaveProduct"])
  contract.to_frontend_variants |> should.equal(["ProductLoaded", "SaveError"])
  contract.has_server_update |> should.be_true()
  contract.has_load |> should.be_true()
  contract.param_names |> should.equal(["id"])
}

pub fn parse_page_without_server_update_test() {
  let source = "
pub type Model { Model(count: Int) }
pub type Msg { Noop }
pub fn init() -> #(Model, Effect(Msg)) { #(Model(count: 0), effect.none()) }
pub fn update(model, msg) -> #(Model, Effect(Msg)) { #(model, effect.none()) }
"
  let assert Ok(contract) = parser.parse_page(source)
  contract.has_server_update |> should.be_false()
  contract.has_load |> should.be_false()
  contract.has_model |> should.be_true()
  contract.has_init |> should.be_true()
  contract.param_names |> should.equal([])
}

pub fn parse_page_with_empty_types_test() {
  let source = "
pub type ToBackend {}
pub type ToFrontend {}
pub fn init() -> #(Model, Effect(Msg)) { ... }
"
  let assert Ok(contract) = parser.parse_page(source)
  contract.to_backend_variants |> should.equal([])
  contract.to_frontend_variants |> should.equal([])
}

pub fn parse_page_init_with_multiple_params_test() {
  let source = "
pub type Model { Model }
pub fn init(id: Int, key: String) -> #(Model, Effect(Msg)) { ... }
"
  let assert Ok(contract) = parser.parse_page(source)
  contract.param_names |> should.equal(["id", "key"])
}
