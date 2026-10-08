# Ticket 08 evidence

Evidence for [ticket 08](../../issues/08-testing-toolkit.md): how birdie behaves in the read-only gate, which the ticket asks to verify. Gathered on 2026-10-08 (UTC) on an Apple-silicon Mac (Darwin arm64), with birdie 2.0.2, glinter 2.19.2, Gleam 1.19.0 and OTP 29. Nothing here ran on linux-64.

[birdie-check.sh](birdie-check.sh) exits non-zero on any unexpected result, and [birdie-check.txt](birdie-check.txt) is its transcript. It works in a throwaway clone of the committed branch and writes only to the work directory it is given.

## Rerun

```sh
sh .scratch/bootstrap/evidence/08/birdie-check.sh "$(mktemp -d)"
```

Run it from a checkout where `just initialize` has run. The clone borrows that checkout's `.pixi` and `.tools` through symlinks and copies its `build/packages`, so it needs no network. Every `just` command runs with outbound network denied: through `sandbox-exec` on macOS, and `unshare -rn` on Linux.

## What birdie does

Read from birdie 2.0.2's source, then observed by the script:

- **There is no check mode.** No flag, environment variable or setting makes `birdie.snap` only compare. On a new or changed snapshot it always writes `<title>.new` beside the accepted file, prints the picture or the diff, and fails the test. On a match it deletes any `.new` left over for that title.
- **The referenced list lives in `$TMPDIR/<project>_referenced.txt`.** It is named after the project only, so without a change every worktree would share it. birdie empties it only when a run first reads an accepted snapshot. `stale check` fails when the list is missing.
- **`accept` takes every `.new` present**, whichever run wrote it. So `just test` removes every `.new` before it runs.
- **`review`, `accept` and `reject` find each snapshot's test** by its literal title. They fail when two tests share a title, and they rewrite the `file:` and `test_name:` header of an accepted file whose test has moved.

## What it shows

In a clone of the branch:

- The baseline `just check` passes, and the worktree is unchanged afterwards.
- One changed character in the accepted file makes `just check` stop at `just test`, naming the snapshot and showing the diff. The runner reports no worktree change. `git status --untracked-files=all` shows only the deliberate edit, and `git status --ignored` shows the `.new`.
- `just snapshots-check` then fails, naming the pending `.new`.
- `just snapshots-accept` restores the committed file byte for byte: `git diff` is empty and no `.new` remains.
- A deleted accepted file, which makes the snapshot new, behaves the same way.
- With the snapshot test failing before it snaps, and a wrong `.new` from an earlier run planted, `just snapshots-accept` accepts nothing and the accepted file is unchanged: `just test` removed the old `.new` first. Without that removal, birdie's `accept` took the old picture into the tracked file (reproduced by hand, not in the transcript).
- An accepted file that no test refers to lets `just test` pass, but fails `just snapshots-check`, naming it. `just snapshots-stale` lists it.
- `just test` writes the referenced list to the clone's `build/birdie/knarr_referenced.txt`. Neither the source checkout's list nor the one in the system `TMPDIR` changes during the run.
- `gleam run -m glinter` on a file glance cannot parse prints `Error: Failed to parse …` and exits 0. `scripts/checks/run_glinter.sh` exits 1 on the same file. The file sits outside `src/` and `test/`, where the compiler, which builds both, would reject it before glinter ran.

`scripts/checks/tests/test_run_glinter.py` covers the wrapper's other cases.
