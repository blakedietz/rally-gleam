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

pub type PageContract {
  PageContract(
    to_backend_variants: List(String),
    to_frontend_variants: List(String),
    has_server_update: Bool,
    has_server_init: Bool,
    has_load: Bool,
    has_init: Bool,
    has_model: Bool,
    param_names: List(String),
  )
}
