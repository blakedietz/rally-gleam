import gleam/list
import gleam/string
import lando/types.{type PageContract, PageContract}

/// Parse a page module source to extract the contract.
/// Uses structural string matching — detects type definitions
/// and function signatures by pattern.
pub fn parse_page(source: String) -> Result(PageContract, String) {
  let to_backend = extract_variants(source, "pub type ToBackend")
  let to_frontend = extract_variants(source, "pub type ToFrontend")
  let has_server_update = string.contains(source, "pub fn server_update")
  let has_load = string.contains(source, "pub fn load")
  let has_init = string.contains(source, "pub fn init")
  let has_model = string.contains(source, "pub type Model")
  let param_names = extract_init_params(source)

  Ok(PageContract(
    to_backend_variants: to_backend,
    to_frontend_variants: to_frontend,
    has_server_update:,
    has_load:,
    has_init:,
    has_model:,
    param_names:,
  ))
}

fn extract_variants(source: String, type_decl: String) -> List(String) {
  case string.split_once(source, type_decl) {
    Error(_) -> []
    Ok(#(_, rest)) -> {
      case string.split_once(rest, "{") {
        Error(_) -> []
        Ok(#(_, after_brace)) -> {
          case string.split_once(after_brace, "}") {
            Error(_) -> []
            Ok(#(body, _)) ->
              body
              |> string.split(";")
              |> list.filter_map(fn(variant) {
                let trimmed = string.trim(variant)
                case trimmed {
                  "" -> Error(Nil)
                  _ -> {
                    // Split on "(" first — gives us the name before any params
                    let name = case string.split_once(trimmed, "(") {
                      Ok(#(name, _)) -> string.trim(name)
                      Error(_) ->
                        case string.split_once(trimmed, " ") {
                          Ok(#(name, _)) -> string.trim(name)
                          Error(_) -> trimmed
                        }
                    }
                    case name {
                      "" -> Error(Nil)
                      _ -> Ok(name)
                    }
                  }
                }
              })
          }
        }
      }
    }
  }
}

fn extract_init_params(source: String) -> List(String) {
  case string.split_once(source, "pub fn init(") {
    Error(_) -> []
    Ok(#(_, rest)) -> {
      case string.split_once(rest, ")") {
        Error(_) -> []
        Ok(#(params, _)) -> {
          params
          |> string.split(",")
          |> list.filter_map(fn(param) {
            let trimmed = string.trim(param)
            case trimmed {
              "" -> Error(Nil)
              p -> {
                case string.split_once(p, ":") {
                  Ok(#(name, _)) -> Ok(string.trim(name))
                  Error(_) -> Ok(string.trim(p))
                }
              }
            }
          })
        }
      }
    }
  }
}
