import gleam/list
import gleam/option
import gleam/string
import libero/field_type
import libero/walker.{DiscoveredType, DiscoveredVariant}
import rally/generator/codec
import rally/types.{PageContract, ScannedRoute}

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
  let files = codec.generate([], [], option.None, [], [])
  let assert Ok(file) =
    list.find(files, fn(file) {
      file.path == "src/rally_runtime/rally_effect_ffi.mjs"
    })

  let assert True = string.contains(file.content, "navigator.language")
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
  let files = codec.generate([#(route, contract)], [], option.None, [], [])
  let assert Ok(file) =
    list.find(files, fn(file) { file.path == "src/pages/home_.gleam" })

  let assert True = string.contains(file.content, "send_to_server (Send)")
  let assert False = string.contains(file.content, "fx.send_to_server")
  let assert True = string.contains(file.content, "import generated/transport")
}

fn has_bare_import(output: String, bare: String) -> Bool {
  string.contains(output, bare)
}
