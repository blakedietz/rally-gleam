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
    client_root: String,
  )
}
