//// Page module parser using Glance AST.
//// Parses page source files to extract the page contract:
//// custom types (ToServer, ToClient) with full variant/field info,
//// and function presence (server_update, server_init, load, etc.).

import glance
import gleam/dict.{type Dict}
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import libero/field_type.{type FieldType}
import rally/types.{
  type ClientContextContract, type PageContract, type VariantInfo,
  ClientContextContract, PageContract, VariantField, VariantInfo,
}

/// Parse a page module source to extract the contract.
/// Uses Glance AST parsing for robust type extraction.
pub fn parse_page(
  source source: String,
  module_path module_path: String,
) -> Result(PageContract, String) {
  use ast <- result.try(
    glance.module(source)
    |> result.map_error(fn(e) {
      io.println_error("Parse error: " <> glance_to_string(e))
      "Parse error"
    }),
  )

  let type_imports = build_type_import_map(ast.imports)
  let alias_map = build_alias_resolution_map(ast.imports)
  let type_alias_originals = build_type_alias_originals(ast.imports)

  use model_variants <- result.try(extract_variants(
    ast: ast,
    type_name: "Model",
    type_imports: type_imports,
    alias_map: alias_map,
    type_alias_originals: type_alias_originals,
    module_path: module_path,
  ))
  use msg_variants <- result.try(extract_variants(
    ast: ast,
    type_name: "Msg",
    type_imports: type_imports,
    alias_map: alias_map,
    type_alias_originals: type_alias_originals,
    module_path: module_path,
  ))

  let functions_list = ast.functions
  let has_load = has_function(functions_list, "load")
  let has_init = has_function(functions_list, "init")
  let has_init_loaded = has_function(functions_list, "init_loaded")
  let has_model =
    has_custom_type(ast.custom_types, "Model")
    || has_type_alias(ast.type_aliases, "Model")

  let param_names = extract_init_params_from_ast(functions_list)

  let view_source =
    extract_function_source(
      source: source,
      functions: functions_list,
      name: "view",
    )
  let init_source =
    extract_function_source(
      source: source,
      functions: functions_list,
      name: "init",
    )
  let update_source =
    extract_function_source(
      source: source,
      functions: functions_list,
      name: "update",
    )
  let updates_client_context =
    string.contains(update_source, "ClientContextMsg")

  Ok(PageContract(
    model_variants:,
    msg_variants:,
    has_load:,
    has_init:,
    has_init_loaded:,
    has_model:,
    updates_client_context:,
    param_names:,
    source:,
    view_source:,
    init_source:,
    update_source:,
  ))
}

/// Parse a client_context.gleam source to extract the contract.
pub fn parse_client_context(
  source: String,
) -> Result(ClientContextContract, String) {
  use ast <- result.try(
    glance.module(source)
    |> result.map_error(fn(e) {
      io.println_error("Parse error: " <> glance_to_string(e))
      "Parse error"
    }),
  )

  let type_imports = build_type_import_map(ast.imports)
  let alias_map = build_alias_resolution_map(ast.imports)
  let type_alias_originals = build_type_alias_originals(ast.imports)

  use context_variants <- result.try(extract_variants(
    ast: ast,
    type_name: "ClientContext",
    type_imports: type_imports,
    alias_map: alias_map,
    type_alias_originals: type_alias_originals,
    module_path: "client_context",
  ))
  use msg_variants <- result.try(extract_variants(
    ast: ast,
    type_name: "ClientContextMsg",
    type_imports: type_imports,
    alias_map: alias_map,
    type_alias_originals: type_alias_originals,
    module_path: "client_context",
  ))

  let functions_list = ast.functions
  let has_init = has_function(functions_list, "init")
  let has_update = has_function(functions_list, "update")

  Ok(ClientContextContract(
    context_variants:,
    msg_variants:,
    has_init:,
    has_update:,
  ))
}

// ---------- Type extraction ----------

/// Extract all variants of a named custom type, with field type info.
fn extract_variants(
  ast ast: glance.Module,
  type_name type_name: String,
  type_imports type_imports: Dict(String, String),
  alias_map alias_map: Dict(String, String),
  type_alias_originals type_alias_originals: Dict(String, String),
  module_path module_path: String,
) -> Result(List(VariantInfo), String) {
  case list.find(ast.custom_types, fn(d) { d.definition.name == type_name }) {
    Error(Nil) -> Ok([])
    Ok(ct_def) -> {
      let custom_type = ct_def.definition
      list.try_map(custom_type.variants, fn(variant) {
        use fields <- result.try(
          list.try_map(variant.fields, fn(field) {
            let #(label, type_) = case field {
              glance.LabelledVariantField(item:, label:) -> #(label, item)
              glance.UnlabelledVariantField(item:) -> #("value", item)
            }
            use field_type <- result.try(glance_type_to_field_type(
              type_:,
              type_imports:,
              alias_map:,
              type_alias_originals:,
              module_path:,
              path: module_path <> "." <> type_name <> "." <> label,
            ))
            Ok(VariantField(label:, type_: field_type))
          }),
        )
        Ok(VariantInfo(name: variant.name, fields:))
      })
    }
  }
}

/// Convert a glance.Type to a FieldType, resolving named types via import maps.
fn glance_type_to_field_type(
  type_ t: glance.Type,
  type_imports type_imports: Dict(String, String),
  alias_map alias_map: Dict(String, String),
  type_alias_originals type_alias_originals: Dict(String, String),
  module_path module_path: String,
  path path: String,
) -> Result(FieldType, String) {
  let recurse = fn(t) {
    glance_type_to_field_type(
      type_: t,
      type_imports:,
      alias_map:,
      type_alias_originals:,
      module_path:,
      path:,
    )
  }
  case t {
    glance.NamedType(name:, module: None, parameters: [], ..) ->
      resolve_named_type(
        name:,
        params: [],
        type_imports:,
        alias_map:,
        type_alias_originals:,
        module_path:,
        path:,
      )
    glance.NamedType(name:, module: None, parameters: params, ..) ->
      resolve_named_type(
        name:,
        params:,
        type_imports:,
        alias_map:,
        type_alias_originals:,
        module_path:,
        path:,
      )
    glance.NamedType(name:, module: Some(m), parameters: params, ..) -> {
      let resolved_module = dict.get(alias_map, m) |> result.unwrap(or: m)
      let original_name =
        dict.get(type_alias_originals, name) |> result.unwrap(or: name)
      use args <- result.try(list.try_map(params, recurse))
      Ok(field_type.UserType(
        module_path: resolved_module,
        type_name: original_name,
        args:,
      ))
    }
    glance.TupleType(elements:, ..) -> {
      use elements <- result.try(list.try_map(elements, recurse))
      Ok(field_type.TupleOf(elements:))
    }
    glance.VariableType(name:, ..) -> Ok(field_type.TypeVar(name:))
    glance.FunctionType(..) -> Error("Unsupported function type in " <> path)
    glance.HoleType(..) -> Error("Unsupported hole type in " <> path)
  }
}

/// Resolve an unqualified named type. Builtins return their FieldType directly.
/// Other names look up the module path from imports.
fn resolve_named_type(
  name name: String,
  params params: List(glance.Type),
  type_imports type_imports: Dict(String, String),
  alias_map alias_map: Dict(String, String),
  type_alias_originals type_alias_originals: Dict(String, String),
  module_path module_path: String,
  path path: String,
) -> Result(FieldType, String) {
  let recurse = fn(t) {
    glance_type_to_field_type(
      type_: t,
      type_imports:,
      alias_map:,
      type_alias_originals:,
      module_path:,
      path:,
    )
  }
  case name, params {
    "Int", [] -> Ok(field_type.IntField)
    "Float", [] -> Ok(field_type.FloatField)
    "String", [] -> Ok(field_type.StringField)
    "Bool", [] -> Ok(field_type.BoolField)
    "BitArray", [] -> Ok(field_type.BitArrayField)
    "Nil", [] -> Ok(field_type.NilField)
    "List", [elem] -> {
      use elem <- result.try(recurse(elem))
      Ok(field_type.ListOf(element: elem))
    }
    "Option", [inner] -> {
      use inner <- result.try(recurse(inner))
      Ok(field_type.OptionOf(inner:))
    }
    "Result", [ok, err] -> {
      use ok <- result.try(recurse(ok))
      use err <- result.try(recurse(err))
      Ok(field_type.ResultOf(ok:, err:))
    }
    "Dict", [key, value] -> {
      use key <- result.try(recurse(key))
      use value <- result.try(recurse(value))
      Ok(field_type.DictOf(key:, value:))
    }
    _, _ -> {
      let resolved_module =
        dict.get(type_imports, name) |> result.unwrap(or: module_path)
      let type_name =
        dict.get(type_alias_originals, name) |> result.unwrap(or: name)
      use args <- result.try(list.try_map(params, recurse))
      Ok(field_type.UserType(module_path: resolved_module, type_name:, args:))
    }
  }
}

// ---------- Import maps (from libero scanner) ----------

/// Build a map from unqualified type names to their full module paths.
fn build_type_import_map(
  imports: List(glance.Definition(glance.Import)),
) -> Dict(String, String) {
  list.fold(imports, dict.new(), fn(acc, def) {
    let glance.Definition(_, imp) = def
    list.fold(imp.unqualified_types, acc, fn(inner_acc, uq) {
      let key = case uq.alias {
        Some(alias) -> alias
        None -> uq.name
      }
      dict.insert(inner_acc, key, imp.module)
    })
  })
}

/// Build a map from module aliases to full paths.
fn build_alias_resolution_map(
  imports: List(glance.Definition(glance.Import)),
) -> Dict(String, String) {
  list.fold(imports, dict.new(), fn(acc, def) {
    let glance.Definition(_, imp) = def
    let last_seg = field_type.last_segment(imp.module)
    let alias = case imp.alias {
      Some(glance.Named(name)) -> name
      _ -> last_seg
    }
    dict.insert(acc, alias, imp.module)
  })
}

/// Build a map from aliased type names to original names.
fn build_type_alias_originals(
  imports: List(glance.Definition(glance.Import)),
) -> Dict(String, String) {
  list.fold(imports, dict.new(), fn(acc, def) {
    let glance.Definition(_, imp) = def
    list.fold(imp.unqualified_types, acc, fn(inner_acc, uq) {
      case uq.alias {
        Some(alias) -> dict.insert(inner_acc, alias, uq.name)
        None -> inner_acc
      }
    })
  })
}

// ---------- Function detection ----------

/// Extract the source text of a named public function using AST span positions.
fn extract_function_source(
  source source: String,
  functions functions: List(glance.Definition(glance.Function)),
  name name: String,
) -> String {
  case
    list.find(functions, fn(def) {
      def.definition.name == name && def.definition.publicity == glance.Public
    })
  {
    Error(Nil) -> ""
    Ok(func_def) -> {
      let glance.Function(location: glance.Span(start:, end:), ..) =
        func_def.definition
      case string.length(source) >= end {
        True -> string.slice(from: source, at_index: start, length: end - start)
        False -> ""
      }
    }
  }
}

fn has_function(
  functions: List(glance.Definition(glance.Function)),
  name: String,
) -> Bool {
  list.any(functions, fn(def) {
    def.definition.name == name && def.definition.publicity == glance.Public
  })
}

fn has_custom_type(
  custom_types: List(glance.Definition(glance.CustomType)),
  name: String,
) -> Bool {
  list.any(custom_types, fn(def) { def.definition.name == name })
}

fn has_type_alias(
  type_aliases: List(glance.Definition(glance.TypeAlias)),
  name: String,
) -> Bool {
  list.any(type_aliases, fn(def) { def.definition.name == name })
}

/// Extract parameter names from the `init` function AST.
fn extract_init_params_from_ast(
  functions: List(glance.Definition(glance.Function)),
) -> List(String) {
  case
    list.find(functions, fn(def) {
      def.definition.name == "init" && def.definition.publicity == glance.Public
    })
  {
    Error(Nil) -> []
    Ok(func_def) ->
      list.filter_map(func_def.definition.parameters, fn(param) {
        case param {
          glance.FunctionParameter(label: Some(label), ..) -> Ok(label)
          glance.FunctionParameter(
            label: None,
            name: glance.Named(name),
            type_: Some(_),
          ) -> Ok(name)
          _ -> Error(Nil)
        }
      })
  }
}

fn glance_to_string(err: glance.Error) -> String {
  case err {
    glance.UnexpectedEndOfInput -> "unexpected end of input"
    glance.UnexpectedToken(token: _, position:) ->
      "unexpected token at byte offset " <> int.to_string(position.byte_offset)
  }
}
