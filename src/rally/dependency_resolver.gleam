//// Client dependency resolver.
////
//// Starting from the tree-shaken page modules and layout files, follows
//// their import chains through the server's src/ tree and copies any
//// shared modules the client package needs. Catches @external(erlang)
//// imports that would fail to compile for JavaScript and reports the
//// import chain so the developer can find the problem.

import glance
import gleam/bool
import gleam/int
import gleam/list
import gleam/set.{type Set}
import gleam/string
import rally/generator/client
import simplifile

pub fn resolve(
  seed_sources seed_sources: List(#(String, String)),
  src_root src_root: String,
  client_root client_root: String,
) -> Result(List(client.GeneratedFile), String) {
  let seed_modules =
    list.map(seed_sources, fn(pair) { pair.0 })
    |> set.from_list

  let seed_imports =
    list.flat_map(seed_sources, fn(pair) {
      list.map(extract_imports(pair.1), fn(imp) { #(imp, [pair.0]) })
    })

  resolve_loop(
    frontier: seed_imports,
    visited: seed_modules,
    src_root:,
    client_root:,
    acc: [],
  )
}

fn resolve_loop(
  frontier frontier: List(#(String, List(String))),
  visited visited: Set(String),
  src_root src_root: String,
  client_root client_root: String,
  acc acc: List(client.GeneratedFile),
) -> Result(List(client.GeneratedFile), String) {
  case frontier {
    [] -> Ok(acc)
    [#(module_path, chain), ..rest] -> {
      case set.contains(visited, module_path) || should_skip(module_path) {
        True ->
          resolve_loop(frontier: rest, visited:, src_root:, client_root:, acc:)
        False -> {
          let file_path = src_root <> "/" <> module_path <> ".gleam"
          let visited = set.insert(visited, module_path)
          case simplifile.read(file_path) {
            Ok(content) -> {
              case
                check_erlang_external(
                  content: content,
                  module_path: module_path,
                  chain: chain,
                )
              {
                Ok(_) -> {
                  let dest = client_root <> "/src/" <> module_path <> ".gleam"
                  let file = client.GeneratedFile(dest, content)
                  let ffi_files =
                    collect_ffi_files(
                      src_root: src_root,
                      client_root: client_root,
                      module_path: module_path,
                    )
                  let new_chain = list.append(chain, [module_path])
                  let new_imports =
                    list.map(extract_imports(content), fn(imp) {
                      #(imp, new_chain)
                    })
                  resolve_loop(
                    frontier: list.append(rest, new_imports),
                    visited:,
                    src_root:,
                    client_root:,
                    acc: list.append([file, ..ffi_files], acc),
                  )
                }
                Error(msg) -> Error(msg)
              }
            }
            _ ->
              resolve_loop(
                frontier: rest,
                visited:,
                src_root:,
                client_root:,
                acc:,
              )
          }
        }
      }
    }
  }
}

fn extract_imports(source: String) -> List(String) {
  case glance.module(source) {
    Ok(ast) -> list.map(ast.imports, fn(def) { def.definition.module })
    _ -> []
  }
}

fn collect_ffi_files(
  src_root src_root: String,
  client_root client_root: String,
  module_path module_path: String,
) -> List(client.GeneratedFile) {
  let ffi_path = src_root <> "/" <> module_path <> "_ffi.mjs"
  case simplifile.read(ffi_path) {
    Ok(content) -> {
      let dest = client_root <> "/src/" <> module_path <> "_ffi.mjs"
      [client.GeneratedFile(dest, content)]
    }
    _ -> []
  }
}

fn should_skip(module_path: String) -> Bool {
  string.starts_with(module_path, "generated/")
  || module_path == "server_context"
}

fn check_erlang_external(
  content content: String,
  module_path module_path: String,
  chain chain: List(String),
) -> Result(Nil, String) {
  let has_erlang = string.contains(content, "@external(erlang,")
  let has_javascript = string.contains(content, "@external(javascript,")
  let error_msg = {
    let line = find_line_number(content, "@external(erlang,")
    let chain_str =
      string.join(
        list.map(list.append(chain, [module_path]), fn(c) { c <> ".gleam" }),
        " -> ",
      )
    module_path
    <> ".gleam (line "
    <> int.to_string(line)
    <> ") contains @external(erlang, ...) which can't compile for JavaScript.\n\n"
    <> "  Import chain: "
    <> chain_str
    <> "\n\n"
    <> "  Server-only code belongs in page modules as server_* functions (which rally\n"
    <> "  strips from the client), or in separate modules that client code doesn't import."
  }
  use <- bool.guard(
    when: has_erlang && !has_javascript,
    return: Error(error_msg),
  )
  Ok(Nil)
}

fn find_line_number(content: String, needle: String) -> Int {
  content
  |> string.split("\n")
  |> do_find_line(needle: needle, n: 1)
}

fn do_find_line(
  lines lines: List(String),
  needle needle: String,
  n n: Int,
) -> Int {
  case lines {
    [] -> n
    [line, ..rest] ->
      case string.contains(line, needle) {
        True -> n
        _ -> do_find_line(lines: rest, needle: needle, n: n + 1)
      }
  }
}
