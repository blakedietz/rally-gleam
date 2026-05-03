//// Type graph walker for codec generation.
////
//// Walks the type graph starting from seed types (ToBackend/ToFrontend
//// from page contracts) to discover every custom type reachable through
//// the message types. Produces DiscoveredType/DiscoveredVariant lists
//// that the codec generator uses to emit typed JS decoders.
////
//// Adapted from libero's walker with Lando-specific simplifications:
//// - Seeds come from page contracts instead of shared/ directories
//// - File paths are resolved from the pages_root directory

import glance
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}
import gleam/string
import lando/field_type.{type FieldType, TupleOf, TypeVar, UserType}
import lando/parser
import simplifile

// ---------- Discovered types ----------

pub type DiscoveredType {
  DiscoveredType(
    module_path: String,
    type_name: String,
    type_params: List(String),
    variants: List(DiscoveredVariant),
  )
}

pub type DiscoveredVariant {
  DiscoveredVariant(
    module_path: String,
    variant_name: String,
    atom_name: String,
    float_field_indices: List(Int),
    fields: List(FieldType),
  )
}

// ---------- Type resolver ----------

type TypeResolver {
  TypeResolver(
    unqualified: Dict(String, String),
    aliased: Dict(String, String),
    original_names: Dict(String, String),
  )
}

// ---------- Walker state ----------

type WalkerState {
  WalkerState(
    queue: List(#(String, String)),
    visited: Set(#(String, String)),
    discovered: List(DiscoveredType),
    module_files: Dict(String, String),
    parsed_cache: Dict(String, glance.Module),
  )
}

const skip_prefixes = ["gleam/", "lustre/", "mist/", "marmot/", "sqlight/"]

fn is_skipped_module(module_path: String) -> Bool {
  list.any(skip_prefixes, fn(prefix) {
    string.starts_with(module_path, prefix)
  })
}

/// Walk the type graph starting from seed types extracted from page contracts.
/// Seeds are (module_path, type_name) pairs for ToBackend/ToFrontend types.
pub fn walk(
  seeds seeds: List(#(String, String)),
  page_files page_files: List(String),
  pages_root pages_root: String,
) -> List(DiscoveredType) {
  // Build module_files dict: module_path -> file_path
  let module_files =
    list.fold(page_files, dict.new(), fn(acc, file_path) {
      let module_path = derive_module_path(file_path, pages_root)
      dict.insert(acc, module_path, file_path)
    })

  let state = WalkerState(
    queue: seeds,
    visited: set.new(),
    discovered: [],
    module_files:,
    parsed_cache: dict.new(),
  )

  case do_walk(state) {
    Ok(discovered) -> discovered
    Error(_) -> []
  }
}

/// Derive a Gleam module path from a file path.
/// Strips the pages_root prefix and .gleam extension.
fn derive_module_path(file_path: String, pages_root: String) -> String {
  let without_ext = case string.ends_with(file_path, ".gleam") {
    True ->
      string.slice(
        from: file_path,
        at_index: 0,
        length: string.length(file_path) - string.length(".gleam"),
      )
    False -> file_path
  }
  // The module path is the file path relative to the pages_root's parent (src/)
  case string.split_once(without_ext, pages_root <> "/") {
    Ok(#(_, rest)) -> rest
    Error(_) -> without_ext
  }
}

// ---------- BFS walk ----------

fn do_walk(state: WalkerState) -> Result(List(DiscoveredType), Nil) {
  case state.queue {
    [] -> Ok(list.reverse(state.discovered))
    [#(module_path, type_name), ..rest_queue] -> {
      let key = #(module_path, type_name)
      case set.contains(state.visited, key) {
        True -> do_walk(WalkerState(..state, queue: rest_queue))
        False -> {
          let state =
            WalkerState(
              ..state,
              queue: rest_queue,
              visited: set.insert(state.visited, key),
            )
          process_type(module_path:, type_name:, state:)
        }
      }
    }
  }
}

fn process_type(
  module_path module_path: String,
  type_name type_name: String,
  state state: WalkerState,
) -> Result(List(DiscoveredType), Nil) {
  case dict.get(state.module_files, module_path) {
    Error(Nil) -> do_walk(state)
    Ok(file_path) ->
      process_type_file(module_path:, type_name:, file_path:, state:)
  }
}

fn process_type_file(
  module_path module_path: String,
  type_name type_name: String,
  file_path file_path: String,
  state state: WalkerState,
) -> Result(List(DiscoveredType), Nil) {
  // Parse or load from cache; skip on I/O or parse failure
  case get_or_parse_module(module_path, file_path, state) {
    Error(state) -> do_walk(state)
    Ok(#(ast, state)) ->
      process_type_ast(module_path, type_name, ast, state)
  }
}

fn get_or_parse_module(
  module_path: String,
  file_path: String,
  state: WalkerState,
) -> Result(#(glance.Module, WalkerState), WalkerState) {
  case dict.get(state.parsed_cache, module_path) {
    Ok(cached) -> Ok(#(cached, state))
    Error(Nil) ->
      case simplifile.read(file_path) {
        Error(_) -> Error(state)
        Ok(src) ->
          case glance.module(src) {
            Error(_) -> Error(state)
            Ok(parsed) ->
              Ok(#(
                parsed,
                WalkerState(
                  ..state,
                  parsed_cache: dict.insert(
                    state.parsed_cache,
                    module_path,
                    parsed,
                  ),
                ),
              ))
          }
      }
  }
}

fn process_type_ast(
  module_path: String,
  type_name: String,
  ast: glance.Module,
  state: WalkerState,
) -> Result(List(DiscoveredType), Nil) {
  // Check type aliases first (transparent resolution)
  case
    list.find(ast.type_aliases, fn(d) { d.definition.name == type_name })
  {
    Ok(alias_def) -> {
      let resolver = build_type_resolver(ast.imports)
      let target_refs =
        collect_type_refs(
          t: alias_def.definition.aliased,
          resolver:,
          current_module: module_path,
        )
      let new_refs =
        list.filter(target_refs, fn(ref) {
          let #(ref_module, ref_type) = ref
          !set.contains(state.visited, ref)
            && !is_skipped_module(ref_module)
            && !field_type.is_builtin(ref_type)
        })
      do_walk(WalkerState(..state, queue: list.append(new_refs, state.queue)))
    }
    Error(Nil) ->
      process_custom_type(module_path, type_name, ast, state)
  }
}

fn process_custom_type(
  module_path: String,
  type_name: String,
  ast: glance.Module,
  state: WalkerState,
) -> Result(List(DiscoveredType), Nil) {
  case
    list.find(ast.custom_types, fn(d) { d.definition.name == type_name })
  {
    Error(Nil) -> do_walk(state)
    Ok(ct_def) -> {
      let custom_type = ct_def.definition
      let resolver = build_type_resolver(ast.imports)
      let aliases = build_alias_map(ast.type_aliases)

      let #(variants_rev, new_queue_rev) =
        list.fold(custom_type.variants, #([], []), fn(acc, variant) {
          let #(disc_acc, queue_acc) = acc
          let float_indices = detect_float_fields(variant.fields)
          let fields =
            list.map(variant.fields, fn(field) {
              field_type_of(
                t: variant_field_type(field),
                resolver:,
                aliases:,
                current_module: module_path,
              )
            })
          let disc_item =
            DiscoveredVariant(
              module_path: module_path,
              variant_name: variant.name,
              atom_name: to_snake_case(variant.name),
              float_field_indices: float_indices,
              fields:,
            )
          let field_refs =
            collect_variant_field_refs(
              variant: variant,
              resolver: resolver,
              current_module: module_path,
              visited: state.visited,
            )
          #([disc_item, ..disc_acc], list.append(field_refs, queue_acc))
        })

      let discovered_type =
        DiscoveredType(
          module_path: module_path,
          type_name: type_name,
          type_params: custom_type.parameters,
          variants: list.reverse(variants_rev),
        )
      do_walk(
        WalkerState(
          ..state,
          queue: list.append(list.reverse(new_queue_rev), state.queue),
          discovered: [discovered_type, ..state.discovered],
        ),
      )
    }
  }
}

// ---------- Field type detection ----------

fn detect_float_fields(fields: List(glance.VariantField)) -> List(Int) {
  list.index_fold(fields, [], fn(acc, field, index) {
    case is_float_type(variant_field_type(field)) {
      True -> [index, ..acc]
      False -> acc
    }
  })
  |> list.reverse
}

fn is_float_type(t: glance.Type) -> Bool {
  case t {
    glance.NamedType(name: "Float", module: None, ..) -> True
    glance.NamedType(name: "Float", module: Some("gleam"), ..) -> True
    _ -> False
  }
}

fn variant_field_type(field: glance.VariantField) -> glance.Type {
  case field {
    glance.LabelledVariantField(item:, ..) -> item
    glance.UnlabelledVariantField(item:) -> item
  }
}

// ---------- Type ref collection ----------

fn collect_variant_field_refs(
  variant variant: glance.Variant,
  resolver resolver: TypeResolver,
  current_module current_module: String,
  visited visited: Set(#(String, String)),
) -> List(#(String, String)) {
  let field_refs =
    list.flat_map(variant.fields, fn(field) {
      collect_type_refs(
        t: variant_field_type(field),
        resolver:,
        current_module:,
      )
    })
  list.filter(field_refs, fn(ref) {
    let #(ref_module, ref_type) = ref
    !set.contains(visited, ref)
      && !is_skipped_module(ref_module)
      && !field_type.is_builtin(ref_type)
  })
}

fn collect_type_refs(
  t t: glance.Type,
  resolver resolver: TypeResolver,
  current_module current_module: String,
) -> List(#(String, String)) {
  case t {
    glance.NamedType(name:, module:, parameters:, ..) -> {
      let param_refs =
        list.flat_map(parameters, fn(p) {
          collect_type_refs(t: p, resolver:, current_module:)
        })
      case is_stdlib_reference(name:, module:, resolver:) {
        True -> param_refs
        False ->
          case
            resolve_type_module(
              name:,
              module:,
              resolver:,
              current_module:,
            )
          {
            Error(Nil) -> param_refs
            Ok(mp) -> {
              case is_skipped_module(mp) {
                True -> param_refs
                False -> {
                  let original_name =
                    result.unwrap(
                      dict.get(resolver.original_names, name),
                      name,
                    )
                  [#(mp, original_name), ..param_refs]
                }
              }
            }
          }
      }
    }
    glance.TupleType(elements:, ..) ->
      list.flat_map(elements, fn(e) {
        collect_type_refs(t: e, resolver:, current_module:)
      })
    glance.FunctionType(..) -> []
    glance.VariableType(..) -> []
    glance.HoleType(..) -> []
  }
}

fn resolve_type_module(
  name name: String,
  module module: Option(String),
  resolver resolver: TypeResolver,
  current_module current_module: String,
) -> Result(String, Nil) {
  case module {
    Some(alias) -> dict.get(resolver.aliased, alias)
    None ->
      case dict.get(resolver.unqualified, name) {
        Ok(mp) -> Ok(mp)
        Error(Nil) -> Ok(current_module)
      }
  }
}

fn is_stdlib_reference(
  name name: String,
  module module: Option(String),
  resolver resolver: TypeResolver,
) -> Bool {
  case field_type.is_builtin(name), module {
    False, _ -> False
    True, Some("gleam") -> True
    True, Some("option") -> name == "Option"
    True, Some("result") -> name == "Result"
    True, Some("dict") -> name == "Dict"
    True, Some("list") -> name == "List"
    True, Some("bool") -> name == "Bool"
    True, Some("bit_array") -> name == "BitArray"
    True, Some(_) -> False
    True, None ->
      case dict.get(resolver.unqualified, name) {
        Error(Nil) -> True
        Ok(module_path) ->
          module_path == "gleam" || string.starts_with(module_path, "gleam/")
      }
  }
}

// ---------- Field type conversion ----------

fn field_type_of(
  t t: glance.Type,
  resolver resolver: TypeResolver,
  aliases aliases: Dict(String, glance.Type),
  current_module current_module: String,
) -> FieldType {
  case t {
    glance.VariableType(name:, ..) -> TypeVar(name:)
    glance.TupleType(elements:, ..) ->
      TupleOf(
        list.map(elements, fn(e) {
          field_type_of(t: e, resolver:, aliases:, current_module:)
        }),
      )
    glance.FunctionType(..) -> TypeVar(name: "_fn")
    glance.HoleType(..) -> TypeVar(name: "_")
    glance.NamedType(name:, module:, parameters:, ..) ->
      case is_stdlib_reference(name:, module:, resolver:) {
        True ->
          stdlib_field_type(name:, parameters:, resolver:, aliases:, current_module:)
        False ->
          resolve_field_type(name:, module:, parameters:, resolver:, aliases:, current_module:)
      }
  }
}

fn stdlib_field_type(
  name name: String,
  parameters parameters: List(glance.Type),
  resolver resolver: TypeResolver,
  aliases aliases: Dict(String, glance.Type),
  current_module current_module: String,
) -> FieldType {
  let recurse = fn(t) {
    field_type_of(t:, resolver:, aliases:, current_module:)
  }
  case field_type.builtin_field_type(name:, parameters:, recurse:) {
    Ok(ft) -> ft
    Error(Nil) ->
      UserType(
        module_path: current_module,
        type_name: name,
        args: list.map(parameters, recurse),
      )
  }
}

fn resolve_field_type(
  name name: String,
  module module: Option(String),
  parameters parameters: List(glance.Type),
  resolver resolver: TypeResolver,
  aliases aliases: Dict(String, glance.Type),
  current_module current_module: String,
) -> FieldType {
  case module, dict.get(aliases, name) {
    None, Ok(aliased_type) ->
      field_type_of(t: aliased_type, resolver:, aliases:, current_module:)
    _, _ -> {
      let args =
        list.map(parameters, fn(p) {
          field_type_of(t: p, resolver:, aliases:, current_module:)
        })
      let resolved_module =
        resolve_type_module(name:, module:, resolver:, current_module:)
      let mp = result.unwrap(resolved_module, current_module)
      let original_name =
        result.unwrap(dict.get(resolver.original_names, name), name)
      UserType(module_path: mp, type_name: original_name, args:)
    }
  }
}

// ---------- Resolver + alias construction ----------

fn build_type_resolver(
  imports: List(glance.Definition(glance.Import)),
) -> TypeResolver {
  TypeResolver(
    unqualified: parser.build_type_import_map(imports),
    aliased: parser.build_alias_resolution_map(imports),
    original_names: parser.build_type_alias_originals(imports),
  )
}

fn build_alias_map(
  type_aliases: List(glance.Definition(glance.TypeAlias)),
) -> Dict(String, glance.Type) {
  list.fold(type_aliases, dict.new(), fn(acc, def) {
    dict.insert(acc, def.definition.name, def.definition.aliased)
  })
}

// ---------- snake_case conversion ----------

pub fn to_snake_case(name: String) -> String {
  let graphemes = string.to_graphemes(name)
  let triples = build_triples(remaining: graphemes, prev: "")
  list.index_fold(triples, "", fn(acc, triple, i) {
    let #(prev, g, next) = triple
    case i == 0, is_upper_grapheme(g) {
      True, _ -> acc <> string.lowercase(g)
      False, True -> {
        let prev_upper = is_upper_grapheme(prev)
        let next_lower = next != "" && !is_upper_grapheme(next)
        case prev_upper, next_lower {
          True, True -> acc <> "_" <> string.lowercase(g)
          True, False -> acc <> string.lowercase(g)
          _, _ -> acc <> "_" <> string.lowercase(g)
        }
      }
      False, False -> acc <> g
    }
  })
}

fn build_triples(
  remaining remaining: List(String),
  prev prev: String,
) -> List(#(String, String, String)) {
  case remaining {
    [] -> []
    [g] -> [#(prev, g, "")]
    [g, next, ..rest] -> [
      #(prev, g, next),
      ..build_triples(remaining: [next, ..rest], prev: g)
    ]
  }
}

fn is_upper_grapheme(g: String) -> Bool {
  g != string.lowercase(g)
}
