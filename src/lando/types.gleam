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
