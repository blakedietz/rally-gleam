//// Page module parser using Glance AST.
//// Parses page source files to extract the page contract:
//// custom types (ToServer, ToClient) with full variant/field info,
//// and function presence (server_update, server_init, load, etc.).

import glance
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import lando/field_type.{type FieldType}
import lando/types.{
  type PageContract, type VariantInfo, PageContract, VariantField, VariantInfo,
}

/// Parse a page module source to extract the contract.
/// Uses Glance AST parsing for robust type extraction.
pub fn parse_page(source: String) -> Result(PageContract, String) {
  use ast <- result.try(
    glance.module(source)
    |> result.map_error(fn(e) { "Parse error: " <> string.inspect(e) }),
  )

  let type_imports = build_type_import_map(ast.imports)
  let alias_map = build_alias_resolution_map(ast.imports)
  let type_alias_originals = build_type_alias_originals(ast.imports)

  let to_server = extract_variants(
    ast: ast,
    type_name: "ToServer",
    type_imports: type_imports,
    alias_map: alias_map,
    type_alias_originals: type_alias_originals,
  )
  let to_client = extract_variants(
    ast: ast,
    type_name: "ToClient",
    type_imports: type_imports,
    alias_map: alias_map,
    type_alias_originals: type_alias_originals,
  )

  let functions_list = ast.functions
  let has_server_update = has_function(functions_list, "server_update")
  let has_server_init = has_function(functions_list, "server_init")
  let has_load = has_function(functions_list, "load")
  let has_init = has_function(functions_list, "init")
  let has_model = has_custom_type(ast.custom_types, "Model")

  let param_names = extract_init_params_from_ast(functions_list)

  Ok(PageContract(
    to_server_variants: to_server,
    to_client_variants: to_client,
    has_server_update:,
    has_server_init:,
    has_load:,
    has_init:,
    has_model:,
    param_names:,
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
) -> List(VariantInfo) {
  case
    list.find(ast.custom_types, fn(d) { d.definition.name == type_name })
  {
    Error(Nil) -> []
    Ok(ct_def) -> {
      let custom_type = ct_def.definition
      list.map(custom_type.variants, fn(variant) {
        let fields =
          list.map(variant.fields, fn(field) {
            let #(label, type_) = case field {
              glance.LabelledVariantField(item:, label:) ->
                #(label, item)
              glance.UnlabelledVariantField(item:) ->
                #("value", item)
            }
            VariantField(
              label:,
              type_: glance_type_to_field_type(
                type_:,
                type_imports:,
                alias_map:,
                type_alias_originals:,
              ),
            )
          })
        VariantInfo(name: variant.name, fields:)
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
) -> FieldType {
  let recurse = fn(t) {
    glance_type_to_field_type(
      type_: t,
      type_imports:,
      alias_map:,
      type_alias_originals:,
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
      )
    glance.NamedType(name:, module: None, parameters: params, ..) ->
      resolve_named_type(
        name:,
        params:,
        type_imports:,
        alias_map:,
        type_alias_originals:,
      )
    glance.NamedType(name:, module: Some(m), parameters: params, ..) -> {
      let resolved_module = dict.get(alias_map, m) |> result.unwrap(or: m)
      let original_name =
        dict.get(type_alias_originals, name) |> result.unwrap(or: name)
      field_type.UserType(
        module_path: resolved_module,
        type_name: original_name,
        args: list.map(params, recurse),
      )
    }
    glance.TupleType(elements:, ..) ->
      field_type.TupleOf(elements: list.map(elements, recurse))
    glance.VariableType(name:, ..) -> field_type.TypeVar(name:)
    glance.FunctionType(..) -> field_type.TypeVar(name: "_fn")
    glance.HoleType(..) -> field_type.TypeVar(name: "_")
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
) -> FieldType {
  let recurse = fn(t) {
    glance_type_to_field_type(
      type_: t,
      type_imports:,
      alias_map:,
      type_alias_originals:,
    )
  }
  case field_type.builtin_field_type(name:, parameters: params, recurse:) {
    Ok(ft) -> ft
    Error(Nil) -> {
      let module_path = dict.get(type_imports, name) |> result.unwrap(or: name)
      let type_name =
        dict.get(type_alias_originals, name) |> result.unwrap(or: name)
      field_type.UserType(
        module_path:,
        type_name:,
        args: list.map(params, recurse),
      )
    }
  }
}

// ---------- Import maps (from libero scanner) ----------

/// Build a map from unqualified type names to their full module paths.
pub fn build_type_import_map(
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
pub fn build_alias_resolution_map(
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
pub fn build_type_alias_originals(
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
