import gleam/list
import gleeunit/should
import lando/parser
import lando/types.{VariantInfo}

pub fn parse_client_context_test() {
  let source =
    "
pub type ClientContext {
  ClientContext(smashed_likes: Int)
}

pub type ClientContextMsg {
  UpdateLikes(count: Int)
}

pub fn init() -> #(ClientContext, Effect(ClientContextMsg)) {
  #(ClientContext(smashed_likes: 0), effect.none())
}

pub fn update(model: ClientContext, msg: ClientContextMsg) -> #(ClientContext, Effect(ClientContextMsg)) {
  case msg {
    UpdateLikes(count) -> #(ClientContext(smashed_likes: count), effect.none())
  }
}
"
  let assert Ok(contract) = parser.parse_client_context(source)
  contract.has_init |> should.be_true()
  contract.has_update |> should.be_true()
  list.length(contract.context_variants) |> should.equal(1)
  list.length(contract.msg_variants) |> should.equal(1)
}

pub fn parse_client_context_minimal_test() {
  let source =
    "
pub type ClientContext {
  ClientContext
}

pub type ClientContextMsg {
  NoOp
}

pub fn init() -> #(ClientContext, Effect(ClientContextMsg)) {
  #(ClientContext, effect.none())
}

pub fn update(model: ClientContext, msg: ClientContextMsg) -> #(ClientContext, Effect(ClientContextMsg)) {
  case msg {
    NoOp -> #(model, effect.none())
  }
}
"
  let assert Ok(contract) = parser.parse_client_context(source)
  contract.has_init |> should.be_true()
  contract.has_update |> should.be_true()
  list.length(contract.context_variants) |> should.equal(1)
  // NoOp has no fields
  let assert [VariantInfo(name: "NoOp", fields: [])] = contract.msg_variants
}

pub fn parse_client_context_without_update_test() {
  let source =
    "
pub type ClientContext { ClientContext }
pub type ClientContextMsg { NoOp }
pub fn init() -> #(ClientContext, Effect(ClientContextMsg)) { todo }
"
  let assert Ok(contract) = parser.parse_client_context(source)
  contract.has_init |> should.be_true()
  contract.has_update |> should.be_false()
}
