# 26: Spike: coverage for Gleam on the BEAM

**Context:** libpawdoku gates on a line-coverage floor. Gleam's Erlang target can be measured with OTP's `cover`. The starting position is that Gleam 1.19 maps coverage back to Gleam source lines; this spike verifies that before relying on it.

**What to build:** A decision on whether knarr measures coverage, how, and whether a floor goes in the gate.

**Non-goals:** Mutation testing. Raising coverage of existing code.

**Blocked by:** 08

**MVP critical path:** no. It is a quality signal, and the MVP does not need it.

**Status:** done.

- [x] `cover` runs over `gleam test`, and the report maps to Gleam source lines. Any gaps, such as generated code or FFI modules, are recorded.
- [x] The measurement runs offline and leaves the worktree unchanged, so it could sit in the read-only gate.
- [x] The ticket decides: a floor (with its value and scope), report only, or no coverage, and gives the reason.
- [x] A decision record is written, and follow-ups are drafted.

## Hand-back notes

The implementation adds `just coverage`, a report-only developer command outside
`just check`. A Python wrapper checks the manifest and package cache, builds
through the existing recipe, and runs `just test` with a tooling-only Erlang boot
hook and EUnit reporter. Instrumentation precedes OTP startup; collection finishes
before gleeunit halts. Incomplete reports and test failures fail the command.

Production Gleam and Erlang FFI sources have separate totals. Tests, dependencies,
the reporting helper, and generated entrypoints are excluded. Each invocation
writes a new ignored report directory and never accepts snapshots. There are no
dependency, pin, controller, or specification changes.

[Decision 0011](../../../docs/decisions/0011-coverage.md) chooses report only,
without a floor. The baseline is 35/37 Gleam lines and 13/21 FFI lines. The
generated wrapper for the external `metrics.collect` is uncalled despite the
Erlang function being exercised. Native Linux, checker subprocesses, cluster tests,
and shutdown after collection are not part of this measurement claim.

The [testing reference](../../../docs/reference/testing.md#coverage-reports)
owns usage. [The evidence](../evidence/26/README.md) owns reproduction and measured
results. Command-boundary tests cover mapping, uncalled and empty modules,
startup, failure propagation, missing metadata, cache guards, manifest drift,
freshness, path handling, and unchanged Git-visible files.

## Follow-ups

- **Native Linux coverage verification:** after 26, run the command tests and
  measurement on native linux-64 with the locked toolchain, external networking
  denied and loopback enabled. Record source revision, tool versions, source-line
  assertions, exit statuses, runtime and the unchanged worktree. A green macOS
  run or unrelated Linux gate does not close this item. The evidence harness's
  macOS sandbox wrapper needs a Linux equivalent; the coverage command itself
  has no macOS dependency.
- **Reconsider a coverage floor:** after 31 and 32 implement the reconcile and
  ownership behaviour, and after native Linux verification, collect representative
  baselines on both platforms. Decide whether generated external wrappers and
  subprocess/shutdown execution belong in the denominator before proposing a
  numerical floor. Any gate addition requires a new evidence-backed decision;
  neither this ticket nor Decision 0011 enables it.

## Validation and review

The offline measurement left Git-visible files unchanged. All 13 coverage command
tests pass; the full `just check` gate passes with 21 Gleam tests and 325 checker
tests, ending with “All checks passed and the worktree is unchanged.”

[Claude Code’s adversarial review](../evidence/26/review.md) used the latest Opus
alias, resolved to Opus 5.5, at medium effort. Its case-sensitive `Justfile`
fixture finding is fixed, along with the timeout and documentation findings.
No blocking review finding remains. Native Linux execution remains the explicit
follow-up above.
