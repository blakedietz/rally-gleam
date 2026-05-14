//// JSON-specific RPC dispatch codegen.
////
//// Generates dispatch functions that route JSON-encoded RPC calls to
//// server_* handlers. Handles JSON response encoding and type registry
//// building for the JSON protocol path.

import gleam/list
import gleam/option.{Some}
import gleam/string
import justin
import libero/field_type.{
  type FieldType, BitArrayField, BoolField, DictOf, FloatField, IntField, ListOf,
  NilField, OptionOf, ResultOf, StringField, TupleOf, TypeVar, UserType,
}
import libero/scanner.{type HandlerEndpoint}
import libero/walker

fn handler_alias(module_path: String) -> String {
  string.replace(module_path, "/", "_") <> "_handler"
}

pub fn endpoint_json_tag(endpoint: HandlerEndpoint) -> String {
  let #(module_path, type_name) = case endpoint.msg_type {
    Some(#(module_path, type_name)) -> #(module_path, type_name)
    _ -> #(
      endpoint.module_path,
      justin.pascal_case("server_" <> endpoint.fn_name),
    )
  }
  module_path <> "." <> type_name
}

pub fn generate_json_dispatch_function_with_prefix(
  endpoints: List(HandlerEndpoint),
  has_auth: Bool,
  encode_prefix: String,
) -> String {
  case endpoints {
    [] -> "\nfn json_dispatch(
  message _message: Dynamic,
  request_id request_id: Int,
  server_context server_context: ServerContext," <> case has_auth {
        True -> "\n  identity _identity: auth.Identity,"
        False -> ""
      } <> "
) -> #(String, ServerContext) {
  let error_frame = " <> encode_prefix <> "encode_error(Some(request_id), [JsonError(\"rpc\", \"no endpoints configured\")])
  #(error_frame, server_context)
}\n"
    _ -> {
      let arms =
        list.map(endpoints, fn(e) {
          json_dispatch_arm(e, has_auth, encode_prefix)
        })
        |> string.join("\n")
      let catch_all = "      Ok(other) -> {
        let error_frame = " <> encode_prefix <> "encode_error(Some(request_id), [JsonError(\"type\", \"unknown: \" <> other)])
        #(error_frame, server_context)
      }"

      "\nfn json_dispatch(
  message message: Dynamic,
  request_id request_id: Int,
  server_context server_context: ServerContext," <> case has_auth {
        True -> "\n  identity identity: auth.Identity,"
        False -> ""
      } <> "
) -> #(String, ServerContext) {
  case decode.run(message, decode.field(\"type\", decode.string, fn(x) { decode.success(x) })) {
    Error(_) -> {
      let error_frame = " <> encode_prefix <> "encode_error(Some(request_id), [JsonError(\"type\", \"missing or not a string\")])
      #(error_frame, server_context)
    }\n" <> arms <> "\n" <> catch_all <> "\n  }\n}\n"
    }
  }
}

fn json_dispatch_arm(
  e: HandlerEndpoint,
  has_auth: Bool,
  encode_prefix: String,
) -> String {
  let alias = handler_alias(e.module_path)
  let #(type_module, type_name) = case e.msg_type {
    Some(#(mod, name)) -> #(mod, name)
    _ -> #(e.module_path, justin.pascal_case("server_" <> e.fn_name))
  }
  let type_str = type_module <> "." <> type_name
  let msg_decoder =
    "json_codecs.json_decode_"
    <> walker.qualified_atom_name(type_module, type_name)
  let handler_call = json_handler_call(e, alias, has_auth)
  let #(ok_destructure, ok_ctx) = case e.mutates_context {
    True -> #("#(result, new_ctx)", "new_ctx")
    False -> #("result", "server_context")
  }
  let response_encode = json_response_encode(e)

  "    Ok(\"" <> type_str <> "\") -> {
      case " <> msg_decoder <> "(message) {
        Error(errors) -> {
          let error_frame = " <> encode_prefix <> "encode_error(Some(request_id), errors)
          #(error_frame, server_context)
        }
        Ok(msg) -> {
          case trace.try_call(fn() { " <> handler_call <> " }) {
            Ok(" <> ok_destructure <> ") -> {
              " <> response_encode <> "
              let frame = " <> encode_prefix <> "encode_response(request_id, encoded)
              #(frame, " <> ok_ctx <> ")
            }
            Error(reason) -> {
              let trace_id = trace.new_trace_id()
              io.println_error(\"[libero] \" <> trace_id <> \" " <> e.fn_name <> ": \" <> reason)
              let error_frame = " <> encode_prefix <> "encode_error(Some(request_id), [JsonError(\"handler\", \"Something went wrong\")])
              #(error_frame, server_context)
            }
          }
        }
      }
    }"
}

fn json_handler_call(
  e: HandlerEndpoint,
  alias: String,
  has_auth: Bool,
) -> String {
  let extra = case has_auth {
    True -> ", identity:"
    False -> ""
  }
  case e.msg_type {
    Some(_) ->
      alias
      <> "."
      <> "server_"
      <> e.fn_name
      <> "(msg: msg, server_context: server_context"
      <> extra
      <> ")"
    _ -> {
      let labeled = list.map(e.params, fn(p) { p.0 <> ": " <> p.0 })
      let args =
        list.append(labeled, ["server_context: server_context" <> extra])
      alias
      <> "."
      <> "server_"
      <> e.fn_name
      <> "("
      <> string.join(args, ", ")
      <> ")"
    }
  }
}

fn json_response_encode(e: HandlerEndpoint) -> String {
  let ok_encoder = json_encoder_for_fieldtype(e.return_ok, "x")
  let err_encoder = json_encoder_for_fieldtype(e.return_err, "x")
  let ok_param = closure_param_for_fieldtype(e.return_ok)
  let err_param = closure_param_for_fieldtype(e.return_err)
  "let encoded = json_codecs.json_encode_gleam_result__result(result, fn("
  <> ok_param
  <> ") { "
  <> ok_encoder
  <> " }, fn("
  <> err_param
  <> ") { "
  <> err_encoder
  <> " })"
}

fn closure_param_for_fieldtype(ft: FieldType) -> String {
  case ft {
    NilField -> "_x"
    _ -> "x"
  }
}

fn json_encoder_for_fieldtype(ft: FieldType, var: String) -> String {
  case ft {
    StringField -> "json.string(" <> var <> ")"
    IntField -> "json.int(" <> var <> ")"
    FloatField -> "json.float(" <> var <> ")"
    BoolField -> "json.bool(" <> var <> ")"
    NilField -> "json.null()"
    BitArrayField -> "json.string(bit_array.base64_encode(" <> var <> ", True))"
    UserType(module_path:, type_name:, ..) ->
      "json_codecs.json_encode_"
      <> walker.qualified_atom_name(module_path, type_name)
      <> "("
      <> var
      <> ")"
    ListOf(inner) ->
      "json_codecs.json_encode_gleam__list("
      <> var
      <> ", fn(x) { "
      <> json_encoder_for_fieldtype(inner, "x")
      <> " })"
    OptionOf(inner) ->
      "json_codecs.json_encode_gleam_option__option("
      <> var
      <> ", fn(x) { "
      <> json_encoder_for_fieldtype(inner, "x")
      <> " })"
    ResultOf(ok, err) ->
      "json_codecs.json_encode_gleam_result__result("
      <> var
      <> ", fn(x) { "
      <> json_encoder_for_fieldtype(ok, "x")
      <> " }, fn(x) { "
      <> json_encoder_for_fieldtype(err, "x")
      <> " })"
    DictOf(_, _) -> "json_codecs.json_encode_gleam__dict(" <> var <> ")"
    TupleOf(_) -> "json_codecs.json_encode_gleam__tuple(" <> var <> ")"
    TypeVar(_) -> "panic as \"cannot encode type variable\""
  }
}

pub fn handler_imports(endpoints: List(HandlerEndpoint)) -> List(String) {
  endpoints
  |> list.map(fn(e) { e.module_path })
  |> list.unique()
  |> list.map(fn(mod) {
    let alias = handler_alias(mod)
    case string.split(mod, "/") |> list.last {
      Ok(seg) if seg == alias -> "import " <> mod
      _ -> "import " <> mod <> " as " <> alias
    }
  })
}
