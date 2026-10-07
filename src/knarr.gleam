//// knarr's entry point. The controller does nothing yet; this module exists so
//// the foundation has something to build and test.

import gleam/io

/// The name the controller reports itself by.
pub fn name() -> String {
  "knarr"
}

pub fn main() -> Nil {
  io.println(name())
}
