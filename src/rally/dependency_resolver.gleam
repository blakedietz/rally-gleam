import glance
import gleam/int
import gleam/list
import gleam/result
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
            Error(_) ->
              resolve_loop(
                frontier: rest,
                visited:,
                src_root:,
                client_root:,
                acc:,
              )
            Ok(content) -> {
              use Nil <- result.try(check_erlang_external(
                content,
                module_path,
                chain,
              ))
              let dest = client_root <> "/src/" <> module_path <> ".gleam"
              let file = client.GeneratedFile(dest, content)
              let ffi_files = collect_ffi_files(src_root, client_root, module_path)
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
          }
        }
      }
    }
  }
}

fn extract_imports(source: String) -> List(String) {
  case glance.module(source) {
    Error(_) -> []
    Ok(ast) ->
      list.map(ast.imports, fn(def) { def.definition.module })
  }
}

fn collect_ffi_files(
  src_root: String,
  client_root: String,
  module_path: String,
) -> List(client.GeneratedFile) {
  let ffi_path = src_root <> "/" <> module_path <> "_ffi.mjs"
  case simplifile.read(ffi_path) {
    Ok(content) -> {
      let dest = client_root <> "/src/" <> module_path <> "_ffi.mjs"
      [client.GeneratedFile(dest, content)]
    }
    Error(_) -> []
  }
}

fn should_skip(module_path: String) -> Bool {
  string.starts_with(module_path, "generated/")
  || module_path == "server_context"
}

fn check_erlang_external(
  content: String,
  module_path: String,
  chain: List(String),
) -> Result(Nil, String) {
  case string.contains(content, "@external(erlang,") {
    False -> Ok(Nil)
    True -> {
      let line = find_line_number(content, "@external(erlang,")
      let chain_str =
        string.join(
          list.map(list.append(chain, [module_path]), fn(c) { c <> ".gleam" }),
          " -> ",
        )
      Error(
        module_path
        <> ".gleam (line "
        <> int.to_string(line)
        <> ") contains @external(erlang, ...) which can't compile for JavaScript.\n\n"
        <> "  Import chain: "
        <> chain_str
        <> "\n\n"
        <> "  Server-only code belongs in page modules as server_* functions (which rally\n"
        <> "  strips from the client), or in separate modules that client code doesn't import.",
      )
    }
  }
}

fn find_line_number(content: String, needle: String) -> Int {
  content
  |> string.split("\n")
  |> do_find_line(needle, 1)
}

fn do_find_line(lines: List(String), needle: String, n: Int) -> Int {
  case lines {
    [] -> n
    [line, ..rest] ->
      case string.contains(line, needle) {
        True -> n
        False -> do_find_line(rest, needle, n + 1)
      }
  }
}
