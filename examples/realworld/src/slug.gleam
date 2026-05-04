import gleam/regex
import gleam/string

pub fn from_title(title: String) -> String {
  let assert Ok(re) = regex.from_string("[^a-z0-9]+")
  title
  |> string.lowercase
  |> regex.replace(re, _, "-")
  |> strip_char("-")
}

fn strip_char(s: String, char: String) -> String {
  s
  |> strip_leading(char)
  |> strip_trailing(char)
}

fn strip_leading(s: String, prefix: String) -> String {
  case string.starts_with(s, prefix) {
    True -> strip_leading(string.drop_start(s, string.length(prefix)), prefix)
    False -> s
  }
}

fn strip_trailing(s: String, suffix: String) -> String {
  case string.ends_with(s, suffix) {
    True -> strip_trailing(string.drop_end(s, string.length(suffix)), suffix)
    False -> s
  }
}
