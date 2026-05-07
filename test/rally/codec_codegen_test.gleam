import gleam/list
import gleam/option
import gleam/string
import gleeunit/should
import libero/field_type
import libero/scanner
import libero/walker.{DiscoveredType, DiscoveredVariant}
import rally/generator/codec
import rally/types.{PageContract, ScannedRoute}
import simplifile

pub fn duplicate_constructor_names_get_aliased_imports_test() {
  let discovered = [
    DiscoveredType(
      module_path: "pages/admin/members/waivers",
      type_name: "Waiver",
      type_params: [],
      variants: [
        DiscoveredVariant(
          module_path: "pages/admin/members/waivers",
          variant_name: "Waiver",
          atom_name: "waiver",
          float_field_indices: [],
          fields: [field_type.IntField],
        ),
      ],
    ),
    DiscoveredType(
      module_path: "pages/admin/members/waivers/id_",
      type_name: "Waiver",
      type_params: [],
      variants: [
        DiscoveredVariant(
          module_path: "pages/admin/members/waivers/id_",
          variant_name: "Waiver",
          atom_name: "waiver",
          float_field_indices: [],
          fields: [field_type.IntField, field_type.StringField],
        ),
      ],
    ),
  ]

  let output = codec.emit_codec_ffi(discovered)

  let assert True =
    string.contains(output, "Waiver as pages_admin_members_waivers_Waiver")
  let assert True =
    string.contains(output, "Waiver as pages_admin_members_waivers_id__Waiver")

  let assert False = has_bare_import(output, "{ Waiver }")
}

pub fn generated_effect_lang_falls_back_to_browser_language_test() {
  let files = codec.generate([], [], option.None, "client_context", [], [])
  let assert Ok(file) =
    list.find(files, fn(file) {
      file.path == "src/rally_runtime/rally_effect_ffi.mjs"
    })

  let assert True = string.contains(file.content, "navigator.language")
}

pub fn generated_decode_flags_rejects_empty_flags_before_decoding_test() {
  let files = codec.generate([], [], option.None, "client_context", [], [])
  let assert Ok(file) =
    list.find(files, fn(file) { file.path == "src/generated/codec.gleam" })

  let assert True =
    string.contains(file.content, "\"\" -> Error(\"No flags present\")")
  let assert True =
    string.contains(file.content, "Failed to base64-decode flags")
  let assert True = string.contains(file.content, "transport.decode_safe(bits)")
  let assert True =
    string.contains(file.content, "Failed to ETF-decode flags: ")
  let assert False = string.contains(file.content, "transport.decode(bits)")
}

pub fn codec_ffi_registers_nested_float_endpoint_field_types_test() {
  let endpoint =
    scanner.HandlerEndpoint(
      module_path: "pages/measurements",
      fn_name: "record_measurements",
      return_ok: field_type.NilField,
      return_err: field_type.NilField,
      params: [
        #("values", field_type.ListOf(field_type.FloatField)),
      ],
      mutates_context: False,
      msg_type_name: option.None,
    )
  let files =
    codec.generate([], [], option.None, "client_context", [endpoint], [])
  let assert Ok(file) =
    list.find(files, fn(file) { file.path == "src/generated/codec_ffi.mjs" })

  let assert True =
    string.contains(
      file.content,
      "import { registerConstructor, registerFieldTypes } from \"./rpc_ffi.mjs\";",
    )
  let assert True =
    string.contains(
      file.content,
      "registerFieldTypes(\"server_record_measurements\", [{ kind: \"list\", element: \"float\" }]);",
    )
  let assert False = string.contains(file.content, "registerFloatFields")
}

pub fn copied_rpc_runtime_exposes_only_field_type_float_api_test() {
  let assert Ok(source) = simplifile.read("src/rally_runtime/rpc_ffi.mjs")

  let assert True =
    string.contains(source, "export function registerFieldTypes")
  let assert False = string.contains(source, "registerFloatFields")
  let assert False = string.contains(source, "floatFieldRegistry")
}

pub fn rpc_runtime_routes_framework_errors_outside_user_callbacks_test() {
  let assert Ok(source) = simplifile.read("src/rally_runtime/rpc_ffi.mjs")

  source
  |> string.contains("export function registerRpcErrorHandler(handler)")
  |> should.equal(True)
  source
  |> string.contains("entry.callback(decoded[0])")
  |> should.equal(True)
  source
  |> string.contains("invokeRpcErrorHandler(frameworkError")
  |> should.equal(True)
  source
  |> string.contains("invokeRpcErrorHandler(error, \"RPC request failed\")")
  |> should.equal(True)
  source
  |> string.contains(
    "invokeRpcErrorHandler(makeConnectionError(\"Request timed out\")",
  )
  |> should.equal(True)
  source
  |> string.contains("entry.callback(error)")
  |> should.equal(False)
  source
  |> string.contains("callback(makeConnectionError")
  |> should.equal(False)
}

pub fn page_post_process_handles_effect_alias_for_send_to_server_test() {
  let contract =
    PageContract(
      model_variants: [],
      msg_variants: [],
      has_load: False,
      has_init: True,
      has_init_loaded: False,
      has_model: True,
      updates_client_context: False,
      param_names: [],
      source: "
import rally_runtime/effect as fx
pub type Model { Model }
pub type Msg { Send }
pub fn update(model, msg) {
  case msg {
    Send -> #(model, fx.send_to_server (Send))
  }
}
",
      view_source: "",
      init_source: "",
      update_source: "",
    )
  let route =
    ScannedRoute(
      segments: [],
      variant_name: "Home",
      params: [],
      layout_module: option.None,
      module_path: "pages/home_",
    )
  let files =
    codec.generate(
      [#(route, contract)],
      [],
      option.None,
      "client_context",
      [],
      [],
    )
  let assert Ok(file) =
    list.find(files, fn(file) { file.path == "src/pages/home_.gleam" })

  let assert True = string.contains(file.content, "send_to_server (Send)")
  let assert False = string.contains(file.content, "fx.send_to_server")
  let assert True = string.contains(file.content, "import generated/transport")
}

pub fn namespaced_client_context_imports_from_namespaced_module_test() {
  let source =
    "
pub type ClientContext {
  ClientContext(current_path: String)
}
"
  let files =
    codec.generate([], [], option.Some(source), "public/client_context", [], [])
  let assert Ok(file) =
    list.find(files, fn(file) { file.path == "src/generated/codec_ffi.mjs" })

  file.content
  |> string.contains("from \"../public/client_context.mjs\";")
  |> should.equal(True)

  file.content
  |> string.contains("from \"../client_context.mjs\";")
  |> should.equal(False)
}

fn has_bare_import(output: String, bare: String) -> Bool {
  string.contains(output, bare)
}
