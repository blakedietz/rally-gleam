@external(erlang, "password_ffi", "hash")
pub fn hash(password: String) -> String

@external(erlang, "password_ffi", "verify")
pub fn verify(password: String, hash: String) -> Bool
