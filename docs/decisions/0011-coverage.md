---
title: "Decision 0011: Report-only source coverage"
kind: "decision"
audience: ["maintainer", "agent"]
canonical_for: ["decision_coverage"]
requires: []
---

# Decision 0011: Report-only source coverage

## Decision

Measure executable source lines with OTP's `cover`, through `just coverage`.
Keep the command outside `just check` and impose no percentage floor. The
command fails when tests fail or measurement is incomplete; a low percentage
alone never fails it. This is a contributor diagnostic, not evidence that a
specification obligation is satisfied.

[Ticket 26's evidence](../../.scratch/bootstrap/evidence/26/README.md) verifies
Gleam 1.19.0 and OTP 29.1.1 on macOS arm64. Native Linux execution remains
unverified. No dependency or tool pin changes are required.

## Measurement

The command checks the cached package inventory and manifest before building.
It then runs the existing `just test` recipe. An Erlang boot hook instruments
production modules before the OTP application starts. An additional EUnit
reporter collects before gleeunit calls `erlang:halt`. The wrapper requires a
fresh completed report even if the test command exits successfully.

Reports map back to production `.gleam` and `.erl` source files. Uncalled modules
remain in the denominator. Gleam and FFI totals are separate; tests, dependencies,
the coverage tooling, and compiler-generated entrypoints are excluded. Modules
without executable lines are not applicable. Multiple observations on one
physical source line count once, and any execution marks that line covered.

All generated files stay under ignored paths. With cached packages, the command
runs with external networking denied and loopback allowed for the existing HTTP
tests. Missing caches require separately authorized initialization; the command
does not download dependencies.

## Why no floor

The measured baseline is 35/37 Gleam lines and 13/21 FFI lines. Those small
denominators belong to the walking skeleton, not the eventual controller.
Setting a threshold from them would encode the skeleton's shape rather than
the strength of its tests.

There are also concrete limits to the metric:

- Gleam emits wrappers for external declarations, but compiles callers directly
  to the external function. `metrics.collect` therefore reports its generated
  wrapper as uncovered while the called Erlang function is covered. The report
  retains that zero rather than guessing that a source declaration executed.
- Multiple alternatives on one line share one coverage result. Line coverage
  cannot establish that every branch or specification obligation was tested.
- The command measures application startup and the current `gleam test` VM.
  It does not merge the checker suite's separate Erlang subprocesses, shutdown
  execution after collection, or cluster tests. These limits explain some FFI
  gaps without excusing missing assertions.
- Snapshot tests contribute execution counts like other tests. A snapshot still
  proves no clause.

Reconsider a floor after the reconcile and ownership implementations land, the
native Linux measurement is verified, and generated-wrapper and subprocess
scope are explicitly accounted for. Any later floor needs its own value,
denominator, evidence, and decision; this record authorizes none.

## Contributor interface

The [testing reference](../reference/testing.md#coverage-reports) owns command
usage and report interpretation. [Ticket 26](../../.scratch/bootstrap/issues/26-spike-coverage.md)
records verification and drafts the follow-up work. Mutation testing and raising
existing coverage were outside the spike.
