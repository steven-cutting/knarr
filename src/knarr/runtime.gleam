//// OTP and HTTP adapters. Every server process belongs to the root supervisor.

import gleam/bytes_tree
import gleam/erlang/process.{type Pid}
import gleam/http/response
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision
import knarr/diagnostics
import knarr/metrics
import knarr/s1_probe
import mist

pub type State

pub type Runtime {
  Runtime(pid: Pid, state: State)
}

@external(erlang, "runtime_ffi", "new_state")
fn new_state() -> State

@external(erlang, "runtime_ffi", "ready")
fn ready(state: State) -> Bool

@external(erlang, "runtime_ffi", "mark_ready")
fn mark_ready(state: State) -> Nil

@external(erlang, "runtime_ffi", "set_port")
fn set_port(state: State, port: Int) -> Nil

/// Starts the root supervisor: the listener first, then, with `probe`, the
/// S1 probe under its own supervisor (child id 1). Without it the root has
/// the one child the skeleton had.
pub fn start(
  port port: Int,
  bind bind: String,
  probe probe: Option(s1_probe.Config),
) -> actor.StartResult(Runtime) {
  let state = new_state()
  let child =
    supervision.supervisor(fn() {
      mist.new(fn(request) {
        let result = diagnostics.respond(request, ready(state), metrics.collect)
        response.set_body(
          result,
          mist.Bytes(bytes_tree.from_string(result.body)),
        )
      })
      |> mist.bind(bind)
      |> mist.port(port)
      |> mist.after_start(fn(port, _, _) { set_port(state, port) })
      |> mist.start
    })
  let root =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.restart_tolerance(intensity: 2, period: 5)
    |> supervisor.add(child)
  let root = case probe {
    Some(config) -> supervisor.add(root, s1_probe.supervised(config))
    None -> root
  }
  case supervisor.start(root) {
    Ok(started) -> {
      mark_ready(state)
      Ok(actor.Started(started.pid, Runtime(started.pid, state)))
    }
    Error(error) -> Error(error)
  }
}
