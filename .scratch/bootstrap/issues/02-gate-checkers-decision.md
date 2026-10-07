# 02: Gate checkers decision: copy, rewrite or drop each biscuit_games_tooling checker

**Context:** libpawdoku's gate leaned on the Python checkers in `biscuit_games_tooling`. knarr does not depend on that package; anything it wants from it is copied in. The checkers are:

- the worktree-snapshot gate runner, which hashes every tracked and untracked-unignored path after each recipe and aborts on any change
- `validate_docs`
- `validate_agents`, which hard-codes a required-phrase list that includes the game-only word `runes`
- the Allium installer and runner, which pins the binary by checksum and reads JSON diagnostics because the exit code cannot be trusted
- the ripsecrets wrapper

**What to build:** A decision record with one row per checker: copy it (vendored with provenance), rewrite it (and in what language and runtime), or drop it (and what replaces it, if anything). The read-only gate keeps its main guarantee: no gate recipe may modify the worktree.

**Non-goals:** Wiring the checkers into the gate. That is done by the lane that owns each one: the runner and the ripsecrets wrapper in 03, docs in 06, Allium in 07, agents in 09.

**Blocked by:** 01

**From 01:** [Decision 0003](../../../docs/decisions/0003-tool-manager.md) settles 01. Read [01's hand-back notes](01-tool-manager-decision.md#follow-ups-for-02) first: they fix where a checker's runtime comes from, rule out remote hooks for tools pixi already provides, and name the source of ripsecrets and editorconfig-checker.

**MVP critical path:** yes. It gates the foundation (03).

**Status:** done. See [Decision 0004](../../../docs/decisions/0004-gate-checkers.md) and its [evidence](../evidence/02/README.md).

- [x] Every checker listed above has a decision and a reason.
- [x] Every copied file has provenance recorded: source repository, commit and original path. Its licence is confirmed compatible with Apache-2.0.
- [x] The runtime for kept or rewritten checkers (for example Python from the pixi environment) is owned by the manifest decided in 01, not by a second installer.
- [x] The agents checker's required phrases come from project configuration. `runes` and other game-only wording are gone.
- [x] The snapshot guarantee is kept as is or replaced by an equivalent, and the record says which.
- [x] A decision record is written. Follow-ups for 03 (runner and ripsecrets), 06, 07 and 09 name which checker each lane brings in.

## Hand-back notes

Each box above is met in [Decision 0004](../../../docs/decisions/0004-gate-checkers.md):

- **A decision and a reason for every checker:** "One row per checker". It also decides editorconfig-checker, which 0003 deferred here.
- **Provenance and licence:** "Provenance and licence", backed by [provenance.txt](../evidence/02/provenance.txt).
- **Runtime owned by 0003's manifest:** "The Python stack" adds python, pytest and ruff to `pixi.toml`'s default feature. "Allium: the installer is dropped" puts allium in `tools.txt`. No second installer remains.
- **Phrases from configuration, `runes` gone:** "`checks.toml`" moves the phrases, adapters and bridges into `[agents]`, and validate_agents refuses an empty phrase list.
- **The snapshot guarantee:** "The snapshot guarantee is kept as is" spells out the contract 03 must show it kept.
- **Follow-ups:** below.

These are corrections to the premise above, found while gathering the evidence on 2026-10-07:

- editorconfig-checker was not on the list, but 0003 left it to this ticket. It is kept.
- Upstream has no `LICENSE` file and no licence field. The copyright holder (knarr's maintainer) grants the copied files to knarr under Apache-2.0, and 0004 records that grant.
- The Allium installer is dropped, not copied. 07's first checkbox assumed an installer of its own. 0003's `tools.txt` recipe is that installer.
- The ripsecrets wrapper's refusal now exits 2, not 1, so it cannot be mistaken for a finding.
- Running Python in the worktree writes cache directories that would trip the snapshot runner unless they are gitignored.

### Follow-ups for 03

- Add `python = "==3.14.8"`, `pytest = "==9.1.1"` and `ruff = "==0.16.10"` to `pixi.toml`'s default feature, after `shellcheck`, and commit the re-solved `pixi.lock`.
- Copy `run_project_check.py` and a reduced `_project.py` into `scripts/checks/`, with the provenance header and SPDX line. `_project.py` holds `root()`, the `checks.toml` loader (which fails closed) and `predicates()` rewritten to read `[docs]`. Test the loader's two refusals and `predicates()`'s rule that only boolean `true` enables a predicate, so 06, 07 and 09 build on a proven loader. The `check` recipe runs `python3 scripts/checks/run_project_check.py run <recipe>...`, and the runner appends `check-clean`. `run` with no recipes refuses. The `check-clean` recipe takes an optional `baseline` parameter and passes it to `run_project_check.py clean`, because the runner calls it with the baseline file. Show each point of 0004's snapshot contract in a pytest test, including a failing fixture: a recipe that writes a file must fail the gate.
- Write `checks.toml` with the comment header from 0004. Each later lane adds its own table.
- Copy [ripsecrets-redacted.sh](../evidence/02/ripsecrets-redacted.sh) to `scripts/checks/`, with its cases from [ripsecrets.sh](../evidence/02/ripsecrets.sh) as the test. Run it as a `repo: local`, `language: system` hook: `sh scripts/checks/ripsecrets-redacted.sh`, with filenames passed.
- Add both platforms' ripsecrets and editorconfig-checker lines to `tools.txt`, from [01's tools.txt](../evidence/01/tools.txt). The ripsecrets archive nests its binary under `ripsecrets-0.1.11-<target>/`. The editorconfig-checker archive has its own layout. allium's sits at the archive root. So the installer matches a member by its basename. Run editorconfig-checker as a hook or a recipe inside `just check`.
- Gitignore `__pycache__/`, `.pytest_cache/` and `.ruff_cache/`, and export `PYTHONDONTWRITEBYTECODE=1` from the Justfile.
- Put ruff's configuration in `ruff.toml`, starting from upstream's rule selection. Pick pytest's configuration file. knarr has no `pyproject.toml`.
- Configure typos to skip the evidence transcripts, which carry hashes, as upstream skipped `uv.lock`.

### Follow-ups for 06

- Copy `validate_docs.py` into `scripts/checks/`. It reads `[docs] predicates` through `_project.predicates()`, which 03 provides. Add the `[docs]` table (`predicates = {}`). Any exception the HTML explainer needs is 06's to add. Prove it with a pytest test, including a failing fixture.
- Register 0004 in the decision-record index as the gate-checker decision (02).

### Follow-ups for 07

- 07 writes no installer. Add the two allium lines from 0004 to `tools.txt`, and 0003's recipe installs them. If 07 moves the version, it rehashes both assets.
- Copy `run_allium.py` into `scripts/checks/`. Read the specs path from `[allium] specs`. Replace the `install_allium` import with a version check that reads the host platform's `allium` line in `tools.txt` and compares it with `.tools/bin/allium --version`. Keep every JSON check. Prove it with a pytest test, including a failing fixture.
- Add the `[allium]` table, and tell 09 the specs directory for its phrase list.

### Follow-ups for 09

- Copy `validate_agents.py` into `scripts/checks/`. Read `required_guidance`, `adapters`, `bridges` and `tolerated` from `[agents]`. Derive the bridge body's relative path from each bridge directory's depth. Derive each managed directory from the first path component of a bridge directory (`.claude/skills` manages `.claude/`). Refuse an empty `required_guidance`. Drop the `CODEX.md` check. List committed provider files such as `.claude/settings.json` in `tolerated`. Prove it with a pytest test, including a failing fixture.
- Fix the phrase list in `[agents] required_guidance`, starting from 0004's proposal. Fix the adapters (Claude, Copilot) and the bridge directories. Where Copilot's skill bridges live, if anywhere, is 09's call.
