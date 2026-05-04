import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import gleam/string
import simplifile
import lando/types.{
  type ParamType, type ScannedRoute, type UrlSegment, DynamicSegment, IntParam,
  ScannedRoute, StaticSegment, StringParam, type ScanConfig,
}

/// Convert a snake_case name to PascalCase.
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
    layout_module: None,
  )
}

/// Internal accumulator for the scan.
type ScanAcc {
  ScanAcc(
    routes: List(ScannedRoute),
    layout_modules: List(String),
  )
}

/// Recursively scan a directory, accumulating routes and layout modules.
fn scan_dir(
  path: String,
  prefix_segments: List(UrlSegment),
  path_parts: List(String),
  acc: ScanAcc,
) -> Result(ScanAcc, String) {
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

  use acc, entry <- list.try_fold(over: sorted_entries, from: acc)
  let entry_path = path <> "/" <> entry

  use is_dir <- result.try(
    simplifile.is_directory(entry_path)
    |> result.map_error(fn(e) {
      "Failed to stat " <> entry_path <> ": " <> simplifile.describe_error(e)
    }),
  )

  case is_dir {
    True -> {
      // Skip sql/ directories (used by marmot, not routes)
      case entry == "sql" {
        True -> Ok(acc)
        False -> {
          let seg = parse_segment(entry)
          scan_dir(
            entry_path,
            list.append(prefix_segments, [seg]),
            list.append(path_parts, [entry]),
            acc,
          )
        }
      }
    }
    False -> {
      case string.ends_with(entry, ".gleam") {
        False -> Ok(acc)
        True -> {
          let stem = string.drop_end(entry, string.length(".gleam"))
          let relative_path = string.join(list.append(path_parts, [stem]), "/")
          let module_path = derive_module_path(relative_path)

          // layout.gleam files are not routes — they provide page chrome.
          case stem {
            "layout" ->
              Ok(ScanAcc(..acc, layout_modules: [module_path, ..acc.layout_modules]))
            // index.gleam is the route for its parent directory.
            // Uses the parent's segments, not adding "index" as a segment.
            "index" -> {
              let route = case list.is_empty(prefix_segments) {
                True ->
                  ScannedRoute(
                    segments: [],
                    variant_name: "Home",
                    params: [],
                    module_path:,
                    layout_module: None,
                  )
                False -> build_route(prefix_segments, module_path)
              }
              Ok(ScanAcc(..acc, routes: [route, ..acc.routes]))
            }
            _ -> {
              let route = case stem == "home_" && list.is_empty(prefix_segments) {
                True ->
                  ScannedRoute(
                    segments: [],
                    variant_name: "Home",
                    params: [],
                    module_path:,
                    layout_module: None,
                  )
                False -> {
                  let segments = list.append(prefix_segments, [parse_segment(stem)])
                  build_route(segments, module_path)
                }
              }
              Ok(ScanAcc(..acc, routes: [route, ..acc.routes]))
            }
          }
        }
      }
    }
  }
}

/// Resolve the nearest layout module for a page route.
/// Walks up the module path, checking if <dir>/layout exists in the layout set.
fn resolve_layout(
  route: ScannedRoute,
  layout_set: set.Set(String),
) -> ScannedRoute {
  let parts = string.split(route.module_path, "/")
  // Drop the last segment (the page name), then walk up looking for a layout.
  let dirs = case list.length(parts) {
    1 -> []
    n -> list.take(parts, n - 1)
  }
  let layout = find_nearest_layout(dirs, [], layout_set)
  ScannedRoute(..route, layout_module: layout)
}

fn find_nearest_layout(
  remaining: List(String),
  _acc: List(String),
  layout_set: set.Set(String),
) -> Option(String) {
  case remaining {
    [] -> None
    _ -> {
      let candidate = string.join(remaining, "/") <> "/layout"
      case set.contains(layout_set, candidate) {
        True -> Some(candidate)
        False ->
          find_nearest_layout(
            list.take(remaining, list.length(remaining) - 1),
            [],
            layout_set,
          )
      }
    }
  }
}

/// Scan a root directory and return all routes found with layout assignments.
pub fn scan(config: ScanConfig) -> Result(List(ScannedRoute), String) {
  use acc <- result.try(scan_dir(
    config.pages_root, [], [], ScanAcc([], []),
  ))
  let layout_set = set.from_list(acc.layout_modules)
  let routes_with_layouts =
    list.map(acc.routes, fn(route) { resolve_layout(route, layout_set) })
  Ok(list.reverse(routes_with_layouts))
}

/// Derive a Gleam module path from a filesystem path under pages_root.
fn derive_module_path(relative_path: String) -> String {
  "pages/" <> relative_path
}
