import gleam/dict.{type Dict}
import gleam/option.{type Option}
import libero/field_type.{type FieldType}
import tom

pub type ParamType {
  IntParam
  StringParam
}

pub type UrlSegment {
  StaticSegment(name: String)
  DynamicSegment(param_name: String, param_type: ParamType)
}

pub type ScannedRoute {
  ScannedRoute(
    segments: List(UrlSegment),
    variant_name: String,
    params: List(#(String, ParamType)),
    module_path: String,
    layout_module: Option(String),
  )
}

pub type ScanConfig {
  ScanConfig(
    pages_root: String,
    output_route: String,
    output_dispatch: String,
    output_server_dispatch: String,
    output_server_atoms: String,
    atoms_module: String,
    output_ssr: String,
    output_ws: String,
    output_http: String,
    client_root: String,
    route_root: String,
    rally_package_path: String,
    shell_file: String,
    server_deps: Dict(String, tom.Toml),
  )
}

/// A single field in a variant constructor.
pub type VariantField {
  VariantField(label: String, type_: FieldType)
}

/// A single variant in a custom type, with its fields.
pub type VariantInfo {
  VariantInfo(name: String, fields: List(VariantField))
}

pub type ClientContextContract {
  ClientContextContract(
    context_variants: List(VariantInfo),
    msg_variants: List(VariantInfo),
    has_init: Bool,
    has_update: Bool,
  )
}

pub type PageContract {
  PageContract(
    model_variants: List(VariantInfo),
    msg_variants: List(VariantInfo),
    has_load: Bool,
    has_init: Bool,
    has_init_loaded: Bool,
    has_model: Bool,
    updates_client_context: Bool,
    param_names: List(String),
    source: String,
    view_source: String,
    init_source: String,
    update_source: String,
  )
}
