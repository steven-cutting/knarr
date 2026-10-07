# 03: Foundation: a green `just check` from a fresh clone

**Context:** This adapts libpawdoku's T00 (foundation) and T03 (hooks and dotfiles), with the tool manager from 01 and the checker decisions from 02. libpawdoku taught three lessons that apply here. Fix one branch-name convention before lanes fork. State the first-run network requirement plainly. Install hooks only from the primary checkout, because linked worktrees share `.git/hooks`.

**What to build:** A contributor or agent clones the repository, runs `just initialize` once (with network), then runs `just check` and gets green, offline, with the worktree unchanged. The foundation stays small. Each later lane brings its own validator into the gate.

**Non-goals:** CI (05). The docs layout and docs validator (06). Allium (07). Test libraries beyond gleeunit (08). Real `AGENTS.md` content (09). Any controller behaviour.

**Blocked by:** 01, 02

**From 01:** [Decision 0003](../../../docs/decisions/0003-tool-manager.md) settles 01. It gives the exact `pixi.toml`, the rebar3 pin and the lock-check command. [01's hand-back notes](01-tool-manager-decision.md#follow-ups-for-03) list what this ticket takes from it.

**From 02:** [Decision 0004](../../../docs/decisions/0004-gate-checkers.md) settles 02. This ticket copies the snapshot runner and the ripsecrets wrapper (rewritten in shell), keeps editorconfig-checker, adds python, pytest and ruff to `pixi.toml`, and writes `checks.toml`. [02's hand-back notes](02-gate-checkers-decision.md#follow-ups-for-03) list what this ticket takes from it, including the cache directories to gitignore so the snapshot runner does not trip.

**MVP critical path:** yes. Every later lane builds on it.

**Status:** done. See [the hand-back notes](#hand-back-notes) and the [evidence](../evidence/03/README.md).

- [x] A Gleam application skeleton builds, with one passing gleeunit test.
- [x] The pixi manifest and lockfile follow 01 and are committed. The lock check fails on drift and never rewrites the lock.
- [x] The Justfile has setup, develop, format and check groups, and `just --list` shows them.
- [x] `just check` is read-only and runs the lock check, `gleam format --check`, `gleam build --warnings-as-errors`, `gleam test`, the TOML check and lint (typos, markdownlint, shellcheck and the others 01 settled), all through the snapshot runner from 02. A recipe that modifies any tracked or untracked-unignored file fails the gate.
- [x] `manifest.toml` drift fails the gate rather than being rewritten, as 01 decided.
- [x] There are two prek configs, read-only and fix. Every remote hook is pinned to a full commit SHA with a version comment. Every recipe inside `just check` is read-only. Outside the gate, only `just fix`, `just initialize` (03, 07) and the snapshot review and accept recipes (08) write files, and only `just fix` and the snapshot accept recipe may touch tracked files.
- [x] The dotfiles are in place: editorconfig, gitattributes and gitignore. The gitignore covers build output, the pixi environment, the tool directory and `ai_tmp/`. The ticket decides whether `.scratch/` is tracked.
- [x] `just initialize` is the one first-run command and the only step that needs network. The docs say plainly that an agent needs an explicit network grant for that first run. After it, `just check` passes offline.
- [x] Hook installation runs only from the primary checkout. In a linked worktree `just initialize` skips the hook step with a printed notice and still completes the rest (pixi environment, tool directory), so a worktree reaches a green `just check` without hooks (11).
- [x] One branch-name convention (for example `ticket/NN-slug`) is fixed and stated where lanes will read it.
- [x] An Apache-2.0 LICENSE is committed.

## Hand-back notes

Each box above is met on branch `03-foundation`:

- **Gleam skeleton:** `src/knarr.gleam`, with one gleeunit test in `test/knarr_test.gleam`.
- **pixi:** `pixi.toml` is 0003's manifest block byte for byte, plus 0004's three Python pins after `shellcheck`. `pixi.lock` is solved for both platforms, with the same linux-64 erlang build 0003 recorded. `just lock-check` is `pixi lock --check --offline --dry-run`, and the [evidence](../evidence/03/README.md) shows it failing on drift without rewriting the lock.
- **Justfile groups:** `just --list` shows setup, develop, format and check.
- **The gate:** `just check` runs `lock-check`, `env-check`, `manifest-check`, `format-check`, `build` (with `--warnings-as-errors`), `test`, `test-checkers`, `toml-check` and `lint` through the copied snapshot runner, which appends `check-clean`. `lint` runs typos, markdownlint, lychee (offline), shellcheck, editorconfig-checker, ruff, actionlint, ripsecrets and prek's builtin checks. `test-checkers` holds the snapshot-contract tests, including a writing recipe that fails the gate.
- **manifest.toml:** `manifest-check` runs before every gleam recipe and fails on drift. `build`, `test` and `initialize` also hash `manifest.toml` before and after gleam runs, and fail if it changed.
- **Hook configs:** `.pre-commit-config.yaml` is read-only and `.pre-commit-fix.yaml` repairs. Every hook is `repo: local` or `repo: builtin`, so no remote hook exists. `test_hook_configs.py` fails any future remote hook whose `rev` is not a full SHA with a version comment, and any read-only entry with a fixing flag. Only `fix` and `initialize` write files, and only `fix` edits tracked ones.
- **Dotfiles:** `.editorconfig`, `.gitattributes`, `.gitignore`. `.scratch/` stays tracked, which the gitignore and README say.
- **First run:** on a fresh clone the one command is `just initialize`, or `sh scripts/initialize.sh` without a `just`, since the script sets its own `PATH` and runs `pixi install --locked` itself. The README states that it is the only networked step and that an agent needs an explicit network grant for it. The evidence shows `just check` passing with network denied.
- **Hooks from the primary checkout only:** `scripts/install-hooks.sh` compares the git directory with the common directory.
- **Branch convention:** `NN-slug`, stated in the root README and the bootstrap README.
- **LICENSE:** the Apache-2.0 text from apache.org, byte-identical to libpawdoku's.

These depart from the ticket or the decisions:

- **The branch convention is `NN-slug`, not `ticket/NN-slug`.** The ticket gave `ticket/NN-slug` as an example. Every existing lane branch (`02-gate-checkers-decision`, `03-foundation`, `10-spike-local-cluster`) and worktree already used `NN-slug`, which is the ticket's file name without `.md`. So no branch needed renaming.
- **The manifest pre-check is Python, not taplo and an escript.** `scripts/checks/manifest_check.py` reads both files with `tomllib` and applies the escript's rule. It also refuses a `gleam.toml` that has both dev-table spellings at once, which the escript did not consider. Its pytest tests cover 0003's six cases and assert that nothing is written.
- **Every hook entry runs through `scripts/with-env.sh`.** This closes 01's unverified note that hooks run without the Justfile's `PATH`. The wrapper puts the pixi environment and `.tools/bin` first, and the evidence proves it with a commit under `PATH=/usr/bin:/bin`.
- **The installer accepts `file://` URLs**, so its tests can serve pins without network. Redirects may only go to https, and a test holds every committed `tools.txt` URL to https. A rerun skips a tool whose installed pin line is unchanged, so it does not re-hash an installed binary. A changed pin always downloads and checks again.
- **Scripts are mode 644 and run as `sh` or `python3`**, matching the evidence scripts. So the read-only config omits `check-shebang-scripts-are-executable`.
- **Two files from ticket 10 changed.** markdownlint 0.41.1, which markdownlint-cli2 0.23.3 bundles, adds MD060. MD060 rejects `|---|` delimiter rows in `docs/decisions/0007-local-cluster.md` and `evidence/10/README.md`. That README also began with a stray `|`. Both are fixed.
- **Evidence is excluded from the layout hooks.** gleam-format and editorconfig-checker skip `.scratch/bootstrap/evidence/`, and the fix config never touches it, because transcripts are recorded output. typos, markdownlint, shellcheck and ripsecrets still read it.
- **taplo's column width is 100**, so it leaves 0003's `pixi.toml` exactly as written. taplo skips gleam's `manifest.toml`.

- **The backstop hashes `manifest.toml` instead of running `git diff --exit-code`.** 0003 named `git diff --exit-code manifest.toml`. But that compares with the index, so it also failed a legitimate, still-uncommitted `gleam deps update`. A before-and-after hash catches only a rewrite by gleam.
- **`lint` skips the gleam-format and taplo hooks**, because `format-check` and `toml-check` run the same checks as their own gate recipes. The hooks still run at commit time.
- **`pixi.lock` stays diffable.** libpawdoku marked it `-diff`, which would hide the lock diff the README tells reviewers to read.
- **An uninitialized checkout is refused, not run with system tools.** `scripts/with-env.sh` and the `check` recipe exit 2 with "run just initialize" when the pixi environment is missing.

Found while gathering the evidence:

- A `[feature.*]` table that no environment uses is not drift. `pixi lock --check` passes it, because the lock still satisfies every environment. A drift test has to move a pin that an environment installs.
- markdownlint-cli2 merges the config's `globs` with the files it is given, so without `--no-globs` a hook would lint, and the fix hook would rewrite, the whole repository, whatever prek excludes. Both hooks pass `--no-globs`.
- `gleam deps download` writes nothing tracked when the manifest agrees, so `initialize` can end with `git diff --exit-code manifest.toml`.

Not verified:

- Nothing ran on linux-64. 05's first CI run is the first native linux-64 gate.
- The first-run time (8 s) used warm pixi and Gleam caches. 11 records a cold one.
- Hooks were installed only in a throwaway clone. The maintainer's primary checkout was not touched.

Adversarial review findings applied:

- **The gate passed on a stale installation.** `lock-check` compares `pixi.lock` with `pixi.toml` only, so after a pull that moved a pin every recipe ran the old binaries and the gate could still pass. `env-check` (`scripts/checks/env_check.py`) now runs second in the gate. It compares the packages `pixi.lock` pins for the default environment, on the platform recorded in `conda-meta/pixi`, with the environment's `conda-meta/` records. It also compares each of that platform's `tools.txt` lines with the pin `install-tools.sh` recorded in `.tools/bin/.pins/`. On any difference it fails and says to rerun `just initialize`. It never runs pixi and never writes. No YAML parser is pinned, so it reads `pixi.lock` line by line, accepts only lock version 7 and `- conda:` entries, and refuses anything else with status 2.
- **A checkout path with a space failed `test-checkers`.** The snapshot tests' generated Justfile named the interpreter and the runner by unquoted absolute paths, both inside the checkout. They are now shell-quoted, and a test runs the gate with the runner under a directory whose name has a space.

Code review findings declined:

- **`manifest-check` runs three times per gate**, once as its own recipe and once as a dependency of `build` and of `test`. That repeat is kept: the check is cheap, and it guards `just build` and `just test` run on their own.
- **`check-clean` repeats the runner's last comparison.** That is kept, because 0004 keeps upstream's runner and its `check-clean` step as they are.

### For other lanes

- **05:** call `just check`, or the check-group recipes one per job. The setup is `pixi install --locked`, then `just initialize`. In CI's checkout, initialize also installs the pre-commit hook, which is harmless there. `env-check` reads `.pixi/envs/default/conda-meta/pixi` and `.tools/bin/.pins/`, which `pixi install` and `just initialize` write; a setup action that caches or relocates the environment must keep both. actionlint is already a hook, and it starts checking once `.github/workflows/` exists.
- **06, 07, 09:** add your table to `checks.toml`, your checker to `scripts/checks/` with tests in `scripts/checks/tests/`, and your recipe name to the `check` recipe's list in the Justfile. `_project.table()` and `_project.predicates()` are tested and fail closed. lychee already runs offline as a hook. 06 may move it into its own recipe.
- **07:** add the two allium lines to `tools.txt`. The installer matches the archive member by basename.
- **08:** add the snapshot review and accept recipes outside the check group. Keep any snapshot output a test run may leave behind gitignored, or the gate trips.
- **11:** rerun [fresh-clone.sh](../evidence/03/fresh-clone.sh) on a cold machine for the timings.
