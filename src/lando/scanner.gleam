import gleam/list
import gleam/result
import gleam/string
import simplifile
import lando/types.{
  type ParamType, type ScannedRoute, type UrlSegment, DynamicSegment, IntParam,
  ScannedRoute, StaticSegment, StringParam, type ScanConfig,
}

/// Convert a snake_case name to PascalCase.
/// "custom_questions" -> "CustomQuestions"
pub fn to_pascal_case(name: String) -> String {
  name
  |> string.split("_")
  |> list.map(string.capitalise)
  |> string.join("")
}

/// Determine param type: "id" or anything ending in "_id" -> IntParam, else StringParam.
fn param_type_for(name: String) -> ParamType {
  case name == "id" || string.ends_with(name, "_id") {
    True -> IntParam
    False -> StringParam
  }
}

/// Parse a filename stem (without .gleam extension) into a UrlSegment.
/// Trailing underscore means dynamic; otherwise static.
pub fn parse_segment(stem: String) -> UrlSegment {
  case string.ends_with(stem, "_") {
    True -> {
      let param_name = string.drop_end(stem, 1)
      DynamicSegment(param_name, param_type_for(param_name))
    }
    False -> StaticSegment(stem)
  }
}

/// Build a ScannedRoute from a list of UrlSegments and a module path.
fn build_route(
  segments: List(UrlSegment),
  module_path: String,
) -> ScannedRoute {
  let variant_name =
    segments
    |> list.map(fn(seg) {
      case seg {
        StaticSegment(name) -> to_pascal_case(name)
        DynamicSegment(param_name, _) -> to_pascal_case(param_name)
      }
    })
    |> string.join("")

  let params =
    segments
    |> list.filter_map(fn(seg) {
      case seg {
        DynamicSegment(param_name, param_type) -> Ok(#(param_name, param_type))
        StaticSegment(_) -> Error(Nil)
      }
    })

  ScannedRoute(
    segments: segments,
    variant_name: variant_name,
    params: params,
    module_path: module_path,
  )
}

/// Recursively scan a directory, accumulating routes.
/// prefix_segments carries the UrlSegments for directories above the current level.
/// path_parts carries the raw directory names for computing module paths.
/// pages_root is the base directory for deriving module paths.
fn scan_dir(
  path: String,
  prefix_segments: List(UrlSegment),
  path_parts: List(String),
  pages_root: String,
) -> Result(List(ScannedRoute), String) {
  use entries <- result.try(
    simplifile.read_directory(at: path)
    |> result.map_error(fn(e) {
      "Failed to read directory "
      <> path
      <> ": "
      <> simplifile.describe_error(e)
    }),
  )

  let sorted_entries = list.sort(entries, string.compare)

  use acc, entry <- list.try_fold(over: sorted_entries, from: [])
  let entry_path = path <> "/" <> entry

  use is_dir <- result.try(
    simplifile.is_directory(entry_path)
    |> result.map_error(fn(e) {
      "Failed to stat " <> entry_path <> ": " <> simplifile.describe_error(e)
    }),
  )

  case is_dir {
    True -> {
      // Directory: derive a segment from the directory name and recurse.
      let seg = parse_segment(entry)
      use nested <- result.try(scan_dir(
        entry_path,
        list.append(prefix_segments, [seg]),
        list.append(path_parts, [entry]),
        pages_root,
      ))
      Ok(list.append(acc, nested))
    }
    False -> {
      // File: only process .gleam files.
      case string.ends_with(entry, ".gleam") {
        False -> Ok(acc)
        True -> {
          let stem = string.drop_end(entry, string.length(".gleam"))
          let module_path = derive_module_path(
            pages_root,
            string.join(list.append(path_parts, [stem]), "/"),
          )
          // Special case: home_.gleam at scanner root (no prefix) -> Home route
          let route = case stem == "home_" && list.is_empty(prefix_segments) {
            True ->
              ScannedRoute(
                segments: [],
                variant_name: "Home",
                params: [],
                module_path:,
              )
            False -> {
              let segments = list.append(prefix_segments, [parse_segment(stem)])
              build_route(segments, module_path)
            }
          }
          Ok(list.append(acc, [route]))
        }
      }
    }
  }
}

/// Scan a root directory and return all routes found.
pub fn scan(config: ScanConfig) -> Result(List(ScannedRoute), String) {
  scan_dir(config.pages_root, [], [], config.pages_root)
}

/// Derive a Gleam module path from a filesystem path under pages_root.
/// Uses "pages/" as the fixed module prefix, appending the relative path
/// within pages_root.
/// E.g. "home_" -> "pages/home_"
fn derive_module_path(_pages_root: String, relative_path: String) -> String {
  "pages/" <> relative_path
}
