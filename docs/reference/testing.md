---
title: "Testing"
kind: "reference"
audience: ["contributor", "maintainer", "agent"]
canonical_for: ["testing_toolkit", "snapshot_workflow", "sans_io_pattern", "coverage_workflow"]
requires: []
---

# Testing

This page covers knarr's unit tests: the tools, the snapshot workflow, and the sans-IO pattern every Kubernetes and worker call follows. The unit suite runs in `just check`; the optional coverage command is described below. The cluster tiers belong to [Decision 0007](../decisions/0007-local-cluster.md#tiers), which [ticket 10](../../.scratch/bootstrap/issues/10-spike-local-cluster.md) settled.

## Tiers known so far

0007's table says what each tier proves, what it cannot prove, and where it runs. In one line each:

- **unit**: gleeunit, qcheck and birdie, through `just test` in `just check`. The rest of this page covers it.
- **kwok**: a real apiserver and real controllers with simulated pods, in its own CI job, outside the read-only gate.
- **kind**: everything kwok gives, plus real pods. 13's smoke test and the e2e job use it.
- **GKE**: run by hand against a short-lived cluster, never on every change.

The gate also runs the diagnostics adapter against local HTTP sockets and
crashes a supervised listener to prove recovery without resetting metrics,
once on an OS-assigned port and once on a fixed port that it must rebind.
These tests need no cluster or external network. Test and
lint recipes select a loopback address and ephemeral application port so concurrent worktrees do
not contend for port 8080 or expose metrics on the LAN. The checker suite also
starts isolated Erlang subprocesses to verify startup failure, exhausted
supervision and normal shutdown exit codes; its recipe builds first. Image and cluster checks are separate recipes in
the [local cluster guide](../how-to/local-cluster.md).

## The toolkit

Every package is a dev dependency. `gleam.toml` gives the range, and `manifest.toml` pins the version and checksum.

| Package | Version | Role |
| --- | --- | --- |
| gleeunit | 1.11.0 | Runs every public function whose name ends in `_test`, in any module under `test/`. |
| qcheck | 1.0.5 | Property tests: generators, shrinking, and 1000 cases by default. |
| birdie | 2.0.2 | File snapshots under `test/birdie_snapshots/`, with review, accept and stale commands. |
| glinter | 2.19.2 | Lints `src/` and `test/` in `just lint-gleam`. |

**Assertions.** A test states what it expects with Gleam's `assert`, such as `assert decode(body) == Ok(version)`. Each expected value comes from somewhere independent of the code under test: a literal, a worked example, or the spec.

**Fixed seeds.** Every property in the gate passes a fixed seed:

```gleam
let config = qcheck.default_config() |> qcheck.with_seed(qcheck.seed(8))
use version <- qcheck.run(config, versions)
```

`qcheck.given` and `default_config()` draw a random seed, and qcheck never prints it. On failure it prints the original value and the shrunk one, but a failure under a random seed cannot be replayed. To explore further, change the seed or raise the case count, and commit the new value.

**glinter.** `[tools.glinter]` in `gleam.toml` lints `src/` and `test/`, with warnings as errors. Test functions declare `-> Nil`, because `missing_type_annotation` applies to them too. `unused_exports` is off for `*_test.gleam` files only: gleeunit finds those functions by name, so no module ever imports them. Helper modules in `test/` keep the rule. glinter skips a file it cannot read or parse, a directory it cannot read, and a `gleam.toml` it cannot parse, and still exits 0. So `just lint-gleam` runs it through `scripts/checks/run_glinter.sh`, which fails on any such report.

**Compiler warnings.** `just build` runs `gleam build --warnings-as-errors`, which compiles `test/` as well as `src/`. A warning in test code therefore fails the gate. `gleam test` alone only prints it.

## Coverage reports

Run `just coverage` for source-line coverage of application startup and the
existing Gleam test suite. It builds with warnings as errors, preserves the
snapshot workflow, and prints each production source file's covered and total
executable lines plus uncovered line numbers. Gleam and Erlang FFI have separate
totals. A module that is never called still counts; one with no executable lines
shows `n/a`. Tests, dependencies and compiler-generated entrypoints do not count.

When collection and report generation complete, the command prints the fresh
directory under `build/coverage/` containing `coverage.txt` and `coverage.json`.
The JSON lists source-relative paths,
languages, covered and uncovered line numbers, per-file counts, separate totals,
and the test command's exit code. Failed tests still produce useful reports when
collection completes, but the command exits nonzero. Cache or build failures
create no run directory. Missing instrumentation or incomplete collection can
leave an unfinished directory without reports; its path is not printed. These
failures return nonzero even if the test entrypoint exits zero; an old report
cannot satisfy a new run.

The command is **report only**, outside `just check`, with no percentage floor.
Its command tests run in the checker suite. Cached packages and the pinned local
toolchain are required; missing or stale cache inventory is refused before Gleam
can fetch. Initialization needs separate network authorization. Runtime artifacts
are ignored, and local HTTP tests use loopback. The command neither accepts
snapshots nor rewrites source files.

Coverage describes execution, not correctness. External declarations can report
uncalled generated Gleam wrappers even when their Erlang functions execute.
Alternatives on the same physical line share one result. Checker subprocesses,
cluster tests, and shutdown after collection are outside this report. See
[Decision 0011](../decisions/0011-coverage.md) for the measured limitations and
the reason for deferring a floor. A snapshot contributes execution counts but
still proves no clause.

## Snapshots

A snapshot test writes a value out as text, a "picture", and compares it with the accepted copy in `test/birdie_snapshots/<title>.accepted`. A snapshot has two uses only:

- to show a reviewer a value that reads better as a picture than as assertions, such as a request as it goes out
- to detect a change cheaply

### A snapshot proves no clause

A snapshot records what the code did when someone accepted it. If they accepted a bug, the snapshot now defends that bug. So every obligation `just plan-spec` lists for a spec module has its own named test, whose assertion states the expected value. No clause-to-test table names a snapshot test.

### Writing a snapshot test

- Write it after the behaviour's own tests are green.
- Name it `snapshot_<subject>_test`.
- Feed it a fixed, deterministic input. Never use a property's generated value: one title holds one picture, and every generated case would overwrite it.
- Render the picture in test code, as [http_picture.gleam](../../test/http_picture.gleam) does. A picture is for reviewers and is not a product format.
- Keep trailing whitespace out of the picture. editorconfig-checker reads the `.accepted` files, and birdie adds the one final newline itself.
- Give each test a unique, literal title. birdie names the file after the title. `review` and `accept` find the test through that literal, and they fail on a duplicate.

### A changed snapshot is a question

A diff in an `.accepted` file is reviewed like code. The pull request that changes a snapshot says why the new picture is right. Accepting is a decision, not a repair.

## Snapshot workflow

| Recipe | In `just check` | Writes | Does |
| --- | --- | --- | --- |
| `just test` | yes | ignored paths only | Removes every `.new`, then runs every test. A new or changed snapshot fails and leaves `<title>.new`. |
| `just snapshots-check` | yes, after `test` | nothing | Fails on a pending `.new`, then on an accepted snapshot the last `just test` did not reference. |
| `just snapshots-stale` | no | ignored paths only | Runs the tests and, if they pass, lists stale snapshots. A test that fails before it snaps would make its snapshot look stale. |
| `just snapshots-review` | no | tracked files, when you accept | Runs the tests (ignoring their failure), then opens birdie's interactive review. |
| `just snapshots-accept` | no | tracked files | Runs the tests, then accepts every pending snapshot without prompting. Read the diff before committing. |
| `just birdie <command>` | no | depends on the command | Any other birdie command, such as `reject` or `stale delete`. |

The usual loop: change the code, run `just test`, and see a snapshot fail with its diff. Run `just snapshots-review`, or `just snapshots-accept` if you are an agent. Then read `git diff test/birdie_snapshots/` and commit the change with its reason.

### birdie has no check mode

birdie 2.0.2 has no mode that only compares: no flag, environment variable or setting. When a snapshot is new or changed, `birdie.snap` always writes `<title>.new` beside the accepted file, prints the picture or diff, and fails the test. The gate's "read-only" means what its runner checks: nothing Git can see may change ([Decision 0004](../decisions/0004-gate-checkers.md)). So `.gitignore` ignores `test/birdie_snapshots/*.new`, just as it ignores `build/`. A failing gate leaves the `.new` that `just snapshots-review` reads next. `just test` removes every `.new` before it runs, so each one left afterwards is a picture from that run, and no accept can take an older one. The [ticket 08 evidence](../../.scratch/bootstrap/evidence/08/README.md) shows each case.

### Each worktree keeps its own referenced list

During a test run, birdie appends the name of each accepted snapshot it reads to `$TMPDIR/knarr_referenced.txt`, and `stale check` compares the snapshot folder against that list. The file is named after the project only. Without a change, every worktree on a machine would share one list, and one worktree's test run would decide another's stale check. So every recipe that runs birdie sets `TMPDIR` to `build/birdie`, which is ignored.

`TMPDIR` is set per recipe, not exported from the Justfile, because the gate runner's baseline file and pytest's `tmp_path` also read it. `just test` deletes the list first: birdie empties it only when a run reads an accepted snapshot, so a run that read none would leave the old list behind.

Run birdie's other commands through `just birdie`, for example `just birdie stale delete`. A bare `gleam run -m birdie stale delete`, as birdie's own hints suggest, reads the shared list in the system's temporary directory instead.

### Rejecting and deleting

- `just birdie reject` deletes every pending `.new`.
- `just birdie stale delete` deletes every accepted snapshot the last `just test` did not reference. Those are tracked files.

`review`, `accept` and `reject` also rewrite the `file:` and `test_name:` header of an existing `.accepted` file whose test moved or was renamed. That is a tracked change too.

## The sans-IO pattern

[Decision 0002](../decisions/0002-sans-io-boundaries.md) keeps effects behind sans-IO boundaries. An HTTP call is split three ways:

1. **A pure builder** takes values and returns a `Request(String)`.
2. **A pure decoder** takes a `Response(String)` and returns a typed result. Every way it can fail is a named error.
3. **A function that does the I/O** only through a `send` it is given, of type `fn(Request(String)) -> Result(Response(String), e)`. Production passes `k8s_http.send(_, k8s_http.Tls(ca_file))`, the verified-TLS adapter from [Decision 0012](../decisions/0012-in-cluster-client.md); `gleam_httpc` is not used because it cannot carry a CA file. A test passes a closure.

The builder and the decoder are tested by value. The I/O function is tested with a closure fake. The fake asserts the request it was handed and returns a canned response. A second fake returns `Error(_)`, to test the failure path. To snapshot the outgoing request, take the picture inside the fake: it then shows exactly what the function sent, not a request the test built again.

The real client, `src/knarr/k8s_client.gleam` with `test/k8s_client_test.gleam`, follows the same shape for the pod list and the annotation patch. The worked example lives in `test/` only, because it is not part of knarr. It models the apiserver's `GET /version`, a real, read-only call that decides nothing:

- [sans_io_example.gleam](../../test/sans_io_example.gleam): the builder, the decoder and `fetch_version`
- [sans_io_example_test.gleam](../../test/sans_io_example_test.gleam): named tests, the closure fakes, a fixed-seed property, and a snapshot taken inside the fake
- [http_picture.gleam](../../test/http_picture.gleam): renders a request as a picture

These tests prove the pure parts and how they are joined. They prove nothing about real HTTP or a real apiserver. The kwok and kind tiers cover those, as 0002 and 0007 expect.

Gleam has no HTTP mocking library like respx, and this pattern takes its place. Use `http_server_mock` only where a test needs a real socket. It brings in mist and gleam_otp, so it is not a dependency until a ticket needs it. TestContainers is skipped; 0007 says why.
