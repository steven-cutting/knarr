import gleam/string
import knarr/metrics

pub fn startup_counter_and_vm_collectors_test() -> Nil {
  let first = metrics.collect()
  assert string.contains(first, "# TYPE knarr_startups_total counter\n")
  assert string.contains(first, "knarr_startups_total 1\n")
  assert string.contains(first, "erlang_vm_")
  assert string.contains(metrics.collect(), "knarr_startups_total 1\n")
}
