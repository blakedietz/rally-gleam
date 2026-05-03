import gleam/list
import gleeunit/should
import lando/field_type.{IntField, StringField}
import lando/parser
import lando/types.{type VariantInfo, VariantField, VariantInfo}

pub fn parse_page_with_to_backend_test() {
  let source = "
import app_config.{type Context}
pub type ToServer {
  LoadProduct(id: Int)
  SaveProduct(data: String)
}
pub type ToClient {
  ProductLoaded(String)
  SaveError(String)
}
pub fn server_update(model: ServerModel, msg: ToServer, ctx: Context) -> #(ServerModel, Effect(ToClient)) { todo }
pub fn init(id: Int) -> #(Model, Effect(Msg)) { todo }
pub fn load(id: Int, ctx: Context) -> Result(Model, LoadError) { todo }
"
  let assert Ok(contract) = parser.parse_page(source)

  // Check variant names
  list.map(contract.to_server_variants, fn(v: VariantInfo) { v.name })
  |> should.equal(["LoadProduct", "SaveProduct"])
  list.map(contract.to_client_variants, fn(v: VariantInfo) { v.name })
  |> should.equal(["ProductLoaded", "SaveError"])

  // Check field types
  let assert [VariantInfo(name: "LoadProduct", fields: [VariantField(
    label: "id",
    type_: IntField,
  )]), VariantInfo(name: "SaveProduct", fields: [VariantField(
    label: "data",
    type_: StringField,
  )])] = contract.to_server_variants

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
pub type ToServer {}
pub type ToClient {}
pub fn init() -> #(Model, Effect(Msg)) { todo }
"
  let assert Ok(contract) = parser.parse_page(source)
  contract.to_server_variants |> should.equal([])
  contract.to_client_variants |> should.equal([])
}

pub fn parse_page_init_with_multiple_params_test() {
  let source = "
pub type Model { Model }
pub fn init(id: Int, key: String) -> #(Model, Effect(Msg)) { todo }
"
  let assert Ok(contract) = parser.parse_page(source)
  contract.param_names |> should.equal(["id", "key"])
}

pub fn parse_page_with_server_init_test() {
  let source = "
pub type Model { Model }
pub type ToServer {
  Increment
  Decrement
}
pub type ToClient {
  CounterNewValue(value: Int)
}
pub type ServerModel { ServerModel(count: Int) }
pub fn init() -> #(Model, Effect(Msg)) { #(Model, effect.none()) }
pub fn update(model, msg) -> #(Model, Effect(Msg)) { #(model, effect.none()) }
pub fn server_update(model: ServerModel, msg: ToServer, ctx) -> #(ServerModel, Effect(ToClient)) { todo }
pub fn server_init(ctx) -> ServerModel { ServerModel(count: 0) }
"
  let assert Ok(contract) = parser.parse_page(source)
  contract.has_server_update |> should.be_true()
  contract.has_server_init |> should.be_true()

  // ToServer variants: Increment (0 fields), Decrement (0 fields)
  list.map(contract.to_server_variants, fn(v: VariantInfo) { v.name })
  |> should.equal(["Increment", "Decrement"])

  // ToClient: CounterNewValue(value: Int)
  let assert [VariantInfo(name: "CounterNewValue", fields: [VariantField(
    label: "value",
    type_: IntField,
  )])] = contract.to_client_variants
}
