//// Client package codec and page module generator.
////
//// Generates:
//// - codec_ffi.mjs — JS typed decoders (from walker-discovered types)
//// - types.gleam — ClientMsg type for RPC dispatch
//// - codec.gleam — decode_flags utility
//// - Per-page client modules — tree-shaken page source
//// - rally_runtime/effect.gleam — client-side effect shim

import glance
import gleam/dict
import gleam/list
import gleam/option
import gleam/set
import gleam/string
import libero/codegen
import libero/codegen_decoders
import libero/field_type.{type FieldType, UserType}
import libero/scanner.{type HandlerEndpoint}
import libero/walker.{
  type DiscoveredType,
}
import rally/tree_shaker
import rally/types.{type PageContract, type ScannedRoute}

pub type CodecFile {
  CodecFile(path: String, content: String)
}

/// Generate all codec files for the client package.
pub fn generate(
  contracts: List(#(ScannedRoute, PageContract)),
  discovered: List(DiscoveredType),
  endpoints: List(HandlerEndpoint),
  server_symbols: List(String),
) -> List(CodecFile) {
  let codec_files = [
    CodecFile(
      "src/generated/codec_ffi.mjs",
      emit_codec_ffi_with_endpoints(discovered, endpoints),
    ),
    CodecFile(
      "src/generated/types.gleam",
      emit_types_gleam(contracts, endpoints),
    ),
    CodecFile("src/generated/codec.gleam", emit_codec_gleam()),
    CodecFile("src/rally_runtime/effect.gleam", emit_rally_effect_shim()),
    CodecFile("src/rally_runtime/rally_effect_ffi.mjs", emit_rally_effect_ffi()),
  ]

  let page_files = generate_page_modules(contracts, server_symbols)

  list.append(codec_files, page_files)
}

/// Generate per-page client modules from tree-shaken source.
fn generate_page_modules(
  contracts: List(#(ScannedRoute, PageContract)),
  server_symbols: List(String),
) -> List(CodecFile) {
  list.filter_map(contracts, fn(pair) {
    let #(route, contract) = pair
    case contract.has_model {
      False -> Error(Nil)
      True -> {
        let shaken = tree_shaker.shake(contract.source, server_symbols:)
        let page_path = page_module_path(route.module_path)
        let content = post_process_page(shaken, route.variant_name)
        Ok(CodecFile("src/" <> page_path <> ".gleam", content))
      }
    }
  })
}

/// Convert a server module path to a client page path.
/// "pages/home_" -> "pages/home_"
/// "pages/article/slug_" -> "pages/article/slug_"
fn page_module_path(module_path: String) -> String {
  module_path
}

/// Post-process tree-shaken source for client usage:
/// - Replace rally_effect.send_to_server with local wrapper
/// - Add transport import and local send_to_server wrapper
fn post_process_page(source: String, variant_name: String) -> String {
  let effect_aliases = effect_module_aliases(source)
  let has_send_to_server =
    list.any(effect_aliases, fn(alias) {
      string.contains(source, alias <> ".send_to_server(")
      || string.contains(source, alias <> ".send_to_server (")
    })

  let wrapper = case has_send_to_server {
    True ->
      "\nimport generated/transport\n"
      <> "\nfn send_to_server(msg: a) -> effect.Effect(b) {\n"
      <> "  effect.from(fn(_dispatch) {\n"
      <> "    transport.send_to_server(\""
      <> variant_name
      <> "\", msg)\n"
      <> "    Nil\n"
      <> "  })\n"
      <> "}\n"
    False -> ""
  }

  source
  |> replace_send_to_server_calls(effect_aliases)
  |> drop_unused_effect_import(effect_aliases)
  |> fn(s) { s <> wrapper }
}

fn effect_module_aliases(source: String) -> List(String) {
  case glance.module(source) {
    Error(_) -> ["rally_effect"]
    Ok(ast) ->
      ast.imports
      |> list.filter_map(fn(def) {
        let import_ = def.definition
        case import_.module == "rally_runtime/effect" {
          False -> Error(Nil)
          True ->
            case import_.alias {
              option.Some(glance.Named(name)) -> Ok(name)
              _ -> Ok("effect")
            }
        }
      })
      |> fn(aliases) {
        case aliases {
          [] -> ["rally_effect"]
          _ -> aliases
        }
      }
  }
}

fn replace_send_to_server_calls(
  source: String,
  aliases: List(String),
) -> String {
  list.fold(aliases, source, fn(acc, alias) {
    acc
    |> string.replace(alias <> ".send_to_server(", "send_to_server(")
    |> string.replace(alias <> ".send_to_server (", "send_to_server (")
  })
}

fn drop_unused_effect_import(source: String, aliases: List(String)) -> String {
  let alias_still_used =
    list.any(aliases, fn(alias) { string.contains(source, alias <> ".") })
  case alias_still_used {
    True -> source
    False ->
      source
      |> string.split("\n")
      |> list.filter(fn(line) {
        !string.starts_with(string.trim(line), "import rally_runtime/effect")
      })
      |> string.join("\n")
  }
}

/// Extract (module_path, type_name) seeds from a client_context.gleam
/// source so the walker can discover ClientContext types with proper
/// field type resolution, instead of the old hardcoded-StringField path.
pub fn client_context_seeds(
  source: String,
  module_path: String,
) -> List(#(String, String)) {
  case glance.module(source) {
    Error(_) -> []
    Ok(ast) ->
      list.map(ast.custom_types, fn(def) {
        #(module_path, def.definition.name)
      })
  }
}

fn emit_rally_effect_shim() -> String {
  "// Generated by Rally — do not edit.
////
//// Client-side effect shim. Provides the same API as
//// rally_runtime/effect but backed by the client transport.

import lustre/effect.{type Effect}
import generated/transport

pub fn rpc(msg: a, on_response on_response: fn(b) -> msg) -> Effect(msg) {
  effect.from(fn(dispatch) {
    transport.send_rpc(msg, fn(response) {
      dispatch(on_response(response))
    })
  })
}

pub fn send_to_client_context(msg: a) -> Effect(b) {
  effect.from(fn(_dispatch) {
    transport.send_to_server(\"__ClientContext__\", msg)
    Nil
  })
}

pub fn navigate(path: String) -> Effect(a) {
  effect.from(fn(_dispatch) {
    do_navigate(path)
    Nil
  })
}

@external(javascript, \"./rally_effect_ffi.mjs\", \"navigate\")
fn do_navigate(_path: String) -> Nil {
  Nil
}

pub fn none() -> Effect(a) {
  effect.none()
}

pub fn from(f: fn(fn(a) -> Nil) -> Nil) -> Effect(a) {
  effect.from(f)
}

pub fn get_ws_session() -> String {
  \"\"
}

pub fn set_dark_mode(enabled: Bool) -> Effect(a) {
  effect.from(fn(_dispatch) {
    do_set_dark_mode(enabled)
    Nil
  })
}

@external(javascript, \"./rally_effect_ffi.mjs\", \"setDarkMode\")
fn do_set_dark_mode(_enabled: Bool) -> Nil {
  Nil
}

pub fn set_lang(lang: String) -> Effect(a) {
  effect.from(fn(_dispatch) {
    do_set_lang(lang)
    Nil
  })
}

@external(javascript, \"./rally_effect_ffi.mjs\", \"setLang\")
fn do_set_lang(_lang: String) -> Nil {
  Nil
}

@external(javascript, \"./rally_effect_ffi.mjs\", \"readDarkModeCookie\")
pub fn read_dark_mode() -> Bool {
  False
}

@external(javascript, \"./rally_effect_ffi.mjs\", \"readLangCookie\")
pub fn read_lang() -> String {
  \"\"
}
"
}

fn emit_rally_effect_ffi() -> String {
  "// Generated by Rally — do not edit.

export function navigate(path) {
  globalThis.history?.pushState(null, \"\", path);
  globalThis.dispatchEvent(new PopStateEvent(\"popstate\"));
}

export function setDarkMode(enabled) {
  document.documentElement.classList.toggle(\"dark\", enabled);
  document.cookie = \"__rally_dark_mode=\" + (enabled ? \"1\" : \"0\") + \";path=/;max-age=31536000;SameSite=Lax\";
}

export function setLang(lang) {
  document.cookie = \"__rally_lang=\" + lang + \";path=/;max-age=31536000;SameSite=Lax\";
}

export function readDarkModeCookie() {
  var c = document.cookie;
  if (c.includes('__rally_dark_mode=1')) return true;
  if (c.includes('__rally_dark_mode=0')) return false;
  return window.matchMedia('(prefers-color-scheme:dark)').matches;
}

export function readLangCookie() {
  var m = document.cookie.match(/(?:^|;)\\s*__rally_lang=([^;]+)/);
  if (m) return m[1];
  var lang = navigator.language || navigator.userLanguage || '';
  return lang ? lang.split('-')[0] : 'en';
}
"
}

fn to_pascal_case(name: String) -> String {
  name
  |> string.split("_")
  |> list.map(fn(word) {
    case string.pop_grapheme(word) {
      Ok(#(first, rest)) -> string.uppercase(first) <> rest
      Error(_) -> word
    }
  })
  |> string.join("")
}

// ---------- JS typed decoders (codec_ffi.mjs) ----------
// Ported from libero's codegen_decoders.gleam

pub fn emit_codec_ffi(discovered: List(DiscoveredType)) -> String {
  emit_codec_ffi_with_endpoints(discovered, [])
}

fn emit_codec_ffi_with_endpoints(
  discovered: List(DiscoveredType),
  endpoints: List(HandlerEndpoint),
) -> String {
  let stdlib_setters =
    "import { setResultCtors, setOptionCtors, setListCtors, "
    <> "setDictFromList } from \"./decoders_prelude.mjs\";"

  let imports =
    "import { decode_int, decode_float, decode_string, decode_bool, "
    <> "decode_bit_array, decode_nil, decode_list_of, decode_option_of, "
    <> "decode_result_of, decode_dict_of, decode_tuple_of, DecodeError } from \""
    <> "./decoders_prelude.mjs\";\n"
    <> "import { Ok, Error as ResultError, Empty, NonEmpty } from \""
    <> "../../gleam_stdlib/gleam.mjs\";\n"
    <> "import { Some, None } from \""
    <> "../../gleam_stdlib/gleam/option.mjs\";\n"
    <> "import { from_list as dictFromList } from \""
    <> "../../gleam_stdlib/gleam/dict.mjs\";\n"
    <> "import { registerTypedDecoder, registerFieldTypes } from \"./rpc_ffi.mjs\";\n"

  let ctor_setters =
    "setResultCtors(Ok, ResultError);\n"
    <> "setOptionCtors(Some, None);\n"
    <> "setListCtors(Empty, NonEmpty);\n"
    <> "setDictFromList(dictFromList);"

  let module_imports = emit_module_imports(discovered)
  let float_registrations = codegen_decoders.emit_float_type_registrations(discovered:, endpoints:)
  let type_decoders = codegen_decoders.emit_typed_decoders(discovered)

  "// Generated by Rally — do not edit.
//
// Typed decoders for ETF-serialized custom types.
// Each function converts raw ETF values (atoms as strings,
// tuples as arrays) into proper Gleam constructor instances.

" <> stdlib_setters <> "\n\n" <> imports <> "\n" <> module_imports <> "\n" <> ctor_setters <> "\n" <> float_registrations <> "\n" <> type_decoders <> "\n"
}

fn emit_module_imports(discovered: List(DiscoveredType)) -> String {
  let module_paths =
    list.fold(discovered, #([], set.new()), fn(acc, t) {
      let #(paths_acc, seen) = acc
      case set.contains(seen, t.module_path) {
        True -> acc
        False -> #(
          list.append(paths_acc, [t.module_path]),
          set.insert(seen, t.module_path),
        )
      }
    })
    |> fn(pair) { pair.0 }

  case module_paths {
    [] -> ""
    paths ->
      list.map(paths, fn(mp) {
        "import * as _m_"
        <> module_to_underscored(mp)
        <> " from \"../"
        <> mp
        <> ".mjs\";"
      })
      |> string.join("\n")
      |> fn(s) { s <> "\n" }
  }
}

// ---------- Mirrored types (types.gleam) ----------

fn emit_types_gleam(
  _contracts: List(#(ScannedRoute, PageContract)),
  endpoints: List(HandlerEndpoint),
) -> String {
  let resolve_alias = build_type_alias_resolver(endpoints)

  let client_msg_type = case endpoints {
    [] -> ""
    _ -> {
      let variants =
        list.map(endpoints, fn(e) {
          let variant_name = to_pascal_case("server_" <> e.fn_name)
          case e.params {
            [] -> "  " <> variant_name
            params -> {
              let fields =
                list.map(params, fn(p) {
                  p.0
                  <> ": "
                  <> field_type.to_gleam_source_with_alias(p.1, resolve_alias)
                })
              "  " <> variant_name <> "(" <> string.join(fields, ", ") <> ")"
            }
          }
        })
      "\npub type ClientMsg {\n" <> string.join(variants, "\n") <> "\n}\n"
    }
  }

  let all_modules =
    endpoints
    |> list.flat_map(fn(e) {
      list.flat_map(e.params, fn(p) { collect_user_type_modules(p.1) })
    })
    |> list.unique

  let type_imports =
    all_modules
    |> list.map(fn(mod) {
      let alias = resolve_alias(mod)
      case alias == field_type.last_segment(mod) {
        True -> "import " <> mod
        False -> "import " <> mod <> " as " <> alias
      }
    })
    |> string.join("\n")
    |> fn(s) {
      case s {
        "" -> ""
        _ -> s <> "\n"
      }
    }

  let option_import =
    codegen.import_if(
      endpoints:,
      predicate: codegen.is_option,
      import_line: "import gleam/option.{type Option}",
    )
  let dict_import =
    codegen.import_if(
      endpoints:,
      predicate: codegen.is_dict,
      import_line: "import gleam/dict.{type Dict}",
    )

  "// Generated by Rally — do not edit.
////
//// Mirrored page types for the client package.

" <> type_imports <> option_import <> dict_import <> client_msg_type <> "\n"
}

/// Build a resolver that uses the last segment when unique, or the full
/// underscored path when two modules share the same last segment.
fn build_type_alias_resolver(
  endpoints: List(HandlerEndpoint),
) -> fn(String) -> String {
  let all_modules =
    endpoints
    |> list.flat_map(fn(e) {
      list.flat_map(e.params, fn(p) { collect_user_type_modules(p.1) })
    })
    |> list.unique()
  let segment_counts =
    list.fold(all_modules, dict.new(), fn(acc, mod) {
      let seg = field_type.last_segment(mod)
      let count = case dict.get(acc, seg) {
        Ok(n) -> n + 1
        Error(Nil) -> 1
      }
      dict.insert(acc, seg, count)
    })
  fn(module_path: String) -> String {
    let seg = field_type.last_segment(module_path)
    case dict.get(segment_counts, seg) {
      Ok(n) if n > 1 -> string.replace(module_path, "/", "_")
      _ -> seg
    }
  }
}

fn collect_user_type_modules(ft: FieldType) -> List(String) {
  case ft {
    UserType(module_path:, ..) -> [module_path]
    field_type.ListOf(inner) -> collect_user_type_modules(inner)
    field_type.OptionOf(inner) -> collect_user_type_modules(inner)
    field_type.ResultOf(ok, err) ->
      list.append(collect_user_type_modules(ok), collect_user_type_modules(err))
    field_type.DictOf(k, v) ->
      list.append(collect_user_type_modules(k), collect_user_type_modules(v))
    field_type.TupleOf(elems) -> list.flat_map(elems, collect_user_type_modules)
    _ -> []
  }
}

// ---------- Typed codec wrappers (codec.gleam) ----------

fn emit_codec_gleam() -> String {
  "// Generated by Rally — do not edit.
////
//// Typed ETF encode/decode utilities.

import gleam/bit_array
import generated/transport

pub fn decode_flags(flags: String) -> Result(a, String) {
  case flags {
    \"\" -> Error(\"No flags present\")
    _ ->
      case bit_array.base64_decode(flags) {
        Ok(bits) ->
          case transport.decode_safe_raw(bits) {
            Ok(value) -> Ok(value)
            Error(err) -> Error(\"Failed to ETF-decode flags: \" <> err.message)
          }
        Error(_) -> Error(\"Failed to base64-decode flags\")
      }
  }
}
"
}

// ---------- Naming helpers ----------

fn module_to_underscored(module_path: String) -> String {
  string.replace(module_path, "/", "_")
}
