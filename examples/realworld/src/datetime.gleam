import gleam/int

@external(erlang, "calendar", "universal_time")
fn universal_time() -> #(#(Int, Int, Int), #(Int, Int, Int))

pub fn now_iso8601() -> String {
  let #(#(year, month, day), #(hour, min, sec)) = universal_time()
  int.to_string(year)
  <> "-"
  <> pad2(month)
  <> "-"
  <> pad2(day)
  <> "T"
  <> pad2(hour)
  <> ":"
  <> pad2(min)
  <> ":"
  <> pad2(sec)
  <> "Z"
}

fn pad2(n: Int) -> String {
  case n < 10 {
    True -> "0" <> int.to_string(n)
    False -> int.to_string(n)
  }
}
