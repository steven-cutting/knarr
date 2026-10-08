# 08: Testing toolkit

**Context:** This adapts libpawdoku's T29. Gleam has no source-rewriting snapshot tool like inline-snapshot. `birdie` 2.x gives file snapshots in the style of insta, with review, accept and stale commands. There is no respx equivalent either, so effects sit behind sans-IO boundaries: pure request builders and decoders, plus an injected `send` function that a test replaces with a closure. `http_server_mock` (hex, young) is the fallback only where a real socket is needed. OVERVIEW §9.16 asks for unit tests of the mapping and banding.

**What to build:** A contributor can write unit, property and snapshot tests, run them in the read-only gate, and review snapshot changes deliberately. A worked sans-IO example shows the pattern every Kubernetes and worker-poll call will follow.

**Non-goals:** Coverage (26). Cluster test tiers (10). A real Kubernetes client (14).

**Blocked by:** 03, 06

**MVP critical path:** yes. The walking skeleton (13) and S1 (14) use this toolkit and pattern.

**Status:** done. See [the hand-back notes](#hand-back-notes) and the [evidence](../evidence/08/README.md).

- [x] gleeunit, qcheck and birdie are pinned dependencies, each with one example test. glinter runs in `just check`.
- [x] The snapshot recipes are:
  - a non-writing check, inside `just check`, that fails on a new or changed snapshot
  - stale, which lists unused snapshots
  - review and accept, both outside the gate
- [x] The ticket verifies how birdie behaves in check mode and records it.
- [x] The rule "a snapshot proves no clause" is written down. A spec obligation needs a named assertion, not a snapshot.
- [x] A worked sans-IO example: a pure request builder, a pure decoder, and a function that takes `send`. A closure fake exercises it, and the outgoing request is snapshotted.
- [x] A testing reference page, registered in the docs manifest, covers the tiers known so far, the snapshot workflow and the sans-IO pattern. It links to 10 for cluster tiers.
- [x] `just check` is green and the worktree is clean.

## Hand-back notes

Each box above is met on branch `08-testing-toolkit`:

- **Dependencies:** dev dependencies only. `gleam.toml` gives each a range in gleeunit's style (`>= <version> and < <next major>`), and `manifest.toml` pins the version and checksum. Licences come from each package's `gleam.toml`:

  | Package | Version | Licence | Why |
  | --- | --- | --- | --- |
  | gleeunit | 1.11.0 | Apache-2.0 | the runner, already present |
  | qcheck | 1.0.5 | Apache-2.0 and MIT | property tests |
  | birdie | 2.0.2 | Apache-2.0 | file snapshots |
  | glinter | 2.19.2 | MIT | the Gleam linter |
  | gleam_http | 4.4.0 | Apache-2.0 | the `Request` and `Response` types `send` uses |
  | gleam_json | 3.1.0 | Apache-2.0 | the example's decoder (birdie already pulled it in) |

  They bring 21 transitive packages, all pure Gleam and all Apache-2.0 except glexer (MIT). `gleam_http` resolves on stdlib 1.0.5.
- **One example test each:** gleeunit runs `name_test` and the named tests in `test/sans_io_example_test.gleam`. qcheck runs `decode_version_reads_back_any_encoded_version_test`, with a fixed seed. birdie runs `snapshot_version_request_test`, accepted through `just snapshots-accept`.
- **glinter in `just check`:** `just lint-gleam` runs it over `src/` and `test/` with `warnings_as_errors = true`, through `scripts/checks/run_glinter.sh`. Test functions now declare `-> Nil`, `name_test` included, because of `missing_type_annotation`. `unused_exports` is ignored for `test/**/*_test.gleam` only, and a helper module in `test/` with an unused export still fails.
- **Snapshot recipes:** `snapshots-check` is in the gate, straight after `test`. It fails on a pending `.new`, then runs birdie's `stale check`. `snapshots-stale`, `snapshots-review` and `snapshots-accept` are develop recipes outside the gate, and so is `birdie`, which runs any other birdie command with the worktree's `TMPDIR`.
- **birdie in check mode:** birdie has none. [The evidence](../evidence/08/README.md) records what it does instead and what the gate does about it (see below).
- **"A snapshot proves no clause":** in [docs/reference/testing.md](../../../docs/reference/testing.md#a-snapshot-proves-no-clause).
- **Worked sans-IO example:** `test/sans_io_example.gleam` builds and decodes the apiserver's `GET /version`, and `fetch_version` takes `send`. A closure fake checks the request it was handed, a second fake returns `Error(_)`, and the snapshot is taken inside the fake. It was written test-first, one seam at a time: builder, decoder, then `fetch_version`. Mutation checks confirmed that the fake's assertion and the property each fail on a wrong implementation.
- **Testing reference page:** `docs/reference/testing.md`, registered in `docs/manifest.yml` and linked from `docs/README.md`. It owns `testing_toolkit`, `snapshot_workflow` and `sans_io_pattern`, and links to 0007's tiers and to ticket 10 for the cluster tiers.
- **`just check` is green and the worktree is clean** after the last commit.

What birdie 2.0.2 does, read from its source and shown in [birdie-check.txt](../evidence/08/birdie-check.txt):

- **No check mode.** On a new or changed snapshot, `birdie.snap` always writes `<title>.new` and fails the test. "Non-writing" therefore means the gate's own contract: nothing Git can see changes. `test/birdie_snapshots/*.new` is gitignored, as `build/` is, and the gate fails at `just test` without the runner reporting a worktree change. The `.new` it leaves is what `just snapshots-review` reads next.
- **The stale list is shared across worktrees by default.** birdie writes it to `$TMPDIR/knarr_referenced.txt`. Each birdie-running recipe sets `TMPDIR` to the ignored `build/birdie`. This is set per recipe, not exported, because the gate runner and pytest's `tmp_path` also read `TMPDIR`.
- **A stale list can survive a run.** birdie empties the list only when a run reads an accepted snapshot, so `just test` deletes it first. `stale check` fails when the list is missing.
- **`accept` takes every `.new` present, whichever run wrote it.** `just test` therefore removes every `.new` first (see the review findings below).
- **Accepted files are reproducible.** The `file:` header is relative (`./test/…`), so an accept on another machine writes the same bytes. The evidence shows `git diff` empty after accepting.

These depart from the plan or the ticket:

- **Stale snapshots fail the gate.** The ticket only says stale "lists". libpawdoku's T29 rejected orphans in its gate, and a snapshot no test reads would otherwise sit unnoticed. A side effect is that a snapshot test that never calls `birdie.snap` (for example, because the fake was never called) fails the gate too.
- **The glinter wrapper catches more than parse failures.** glinter 2.19.2 also skips an unreadable file and an unreadable directory, and falls back to its defaults on a `gleam.toml` it cannot parse, with `warnings_as_errors` then off. Each prints a line starting `Error:` or `Warning:` and exits 0. The wrapper fails on any of them. gleam's own diagnostics start with a lower-case `error:` and keep their status.
- **`birdie` is a listed recipe, not private.** `reject` and `stale delete` need this worktree's `TMPDIR`, and birdie's own hint, a bare `gleam run -m birdie stale delete`, would read the shared list. The testing page says to use `just birdie`.
- **Decision 0008 is registered with the docs contract** (a separate commit). On `main`, `just check` failed at `docs-check`: PR #2 added 0008 and PR #4 then brought in the contract, so 0008 was unregistered and unreachable. Its frontmatter `requires: [decision_local_cluster]` also named a decision rather than a feature predicate. The fix adds the manifest entry and the decision-index line, and empties `requires`. 09's worktree is on the same `main` commit and will hit the same failure until this merges.
- **The root README now says five recipe groups.** "Four groups" left out `audit`.

Verified rather than assumed:

- `gleam build --warnings-as-errors` compiles `test/`, so a warning in test code fails `just build`. A probe file with an unused variable failed it, while `gleam test` only printed the warning.
- The evidence script ran every `just` command with outbound network denied, and `curl` to github.com failed inside that sandbox.

Not verified:

- Nothing ran on linux-64. CI's first run of this branch is the first.
- The `/version` body in the tests is cut down from a kind v1.35.8 reply by hand, not captured. The repository holds only the server's `gitVersion` (10's evidence). Kubernetes sends `major` and `minor` as strings, and a managed cluster's `minor` may carry a `+`. That is from memory of `version.Info`, so the example models them as strings, which commits to nothing.

Code review findings applied:

- **`just snapshots-accept` could accept an old picture.** It runs the tests, ignores their failure, and then accepts every `.new`. When a snapshot test failed before it reached `birdie.snap`, a `.new` from an earlier run was accepted into the tracked file. Reproduced by hand: a test that panics before it snaps, a planted wrong `.new`, then `birdie accept` replaced the accepted line. `just test` now removes every `.new` before it runs, so each one left is from that run. The evidence has the case.
- **The lists of writing recipes left out `just birdie`**, which can delete or write tracked snapshot files. The root README and the Justfile comment now name it.
- **The wrapper's pass-through test could not see word splitting.** The stand-in recorded `"$*"`. It now records one argument per line, and with the wrapper's `"$@"` unquoted the test fails.
- **`snapshots-pending` passed on a directory it could not read**, because it sent `find`'s errors to `/dev/null`. A missing directory still means nothing is pending, and an unreadable one now fails with `find`'s error.
- **`snapshots-stale` prints nothing when a test fails.** That is kept on purpose, because a test that fails before it snaps would make its snapshot look stale. The recipe's doc and the testing page now say "if they pass".

Code review findings declined:

- **`http_picture` neither escapes nor rejects a newline in a header value**, so two different requests could render alike. Snapshot inputs are fixed literals, and a header value that holds a newline is not valid HTTP.
- **The manifest guard line is repeated in four recipes, and `manifest-check` runs five times per gate.** That is 03's existing pattern, and each run takes milliseconds. A wrapper for the guard would be a refactor of 03's recipes, outside this ticket.

Follow-ups:

- **09:** add one AGENTS.md sentence: accept snapshots with `just snapshots-accept`, read the diff, and give the reason in the pull request.
- **11 and 13:** rerun `just initialize` (or `gleam deps download`) in each worktree to fetch the new hex packages. Until then, `just build` fails offline.
- **14:** pass `httpc.send` to the S1 client's `fetch` functions unchanged. Move `gleam_http` and `gleam_json` into `[dependencies]` once `src/` uses them.
- **26:** count snapshot tests like any other test. A snapshot covers no clause.
