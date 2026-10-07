import gleam/int
import gleam/io

@external(erlang, "probe_ffi", "count_twice")
fn count_twice() -> Int

pub fn main() -> Nil {
  io.println("prometheus counter after two inc: " <> int.to_string(count_twice()))
}
