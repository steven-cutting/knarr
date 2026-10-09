# Ticket 26 evidence

Evidence for [ticket 26](../../issues/26-spike-coverage.md) and
[Decision 0011](../../../../docs/decisions/0011-coverage.md). The command measures
the existing `gleam test` invocation using Gleam 1.19.0 and OTP 29.1.1. This
evidence is macOS arm64 only; it does not claim native Linux verification.

Captured on 2026-10-09 (UTC): [environment and source hashes](environment.txt),
[coverage and the worktree check](coverage.txt), [machine-readable report](coverage.json),
and [13 command tests](tests.txt). The warm coverage run took 2.06 seconds;
the command tests, including one cold compilation, took 29.86 seconds. These
are individual local measurements, not performance guarantees.

[Claude Code's adversarial review](review.md) records the resolved Opus model,
medium effort, findings, and their disposition. It caught the case-sensitive
`Justfile` fixture defect before hand-back; the evidence here is refreshed after
that correction.

## Reproduce

From an initialized checkout, run:

```sh
sh .scratch/bootstrap/evidence/26/run.sh
```

The script prints an ignored working directory under `ai_tmp/`. It uses macOS
`sandbox-exec` to deny external IP connections while allowing loopback, which
the existing HTTP tests require. It verifies both restrictions with socket
probes, runs coverage through the gate's worktree-snapshot runner, and runs the
coverage command tests. No package is downloaded. If the outer agent sandbox
blocks nested sandbox creation or loopback sockets, the invocation needs local
execution permissions, not external network access.

Reviewed outputs are copied here only after the run finishes, with ANSI colour
codes and trailing whitespace removed. They are evidence, not golden files to
update automatically. The environment transcript identifies
the base commit and working diff used for the experiment; changes are uncommitted
at measurement time. The final source is committed with this evidence.

## Findings

| Production source | Covered / executable |
| --- | --- |
| `src/knarr.gleam` | 1 / 2 |
| `src/knarr/diagnostics.gleam` | 17 / 17 |
| `src/knarr/metrics.gleam` | 0 / 1 |
| `src/knarr/runtime.gleam` | 17 / 17 |
| Gleam total | 35 / 37 |
| `src/knarr/application_ffi.erl` | 5 / 13 |
| `src/knarr/metrics_ffi.erl` | 4 / 4 |
| `src/knarr/runtime_ffi.erl` | 4 / 4 |
| Erlang total | 13 / 21 |

The source-line fixture independently asserts exact line numbers for a called
and an uncalled case alternative, and for called and uncalled FFI functions.
An entirely uncalled module remains in the denominator. A type-only module has
no executable lines. The fixture also shows two alternatives on the same source
line collapsing into one covered line; this is not branch coverage.

The generated external wrapper in `metrics.gleam` is genuinely uncalled:
Gleam's caller targets `metrics_ffi:collect/0` directly. The command reports the
wrapper's zero rather than attributing an external call to a wrapper that did
not run. The fixture reproduces this with an assertion on the FFI's return
value while the declaration line remains uncovered.

Instrumentation begins before application startup. The application callback's
startup call is covered even though it executes before EUnit begins. Collection
finishes in an additional EUnit reporter before gleeunit halts the VM. Coverage
does not include shutdown after collection, checker subprocesses, cluster tests,
dependencies, test helpers, or compiler-generated entrypoints.

## Failure and isolation controls

The command tests exercise real Gleam compilation and `cover` in disposable
checkouts under `ai_tmp/`, with independent compiler artifacts and shared read-only
tool installations. Their command boundary checks cover:

- exact source mapping, FFI separation, generated wrappers, and uncalled modules;
- a cold compilation with cached packages and a module with no executable lines;
- failing assertions and changed snapshots retaining a nonzero status and report;
- a successful entrypoint that never runs EUnit being refused despite an older
  successful report;
- a stripped BEAM lacking debug information failing collection;
- missing package directories, a missing cache index, and stale cached versions
  being refused before a compiler fake could attempt a download;
- a drifted manifest being refused without rewriting it;
- repeated runs producing equivalent reports in distinct directories;
- existing EUnit options and a checkout path containing spaces;
- Git-visible state remaining unchanged on success and failure.

Gleam overrides a source-level `no_debug_info` option, so the missing-metadata
control strips a compiled BEAM at the build command boundary. It does not merely
assume that the source option disabled debug information.

Native Linux verification and reconsideration of a floor are drafted in
[ticket 26's follow-ups](../../issues/26-spike-coverage.md#follow-ups).
