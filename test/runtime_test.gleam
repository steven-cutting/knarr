import gleeunit/should
import knarr/runtime

@external(erlang, "runtime_test_ffi", "recover")
fn recover(root: runtime.Runtime) -> Bool

pub fn listener_recovers_and_preserves_metrics_test() -> Nil {
  let started = runtime.start(port: 0, bind: "127.0.0.1") |> should.be_ok
  assert recover(started.data)
}

@external(erlang, "runtime_test_ffi", "occupied_port")
fn occupied_port(start: fn(Int) -> result) -> Bool

pub fn occupied_port_fails_startup_test() -> Nil {
  assert occupied_port(fn(port) { runtime.start(port: port, bind: "127.0.0.1") })
}
