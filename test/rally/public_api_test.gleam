import gleam/string
import gleeunit/should
import simplifile

pub fn codegen_modules_live_under_internal_test() {
  simplifile.is_file("src/rally/generator/json_rpc_dispatch.gleam")
  |> should.equal(Ok(False))

  simplifile.is_file("src/rally/internal/generator/json_rpc_dispatch.gleam")
  |> should.equal(Ok(True))
}

pub fn cli_imports_internal_codegen_modules_test() {
  let assert Ok(source) = simplifile.read("src/rally.gleam")

  source
  |> string.contains("import rally/generator")
  |> should.be_false()

  source
  |> string.contains("import rally/internal/generator")
  |> should.be_true()
}

pub fn scanner_uses_justin_for_pascal_case_test() {
  let assert Ok(source) = simplifile.read("src/rally/internal/scanner.gleam")

  source
  |> string.contains("import justin")
  |> should.be_true()

  source
  |> string.contains("fn to_pascal_case")
  |> should.be_false()
}
