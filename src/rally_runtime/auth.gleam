//// Types for Rally's auth framework. These are used in page modules
//// (via `pub const page_auth = auth.Required`) and in SSR load functions
//// (via `LoadResult` return types). The auth module itself (resolve,
//// is_authenticated, authorize) is defined per-namespace by the app;
//// these types are the contract Rally expects.

/// Per-page auth policy, declared as `pub const page_auth` in page modules.
/// Required: the user must be authenticated to view the page.
/// Optional: identity is resolved if available, but the page loads either way.
pub type AuthPolicy {
  Required
  Optional
}

/// Return type for auth-enabled `load` functions.
/// Page: render the page with data and optionally set/clear cookies.
/// Redirect: send the user elsewhere (e.g., after login or permission failure).
pub type LoadResult(data) {
  Page(data: data, cookies: List(Cookie))
  Redirect(url: String, cookies: List(Cookie))
}

/// A cookie to set or clear in the SSR response.
pub type Cookie {
  SetCookie(name: String, value: String, max_age: Int)
  ClearCookie(name: String)
}
