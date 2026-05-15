import gleam/dict
import gleeunit/should
import rally
import tom

pub fn hex_dependency_uses_gleam_package_cache_test() {
  let deps =
    dict.from_list([
      #("rally", tom.String(">= 1.0.0 and < 2.0.0")),
    ])

  rally.resolve_rally_package_path(deps)
  |> should.equal("build/packages/rally")
}

pub fn path_dependency_uses_configured_path_test() {
  let deps =
    dict.from_list([
      #(
        "rally",
        tom.InlineTable(dict.from_list([#("path", tom.String("../rally"))])),
      ),
    ])

  rally.resolve_rally_package_path(deps)
  |> should.equal("../rally")
}

pub fn current_package_uses_current_directory_test() {
  rally.resolve_rally_package_path(dict.new())
  |> should.equal(".")
}
