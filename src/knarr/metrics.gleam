//// The sole application interface to the Prometheus library.

@external(erlang, "metrics_ffi", "collect")
pub fn collect() -> String
