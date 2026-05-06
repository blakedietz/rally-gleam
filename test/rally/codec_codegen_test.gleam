import gleam/string
import libero/field_type
import libero/walker.{DiscoveredType, DiscoveredVariant}
import rally/generator/codec

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
    string.contains(
      output,
      "Waiver as pages_admin_members_waivers_Waiver",
    )
  let assert True =
    string.contains(
      output,
      "Waiver as pages_admin_members_waivers_id__Waiver",
    )

  let assert False = has_bare_import(output, "{ Waiver }")
}

fn has_bare_import(output: String, bare: String) -> Bool {
  string.contains(output, bare)
}
