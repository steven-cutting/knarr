# 03: Foundation: a green `just check` from a fresh clone

**Context:** This adapts libpawdoku's T00 (foundation) and T03 (hooks and dotfiles), with the tool manager from 01 and the checker decisions from 02. libpawdoku taught three lessons that apply here. Fix one branch-name convention before lanes fork. State the first-run network requirement plainly. Install hooks only from the primary checkout, because linked worktrees share `.git/hooks`.

**What to build:** A contributor or agent clones the repository, runs `just initialize` once (with network), then runs `just check` and gets green, offline, with the worktree unchanged. The foundation stays small. Each later lane brings its own validator into the gate.

**Non-goals:** CI (05). The docs layout and docs validator (06). Allium (07). Test libraries beyond gleeunit (08). Real `AGENTS.md` content (09). Any controller behaviour.

**Blocked by:** 01, 02

**From 01:** [Decision 0003](../../../docs/decisions/0003-tool-manager.md) settles 01. It gives the exact `pixi.toml`, the rebar3 pin and the lock-check command. [01's hand-back notes](01-tool-manager-decision.md#follow-ups-for-03) list what this ticket takes from it.

**From 02:** [Decision 0004](../../../docs/decisions/0004-gate-checkers.md) settles 02. This ticket copies the snapshot runner and the ripsecrets wrapper (rewritten in shell), keeps editorconfig-checker, adds python, pytest and ruff to `pixi.toml`, and writes `checks.toml`. [02's hand-back notes](02-gate-checkers-decision.md#follow-ups-for-03) list what this ticket takes from it, including the cache directories to gitignore so the snapshot runner does not trip.

**MVP critical path:** yes. Every later lane builds on it.

**Status:** ready-for-agent

- [ ] A Gleam application skeleton builds, with one passing gleeunit test.
- [ ] The pixi manifest and lockfile follow 01 and are committed. The lock check fails on drift and never rewrites the lock.
- [ ] The Justfile has setup, develop, format and check groups, and `just --list` shows them.
- [ ] `just check` is read-only and runs the lock check, `gleam format --check`, `gleam build --warnings-as-errors`, `gleam test`, the TOML check and lint (typos, markdownlint, shellcheck and the others 01 settled), all through the snapshot runner from 02. A recipe that modifies any tracked or untracked-unignored file fails the gate.
- [ ] `manifest.toml` drift fails the gate rather than being rewritten, as 01 decided.
- [ ] There are two prek configs, read-only and fix. Every remote hook is pinned to a full commit SHA with a version comment. Every recipe inside `just check` is read-only. Outside the gate, only `just fix`, `just initialize` (03, 07) and the snapshot review and accept recipes (08) write files, and only `just fix` and the snapshot accept recipe may touch tracked files.
- [ ] The dotfiles are in place: editorconfig, gitattributes and gitignore. The gitignore covers build output, the pixi environment, the tool directory and `ai_tmp/`. The ticket decides whether `.scratch/` is tracked.
- [ ] `just initialize` is the one first-run command and the only step that needs network. The docs say plainly that an agent needs an explicit network grant for that first run. After it, `just check` passes offline.
- [ ] Hook installation runs only from the primary checkout. In a linked worktree `just initialize` skips the hook step with a printed notice and still completes the rest (pixi environment, tool directory), so a worktree reaches a green `just check` without hooks (11).
- [ ] One branch-name convention (for example `ticket/NN-slug`) is fixed and stated where lanes will read it.
- [ ] An Apache-2.0 LICENSE is committed.
