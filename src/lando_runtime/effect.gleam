import lustre/effect.{type Effect}

pub fn send_to_backend(_msg: a) -> Effect(b) {
  effect.from(fn(_dispatch) { Nil })
}

pub fn send_to_client(_msg: a) -> Effect(b) {
  effect.from(fn(_dispatch) { Nil })
}

pub fn broadcast(_msg: a) -> Effect(b) {
  effect.from(fn(_dispatch) { Nil })
}
