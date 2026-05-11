import gleam/list
import gleam/option
import gleam/string
import gleeunit/should
import libero/field_type.{IntField}
import libero/walker.{type DiscoveredType, DiscoveredType, DiscoveredVariant}
import rally/generator/codec.{
  generate_json_codecs, generate_json_decode_dispatch,
}

fn sample_discovered_types() -> List(DiscoveredType) {
  [
    DiscoveredType(
      module_path: "pages/home",
      type_name: "Model",
      type_params: [],
      variants: [
        DiscoveredVariant(
          module_path: "pages/home",
          variant_name: "Model",
          atom_name: "model",
          float_field_indices: [],
          field_labels: [option.Some("title"), option.Some("count")],
          fields: [IntField, IntField],
        ),
      ],
    ),
    DiscoveredType(
      module_path: "shared/items",
      type_name: "Item",
      type_params: [],
      variants: [
        DiscoveredVariant(
          module_path: "shared/items",
          variant_name: "Item",
          atom_name: "item",
          float_field_indices: [],
          field_labels: [option.Some("name")],
          fields: [IntField],
        ),
      ],
    ),
  ]
}

pub fn empty_json_codecs_returns_base_files_test() {
  let files = generate_json_codecs([], [])
  // Even with empty discovered types, the base codecs module and
  // dispatch module are still produced (just with no type cases)
  files |> list.length |> should.equal(2)
  let paths = list.map(files, fn(f) { f.path })
  paths |> list.contains("src/generated/json_codecs.gleam") |> should.be_true()
  paths
  |> list.contains("src/generated/json_decode_dispatch.gleam")
  |> should.be_true()
}

pub fn dispatch_has_correct_structure_test() {
  let dispatch = generate_json_decode_dispatch(sample_discovered_types())
  dispatch.path |> should.equal("src/generated/json_decode_dispatch.gleam")
  dispatch.content
  |> string.contains("pub fn decode_json_typed")
  |> should.be_true()
  dispatch.content
  |> string.contains("import gleam/dynamic.{type Dynamic}")
  |> should.be_true()
  dispatch.content |> string.contains("import gleam/result") |> should.be_true()
  dispatch.content
  |> string.contains("import generated/json_codecs as json_codecs")
  |> should.be_true()
  dispatch.content
  |> string.contains("import libero/json/error.{type JsonError, JsonError}")
  |> should.be_true()
  dispatch.content
  |> string.contains("fn identity(value: a) -> b")
  |> should.be_true()
  dispatch.content
  |> string.contains("decode_pages_home__model")
  |> should.be_true()
  dispatch.content
  |> string.contains("json_decode_pages_home__model(value)")
  |> should.be_true()
  dispatch.content
  |> string.contains("decode_shared_items__item")
  |> should.be_true()
  dispatch.content
  |> string.contains("json_decode_shared_items__item(value)")
  |> should.be_true()
  dispatch.content
  |> string.contains(
    "_ -> Error([JsonError(\"decoder\", \"unknown: \" <> decoder_name)])",
  )
  |> should.be_true()
  dispatch.content
  |> string.contains("Result(Dynamic, List(JsonError))")
  |> should.be_true()
}

pub fn generate_json_codecs_includes_dispatch_test() {
  let files = generate_json_codecs(sample_discovered_types(), [])
  files |> list.length |> should.equal(2)
  let paths = list.map(files, fn(f) { f.path })
  paths |> list.contains("src/generated/json_codecs.gleam") |> should.be_true()
  paths
  |> list.contains("src/generated/json_decode_dispatch.gleam")
  |> should.be_true()
}

pub fn empty_dispatch_has_no_type_cases_test() {
  let dispatch = generate_json_decode_dispatch([])
  dispatch.path |> should.equal("src/generated/json_decode_dispatch.gleam")
  dispatch.content
  |> string.contains("pub fn decode_json_typed")
  |> should.be_true()
  dispatch.content
  |> string.contains(
    "_ -> Error([JsonError(\"decoder\", \"unknown: \" <> decoder_name)])",
  )
  |> should.be_true()
  dispatch.content
  |> string.contains("decode_pages_home__model")
  |> should.be_false()
  dispatch.content
  |> string.contains("json_decode_pages_home__model")
  |> should.be_false()
}
