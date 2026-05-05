import argus

pub fn hash(password: String) -> String {
  let assert Ok(hashes) =
    argus.hasher()
    |> argus.hash(password, argus.gen_salt())
  hashes.encoded_hash
}

pub fn verify(password: String, stored: String) -> Bool {
  case argus.verify(stored, password) {
    Ok(True) -> True
    _ -> False
  }
}
