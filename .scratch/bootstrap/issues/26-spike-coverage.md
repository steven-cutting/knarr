# 26: Spike: coverage for Gleam on the BEAM

**Context:** libpawdoku gates on a line-coverage floor. Gleam's Erlang target can be measured with OTP's `cover`. The starting position is that Gleam 1.19 maps coverage back to Gleam source lines; this spike verifies that before relying on it.

**What to build:** A decision on whether knarr measures coverage, how, and whether a floor goes in the gate.

**Non-goals:** Mutation testing. Raising coverage of existing code.

**Blocked by:** 08

**MVP critical path:** no. It is a quality signal, and the MVP does not need it.

**Status:** ready-for-agent

- [ ] `cover` runs over `gleam test`, and the report maps to Gleam source lines. Any gaps, such as generated code or FFI modules, are recorded.
- [ ] The measurement runs offline and leaves the worktree unchanged, so it could sit in the read-only gate.
- [ ] The ticket decides: a floor (with its value and scope), report only, or no coverage, and gives the reason.
- [ ] A decision record is written, and follow-ups are drafted.
