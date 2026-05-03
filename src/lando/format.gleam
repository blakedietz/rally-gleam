//// Run `gleam format` on generated Gleam code.
//// Writes code to a temp file, runs the formatter, reads back the result.
//// Falls back to the original string if formatting fails.

import gleam/int
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/result
import simplifile

/// Format a string of Gleam code using `gleam format`.
/// Returns the formatted code, or the original if formatting fails.
pub fn format_gleam(code: String) -> String {
  let suffix = format_unique_id()
  let tmp_dir = get_tmp_dir()
  let tmp = tmp_dir <> "/lando_fmt_" <> suffix <> ".gleam"
  case simplifile.write(tmp, code) {
    Error(_) -> {
      io.println_error(
        "warning: could not write temp file for formatting, skipping gleam format",
      )
      code
    }
    Ok(_) -> {
      let formatted = run_format(tmp, code)
      let _ = simplifile.delete(tmp)
      formatted
    }
  }
}

fn run_format(tmp: String, fallback: String) -> String {
  case find_executable("gleam") {
    None -> {
      io.println_error(
        "warning: gleam not found on PATH, skipping format",
      )
      fallback
    }
    Some(_path) -> {
      let exit_code = run_executable("gleam", ["format", tmp])
      case exit_code {
        0 ->
          simplifile.read(tmp)
          |> result.unwrap(fallback)
        _ -> {
          io.println_error(
            "warning: gleam format failed (exit code "
            <> int.to_string(exit_code)
            <> "), using unformatted output",
          )
          fallback
        }
      }
    }
  }
}

@external(erlang, "lando_cli_ffi", "find_executable")
fn find_executable(name: String) -> Option(String)

@external(erlang, "lando_cli_ffi", "run_executable")
fn run_executable(program: String, args: List(String)) -> Int

fn get_tmp_dir() -> String {
  get_env("TMPDIR")
  |> option.lazy_or(fn() { get_env("TMP") })
  |> option.lazy_or(fn() { get_env("TEMP") })
  |> option.unwrap("/tmp")
}

@external(erlang, "lando_cli_ffi", "get_env")
fn get_env(name: String) -> Option(String)

@external(erlang, "lando_cli_ffi", "unique_id")
fn format_unique_id() -> String
