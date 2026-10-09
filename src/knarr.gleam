//// The OTP application starts the supervised HTTP tree before main runs.

@external(erlang, "application_ffi", "await_shutdown")
fn await_shutdown() -> Nil

/// The name the controller reports itself by.
pub fn name() -> String {
  "knarr"
}

pub fn main() -> Nil {
  await_shutdown()
}
