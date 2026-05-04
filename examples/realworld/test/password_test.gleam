import gleam/string
import gleeunit/should
import password

pub fn hash_produces_prefixed_string_test() {
  let hashed = password.hash("mysecret")
  hashed
  |> string.starts_with("pbkdf2_sha256$")
  |> should.be_true
}

pub fn verify_correct_password_test() {
  let hashed = password.hash("correctpassword")
  password.verify("correctpassword", hashed)
  |> should.be_true
}

pub fn verify_wrong_password_test() {
  let hashed = password.hash("correctpassword")
  password.verify("wrongpassword", hashed)
  |> should.be_false
}

pub fn different_hashes_for_same_password_test() {
  let hash1 = password.hash("samepassword")
  let hash2 = password.hash("samepassword")
  should.not_equal(hash1, hash2)
}
