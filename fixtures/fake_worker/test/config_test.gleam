//// Configuration from the environment: the defaults are the contract's, and
//// a bad value stops the worker before it serves anything.

import fake_worker/config
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/result

fn parse(
  pairs: List(#(String, String)),
) -> Result(config.Config, config.ConfigError) {
  let environment = dict.from_list(pairs)
  config.parse(dict.get(environment, _), hostname: "host-1")
}

// StatusEndpoint.Discovery: the defaults are config.status_port and
// config.status_path from worker_contract.allium.
pub fn defaults_test() -> Nil {
  assert parse([])
    == Ok(config.Config(
      mode: config.Worker,
      bind: "0.0.0.0",
      status_port: 8080,
      status_path: "/knarr/v1/status",
      control_port: 8081,
      drain_ms: 10_000,
      sink_url: None,
      pod: "host-1",
    ))
}

// StatusEndpoint.Discovery: the port and path a Deployment's overrides name.
pub fn overrides_test() -> Nil {
  assert parse([
      #("FAKE_WORKER_MODE", "collector"),
      #("FAKE_WORKER_BIND", "::"),
      #("FAKE_WORKER_STATUS_PORT", "9797"),
      #("FAKE_WORKER_STATUS_PATH", "/custom/v1/status"),
      #("FAKE_WORKER_CONTROL_PORT", "0"),
      #("FAKE_WORKER_DRAIN_SECONDS", "3"),
      #("FAKE_WORKER_SINK_URL", "http://collector:8081//"),
      #("POD_NAME", "worker-abc"),
    ])
    == Ok(config.Config(
      mode: config.Collector,
      bind: "::",
      status_port: 9797,
      status_path: "/custom/v1/status",
      control_port: 0,
      drain_ms: 3000,
      sink_url: Some("http://collector:8081"),
      pod: "worker-abc",
    ))
}

pub fn empty_values_mean_the_default_test() -> Nil {
  assert parse([#("FAKE_WORKER_SINK_URL", ""), #("POD_NAME", "")]) == parse([])
}

pub fn bad_values_are_refused_by_name_test() -> Nil {
  list.each(
    [
      #("FAKE_WORKER_MODE", "both"),
      #("FAKE_WORKER_STATUS_PORT", "65536"),
      #("FAKE_WORKER_STATUS_PORT", "-1"),
      #("FAKE_WORKER_CONTROL_PORT", "http"),
      #("FAKE_WORKER_STATUS_PATH", "knarr/v1/status"),
      #("FAKE_WORKER_STATUS_PATH", "/status?x=1"),
      #("FAKE_WORKER_STATUS_PATH", "/status#x"),
      #("FAKE_WORKER_DRAIN_SECONDS", "-1"),
      #("FAKE_WORKER_DRAIN_SECONDS", "1.5"),
      #("FAKE_WORKER_SINK_URL", "https://collector"),
    ],
    fn(pair) {
      let #(variable, value) = pair
      let refused = parse([pair])
      assert result.map_error(refused, fn(error) {
          #(error.variable, error.got)
        })
        == Error(#(variable, value))
    },
  )
}

pub fn describe_names_the_variable_and_the_value_test() -> Nil {
  assert config.describe(config.ConfigError("FAKE_WORKER_MODE", "worker", "x"))
    == "FAKE_WORKER_MODE must be worker, not \"x\""
}
