import lando/field_type.{type FieldType}

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
  )
}

pub type ScanConfig {
  ScanConfig(
    pages_root: String,
    output_route: String,
    output_dispatch: String,
    output_server_dispatch: String,
    output_ssr: String,
    output_ws: String,
    client_root: String,
    lando_package_path: String,
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

pub type PageContract {
  PageContract(
    to_backend_variants: List(VariantInfo),
    to_frontend_variants: List(VariantInfo),
    has_server_update: Bool,
    has_server_init: Bool,
    has_load: Bool,
    has_init: Bool,
    has_model: Bool,
    param_names: List(String),
  )
}
