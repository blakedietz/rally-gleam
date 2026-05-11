import gleam/list
import gleeunit/should
import libero/field_type.{IntField, StringField}
import rally/parser
import rally/types.{type VariantInfo, VariantField, VariantInfo}

pub fn parse_page_with_model_and_msg_test() {
  let source =
    "
pub type Model { Model(count: Int, name: String) }
pub type Msg {
  Increment
  SetName(String)
}
pub fn init() -> #(Model, Effect(Msg)) { todo }
pub fn update(model, msg) -> #(Model, Effect(Msg)) { todo }
pub fn view(model: Model) -> Element(Msg) { todo }
"
  let assert Ok(contract) = parser.parse_page(source, module_path: "test/page")

  list.map(contract.model_variants, fn(v: VariantInfo) { v.name })
  |> should.equal(["Model"])

  let assert [
    VariantInfo(
      name: "Model",
      fields: [
        VariantField(label: "count", type_: IntField),
        VariantField(label: "name", type_: StringField),
      ],
    ),
  ] = contract.model_variants

  list.map(contract.msg_variants, fn(v: VariantInfo) { v.name })
  |> should.equal(["Increment", "SetName"])

  contract.has_init |> should.be_true()
  contract.has_model |> should.be_true()
}

pub fn parse_page_with_load_test() {
  let source =
    "
pub type Model { Model }
pub fn init(id: Int) -> #(Model, Effect(Msg)) { todo }
pub fn load(id: Int, ctx: ServerContext) -> Result(Model, LoadError) { todo }
"
  let assert Ok(contract) = parser.parse_page(source, module_path: "test/page")
  contract.has_load |> should.be_true()
  contract.has_init |> should.be_true()
  contract.param_names |> should.equal(["id"])
}

pub fn parse_page_without_load_test() {
  let source =
    "
pub type Model { Model(count: Int) }
pub type Msg { Noop }
pub fn init() -> #(Model, Effect(Msg)) { #(Model(count: 0), effect.none()) }
pub fn update(model, msg) -> #(Model, Effect(Msg)) { #(model, effect.none()) }
"
  let assert Ok(contract) = parser.parse_page(source, module_path: "test/page")
  contract.has_load |> should.be_false()
  contract.has_model |> should.be_true()
  contract.has_init |> should.be_true()
  contract.param_names |> should.equal([])
}

pub fn parse_page_init_with_multiple_params_test() {
  let source =
    "
pub type Model { Model }
pub fn init(id: Int, key: String) -> #(Model, Effect(Msg)) { todo }
"
  let assert Ok(contract) = parser.parse_page(source, module_path: "test/page")
  contract.param_names |> should.equal(["id", "key"])
}

pub fn parse_page_with_nested_msg_types_test() {
  let source =
    "
pub type Model { Model }
pub type Msg {
  GotItems(List(String))
  GotMaybe(Option(Int))
}
pub fn init() -> #(Model, Effect(Msg)) { todo }
"
  let assert Ok(contract) = parser.parse_page(source, module_path: "test/page")
  list.map(contract.msg_variants, fn(v: VariantInfo) { v.name })
  |> should.equal(["GotItems", "GotMaybe"])
}

pub fn parse_page_rejects_function_typed_fields_test() {
  let source =
    "
pub type Model { Model(handler: fn() -> Nil) }
pub fn init() -> #(Model, Effect(Msg)) { todo }
"

  let assert Error(message) =
    parser.parse_page(source, module_path: "test/page")
  message
  |> should.equal("Unsupported function type in test/page.Model.handler")
}

pub fn update_comment_does_not_count_as_client_context_update_test() {
  let source =
    "
import lustre/effect.{type Effect}
pub type Model { Model }
pub type Msg { NoOp }
pub fn init() -> #(Model, Effect(Msg)) { todo }
pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  // ClientContextMsg appears in a comment.
  #(model, effect.none())
}
pub fn view(model: Model) { todo }
"
  let assert Ok(contract) = parser.parse_page(source, module_path: "test/page")
  contract.updates_client_context |> should.equal(False)
}

pub fn update_three_tuple_return_counts_as_client_context_update_test() {
  let source =
    "
import gleam/option.{type Option}
import lustre/effect.{type Effect}
import public/client_context.{type ClientContext, type ClientContextMsg}
pub type Model { Model }
pub type Msg { NoOp }
pub fn init(ctx: ClientContext) -> #(Model, Effect(Msg)) { todo }
pub fn update(ctx: ClientContext, model: Model, msg: Msg) -> #(Model, Effect(Msg), Option(ClientContextMsg)) {
  todo
}
pub fn view(ctx: ClientContext, model: Model) { todo }
"
  let assert Ok(contract) = parser.parse_page(source, module_path: "test/page")
  contract.updates_client_context |> should.equal(True)
}

pub fn parse_page_rejects_hole_typed_fields_test() {
  let source =
    "
pub type Model { Model(value: _) }
pub fn init() -> #(Model, Effect(Msg)) { todo }
"

  let assert Error(message) =
    parser.parse_page(source, module_path: "test/page")
  message
  |> should.equal("Unsupported hole type in test/page.Model.value")
}
