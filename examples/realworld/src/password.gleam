import argus

pub fn hash(password password: String) -> String {
  case argus.hasher() |> argus.hash(password, argus.gen_salt()) {
    Ok(hashes) -> hashes.encoded_hash
    Error(_error) -> ""
  }
}

pub fn verify(password password: String, stored stored: String) -> Bool {
  case argus.verify(stored, password) {
    Ok(True) -> True
    _ -> False
  }
}
