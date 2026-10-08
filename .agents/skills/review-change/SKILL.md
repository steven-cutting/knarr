---
name: review-change
description: Review a change in this repository against its invariants, specifications, tests, and documentation contract.
---

# Review a change

1. Read `AGENTS.md` and the specification module under `docs/specs/` the change touches. Review the whole diff, not the summary of it.
2. Check the invariants in `AGENTS.md` one at a time. Specs decide behaviour; effects behind sans-IO boundaries; FFI only in named `*_ffi.erl` modules; every process supervised; the controller writes only the annotations it owns, never replica counts, never the pod template, never a pod past `deletionTimestamp`.
3. Check the change against the specification it implements. A rule, guard or threshold decided in code rather than in `docs/specs/` is a finding even when the behaviour looks right.
4. Check the test evidence. A test that only asserts a function was called is not evidence; a test that supplies observations and a clock to the decision logic and asserts the decision it produced is. An adapter without a test that proves its HTTP or Kubernetes behaviour is a finding.
5. Check the boundaries. Nothing in the decision logic may read a clock, the network or the environment on its own, and no test may replace an injected effect with a global.
6. Check documentation ownership. A durable fact belongs on the page that owns its topic in `docs/manifest.yml`, added there rather than restated.
7. Check scope. Unrelated refactors, new dependencies, moved pins and speculative abstractions are findings in themselves.
8. Report findings by severity with `file:line`, what breaks, and the smallest fix. Run `just check` before concluding.
