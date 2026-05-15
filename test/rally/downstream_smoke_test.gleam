import gleam/option.{type Option, Some}
import gleam/string
import rally/internal/init
import simplifile

@external(erlang, "rally_cli_ffi", "find_executable")
fn find_executable(name: String) -> Option(String)

@external(erlang, "rally_cli_ffi", "run_in_dir")
fn run_in_dir(
  program: String,
  args: List(String),
  dir: String,
) -> #(Int, String)

fn rally_root() -> String {
  let assert Ok(cwd) = simplifile.current_directory()
  cwd
}

fn make_temp_dir() -> String {
  let path = "/tmp/rally_downstream_smoke"
  let _ = simplifile.delete(file_or_dir_at: path)
  let assert Ok(Nil) = simplifile.create_directory_all(path)
  path
}

fn cleanup(path: String) -> Nil {
  let _ = simplifile.delete(file_or_dir_at: path)
  Nil
}

fn assert_no_warning(output: String, phase: String, dir: String) -> Nil {
  case string.contains(output, "warning:") {
    False -> Nil
    True -> {
      cleanup(dir)
      panic as { phase <> " emitted warnings: " <> output }
    }
  }
}

pub fn scaffold_builds_without_warnings_test() {
  let root = rally_root()
  let dir = make_temp_dir()
  let assert Some(gleam) = find_executable("gleam")
  let assert Ok(Nil) = init.init_project(dir)

  let assert Ok(toml) = simplifile.read(dir <> "/gleam.toml")
  let patched =
    toml
    |> string.replace(
      "rally = \">= 1.0.0 and < 2.0.0\"",
      "rally = { path = \"" <> root <> "\" }",
    )
  let assert Ok(Nil) = simplifile.write(dir <> "/gleam.toml", patched)

  let #(migrate_exit, migrate_out) =
    run_in_dir(gleam, ["run", "-m", "rally", "migrate"], dir)
  case migrate_exit {
    0 -> Nil
    _ -> {
      cleanup(dir)
      panic as { "rally migrate failed: " <> migrate_out }
    }
  }

  let #(rally_build_exit, rally_build_out) =
    run_in_dir(gleam, ["run", "-m", "rally", "build"], dir)
  case rally_build_exit {
    0 -> Nil
    _ -> {
      cleanup(dir)
      panic as { "rally build failed: " <> rally_build_out }
    }
  }

  let #(build_exit, build_out) = run_in_dir(gleam, ["build"], dir)
  case build_exit {
    0 -> Nil
    _ -> {
      cleanup(dir)
      panic as { "build failed: " <> build_out }
    }
  }
  assert_no_warning(build_out, "build", dir)

  cleanup(dir)
}
