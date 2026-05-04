import sqlight

pub type ServerContext {
  ServerContext(db: sqlight.Connection)
}
