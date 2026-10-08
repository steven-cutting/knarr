import gleeunit
import knarr

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn name_test() -> Nil {
  assert knarr.name() == "knarr"
}
