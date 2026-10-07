import gleeunit
import knarr

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn name_test() {
  assert knarr.name() == "knarr"
}
