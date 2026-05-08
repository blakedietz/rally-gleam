import gleam/list
import gleam/string
import gleeunit/should
import rally/dependency_resolver
import simplifile

fn make_temp_dir(name: String) -> String {
  let path = "/tmp/rally_test_depres_" <> name
  let _ = simplifile.delete(file_or_dir_at: path)
  let assert Ok(Nil) = simplifile.create_directory_all(path)
  path
}

fn write_file(path: String, content: String) -> Nil {
  let dir = case path |> string.split("/") |> list.reverse {
    [_, ..rest] -> rest |> list.reverse |> string.join("/")
    [] -> "."
  }
  let assert Ok(Nil) = simplifile.create_directory_all(dir)
  let assert Ok(Nil) = simplifile.write(to: path, contents: content)
  Nil
}

// Test 1: seed imports a local module, that module is returned
pub fn single_local_import_test() {
  let dir = make_temp_dir("single")
  let src = dir <> "/src"
  write_file(src <> "/foo.gleam", "pub fn hello() { \"hi\" }\n")
  let seed_source = "import foo\npub fn init() { foo.hello() }\n"
  let assert Ok(files) =
    dependency_resolver.resolve(
      seed_sources: [#("pages/home_", seed_source)],
      src_root: src,
      client_root: dir <> "/client",
    )
  list.length(files) |> should.equal(1)
  let assert Ok(file) = list.first(files)
  file.path |> should.equal(dir <> "/client/src/foo.gleam")
  file.content |> string.contains("pub fn hello()") |> should.be_true()
}

// Test 2: transitive chain
pub fn transitive_chain_test() {
  let dir = make_temp_dir("transitive")
  let src = dir <> "/src"
  write_file(
    src <> "/foo.gleam",
    "import bar\npub fn hello() { bar.world() }\n",
  )
  write_file(src <> "/bar.gleam", "pub fn world() { \"world\" }\n")
  let seed = "import foo\npub fn init() { foo.hello() }\n"
  let assert Ok(files) =
    dependency_resolver.resolve(
      seed_sources: [#("pages/home_", seed)],
      src_root: src,
      client_root: dir <> "/client",
    )
  let paths = list.map(files, fn(f) { f.path })
  list.length(paths) |> should.equal(2)
  paths |> list.contains(dir <> "/client/src/foo.gleam") |> should.be_true()
  paths |> list.contains(dir <> "/client/src/bar.gleam") |> should.be_true()
}

// Test 3: external dep skipped
pub fn external_dep_skipped_test() {
  let dir = make_temp_dir("external")
  let src = dir <> "/src"
  let assert Ok(Nil) = simplifile.create_directory_all(src)
  let seed = "import gleam/list\npub fn init() { list.map([], fn(x) { x }) }\n"
  let assert Ok(files) =
    dependency_resolver.resolve(
      seed_sources: [#("pages/home_", seed)],
      src_root: src,
      client_root: dir <> "/client",
    )
  list.length(files) |> should.equal(0)
}

// Test 4: generated modules skipped
pub fn generated_modules_skipped_test() {
  let dir = make_temp_dir("generated")
  let src = dir <> "/src"
  write_file(src <> "/generated/router.gleam", "pub fn route() { \"/\" }\n")
  let seed = "import generated/router\npub fn init() { router.route() }\n"
  let assert Ok(files) =
    dependency_resolver.resolve(
      seed_sources: [#("pages/home_", seed)],
      src_root: src,
      client_root: dir <> "/client",
    )
  list.length(files) |> should.equal(0)
}

// Test 5: server_context skipped
pub fn server_context_skipped_test() {
  let dir = make_temp_dir("server_ctx")
  let src = dir <> "/src"
  write_file(
    src <> "/server_context.gleam",
    "pub type ServerContext { ServerContext }\n",
  )
  let seed = "import server_context\npub fn init() { Nil }\n"
  let assert Ok(files) =
    dependency_resolver.resolve(
      seed_sources: [#("pages/home_", seed)],
      src_root: src,
      client_root: dir <> "/client",
    )
  list.length(files) |> should.equal(0)
}

// Test 6: deduplication
pub fn deduplication_test() {
  let dir = make_temp_dir("dedup")
  let src = dir <> "/src"
  write_file(src <> "/i18n.gleam", "pub fn pick() { \"en\" }\n")
  let seed1 = "import i18n\npub fn init() { i18n.pick() }\n"
  let seed2 = "import i18n\npub fn view() { i18n.pick() }\n"
  let assert Ok(files) =
    dependency_resolver.resolve(
      seed_sources: [#("pages/home_", seed1), #("pages/about", seed2)],
      src_root: src,
      client_root: dir <> "/client",
    )
  list.length(files) |> should.equal(1)
}

// Test 7: diamond dependency
pub fn diamond_dependency_test() {
  let dir = make_temp_dir("diamond")
  let src = dir <> "/src"
  write_file(src <> "/a.gleam", "import c\npub fn fa() { c.fc() }\n")
  write_file(src <> "/b.gleam", "import c\npub fn fb() { c.fc() }\n")
  write_file(src <> "/c.gleam", "pub fn fc() { \"c\" }\n")
  let seed = "import a\nimport b\npub fn init() { a.fa() }\n"
  let assert Ok(files) =
    dependency_resolver.resolve(
      seed_sources: [#("pages/home_", seed)],
      src_root: src,
      client_root: dir <> "/client",
    )
  let paths = list.map(files, fn(f) { f.path })
  list.length(paths) |> should.equal(3)
  paths |> list.contains(dir <> "/client/src/c.gleam") |> should.be_true()
}

// Test 8: deep chain
pub fn deep_chain_test() {
  let dir = make_temp_dir("deep")
  let src = dir <> "/src"
  write_file(src <> "/a.gleam", "import b\npub fn fa() { b.fb() }\n")
  write_file(src <> "/b.gleam", "import c\npub fn fb() { c.fc() }\n")
  write_file(src <> "/c.gleam", "import d\npub fn fc() { d.fd() }\n")
  write_file(src <> "/d.gleam", "pub fn fd() { \"d\" }\n")
  let seed = "import a\npub fn init() { a.fa() }\n"
  let assert Ok(files) =
    dependency_resolver.resolve(
      seed_sources: [#("pages/home_", seed)],
      src_root: src,
      client_root: dir <> "/client",
    )
  list.length(files) |> should.equal(4)
}

// Test 9: mixed local and external
pub fn mixed_local_and_external_test() {
  let dir = make_temp_dir("mixed")
  let src = dir <> "/src"
  write_file(src <> "/i18n.gleam", "pub fn pick() { \"en\" }\n")
  let seed =
    "import i18n\nimport gleam/option\nimport glaze/basecoat/table\npub fn init() { i18n.pick() }\n"
  let assert Ok(files) =
    dependency_resolver.resolve(
      seed_sources: [#("pages/home_", seed)],
      src_root: src,
      client_root: dir <> "/client",
    )
  list.length(files) |> should.equal(1)
  let assert Ok(file) = list.first(files)
  file.path |> should.equal(dir <> "/client/src/i18n.gleam")
}

// Test 10: subdirectory modules
pub fn subdirectory_module_test() {
  let dir = make_temp_dir("subdir")
  let src = dir <> "/src"
  write_file(src <> "/translations/keys.gleam", "pub const name = \"name\"\n")
  let seed = "import translations/keys\npub fn init() { keys.name }\n"
  let assert Ok(files) =
    dependency_resolver.resolve(
      seed_sources: [#("pages/home_", seed)],
      src_root: src,
      client_root: dir <> "/client",
    )
  list.length(files) |> should.equal(1)
  let assert Ok(file) = list.first(files)
  file.path |> should.equal(dir <> "/client/src/translations/keys.gleam")
}

// Test 11: erlang external produces error
pub fn erlang_external_detection_test() {
  let dir = make_temp_dir("erlang_ext")
  let src = dir <> "/src"
  write_file(
    src <> "/db_helper.gleam",
    "import gleam/list\n\npub fn query() { \"ok\" }\n\n@external(erlang, \"sqlight_ffi\", \"open\")\npub fn open(path: String) -> Nil\n",
  )
  let seed = "import db_helper\npub fn init() { db_helper.query() }\n"
  let result =
    dependency_resolver.resolve(
      seed_sources: [#("pages/home_", seed)],
      src_root: src,
      client_root: dir <> "/client",
    )
  case result {
    Error(msg) -> {
      msg |> string.contains("db_helper.gleam") |> should.be_true()
      msg |> string.contains("line 5") |> should.be_true()
      msg |> string.contains("@external(erlang,") |> should.be_true()
    }
    Ok(_) -> should.fail()
  }
}

// Test 12: error includes import chain
pub fn erlang_external_chain_test() {
  let dir = make_temp_dir("erlang_chain")
  let src = dir <> "/src"
  write_file(src <> "/helper.gleam", "import db\npub fn go() { db.run() }\n")
  write_file(
    src <> "/db.gleam",
    "@external(erlang, \"db_ffi\", \"run\")\npub fn run() -> Nil\n",
  )
  let seed = "import helper\npub fn init() { helper.go() }\n"
  let result =
    dependency_resolver.resolve(
      seed_sources: [#("pages/home_", seed)],
      src_root: src,
      client_root: dir <> "/client",
    )
  case result {
    Error(msg) -> {
      msg |> string.contains("pages/home_.gleam") |> should.be_true()
      msg |> string.contains("helper.gleam") |> should.be_true()
      msg |> string.contains("db.gleam") |> should.be_true()
    }
    Ok(_) -> should.fail()
  }
}

// Test 13: javascript external passes
pub fn javascript_external_passes_test() {
  let dir = make_temp_dir("js_ext")
  let src = dir <> "/src"
  write_file(
    src <> "/ffi_helper.gleam",
    "@external(javascript, \"./ffi.mjs\", \"doThing\")\npub fn do_thing() -> Nil\n",
  )
  let seed = "import ffi_helper\npub fn init() { ffi_helper.do_thing() }\n"
  let assert Ok(files) =
    dependency_resolver.resolve(
      seed_sources: [#("pages/home_", seed)],
      src_root: src,
      client_root: dir <> "/client",
    )
  list.length(files) |> should.equal(1)
}

// Test 14: ffi files copied alongside local modules
pub fn ffi_file_copied_test() {
  let dir = make_temp_dir("ffi_copy")
  let src = dir <> "/src"
  write_file(src <> "/widget.gleam", "pub fn render() { Nil }\n")
  write_file(src <> "/widget_ffi.mjs", "export function doThing() {}")
  let seed = "import widget\npub fn init() { widget.render() }\n"
  let assert Ok(files) =
    dependency_resolver.resolve(
      seed_sources: [#("pages/home_", seed)],
      src_root: src,
      client_root: dir <> "/client",
    )
  list.length(files) |> should.equal(2)
  let paths = list.map(files, fn(f) { f.path })
  paths
  |> list.contains(dir <> "/client/src/widget.gleam")
  |> should.be_true()
  paths
  |> list.contains(dir <> "/client/src/widget_ffi.mjs")
  |> should.be_true()
}

// Test 15: no ffi file when sibling doesn't exist
pub fn no_ffi_file_when_missing_test() {
  let dir = make_temp_dir("no_ffi")
  let src = dir <> "/src"
  write_file(src <> "/plain.gleam", "pub fn go() { Nil }\n")
  let seed = "import plain\npub fn init() { plain.go() }\n"
  let assert Ok(files) =
    dependency_resolver.resolve(
      seed_sources: [#("pages/home_", seed)],
      src_root: src,
      client_root: dir <> "/client",
    )
  list.length(files) |> should.equal(1)
  let assert Ok(file) = list.first(files)
  file.path |> should.equal(dir <> "/client/src/plain.gleam")
}
