---
title: "Agent contract"
kind: "reference"
audience: ["contributor", "maintainer", "agent"]
canonical_for: ["agent_contract"]
requires: []
---

# Agent contract

`just agents-check` runs the copied agents validator, `scripts/checks/validate_agents.py`, and `just check` includes it under the worktree snapshot guarantee. [`AGENTS.md`](../../AGENTS.md) is the single source of truth for how an agent works in this repository; everything else in the agent surface exists only so a particular tool can find it. The source of the validator and its permitted adaptations are recorded in [Decision 0004](../decisions/0004-gate-checkers.md). Its settings live in the `[agents]` table of `checks.toml`.

## The surfaces

| Path | Role |
| --- | --- |
| `AGENTS.md` | Canonical. Read natively by Copilot's coding agent and by anything following the convention. |
| `CLAUDE.md` | An adapter, byte-pinned to `@AGENTS.md` and nothing else. |
| `.github/copilot-instructions.md` | An adapter, byte-pinned to one paragraph. |
| `.agents/skills/<name>/` | Canonical task procedures: seven house skills and seven vendored Allium skills. |
| `.claude/skills/<name>/SKILL.md` | A bridge per skill for Claude Code, which loads project skills from that directory only. |
| `skills-lock.json` | The provenance and sha256 of every vendored file. |

Copilot gets no bridge directory: GitHub's agent-skills documentation lists `.agents/skills/` as a project skill directory, so Copilot reads the canonical skills where they are. A copy under `.github/skills/` would be a third duplicate and would make `.github/`, where the workflows live, a managed directory.

The adapter contents are the `[agents.adapters]` values in `checks.toml`, compared byte for byte. A forgiving comparison would enforce something weaker than the word "pinned".

## What AGENTS.md must contain

- At least 300 words.
- Every phrase in `[agents] required_guidance`, matched case-insensitively as a substring. Each names an invariant that is expensive to rediscover: how untrusted input is treated, the one command that proves a change, where authority stops, where scratch work goes, the sans-IO boundary, confined FFI, supervision, what the controller may and may not write, the worktree rule, and where the specifications live.

The phrase list is a crude check and is meant to be. It does not verify that the guidance is good; it verifies that no topic was dropped in an edit. Adding an invariant means adding its phrase to `checks.toml` in the same change.

## House skills

A house skill is a directory under `.agents/skills/` holding exactly one file, `SKILL.md`, with frontmatter of exactly two keys:

- `name` equals the directory name.
- `description` is at least eight words and states a real trigger.
- The body cites `AGENTS.md` and names at least one `just` recipe. A procedure that ends without saying how to verify it is not a procedure.

The frontmatter parser is deliberately literal. It splits every line between the `---` markers on the first colon, treats a line without one as an error, and treats a repeated key as an error rather than an overwrite. Keep the keys adjacent with nothing between them. The same parser reads the bridges. No house file may contain unresolved template syntax.

The seven house skills are `project-check`, `fix-quality`, `plan-change`, `review-change`, `review-docs`, `spec-change` and `gleam-change`.

## Vendored skills and the lock

A vendored skill is one named in `skills-lock.json`. The seven are `allium`, `distill`, `elicit`, `propagate`, `tend`, `weed` and `witness`, copied byte for byte from [juxt/allium](https://github.com/juxt/allium) at the tag the lock's `source` names, each directory in its upstream layout (`SKILL.md` and `references/`) plus a copy of the upstream `LICENSE`. The lock records, per skill, the upstream path and the sha256 of every file relative to the skill directory.

The validator checks the lock in both directions. Every listed file must exist as a regular file with the recorded digest, and every file under a vendored directory must be listed. A lock entry naming a directory that does not exist, a malformed digest, a path with parent traversal, a duplicate key, or an entry without `SKILL.md` fails the gate, as does a missing or unreadable lock. The lock's `source` must name the repository, tag and a 40-digit commit.

Vendored skills are exempt from the house body rule and the two-key rule, because upstream frontmatter carries its own keys and upstream bodies do not cite `AGENTS.md`. They still need `name` equal to the directory and a nonempty description. How each one fits this project's loop is stated in `AGENTS.md`, never by editing upstream bytes.

To move the pin, clone upstream at the new tag into `ai_tmp/`, replace the seven directories, copy `LICENSE` into each, and regenerate the lock from the validator's read-only `lock` mode:

```sh
python3 scripts/checks/validate_agents.py lock allium distill elicit propagate tend weed witness >| ai_tmp/skills-lock.json
```

Then edit `source` in the printed file to the new tag and commit, and move it over `skills-lock.json`. Print into `ai_tmp/` rather than over the lock: a shell redirect truncates the target before the command reads it, and lock mode copies `source` from the existing lock. Without one it prints placeholders whose commit is not hex, which the gate refuses until the provenance is written.

The vendored directories are skipped by markdownlint, typos and editorconfig-checker, excluded from the whole fix config so `just fix` never rewrites them, and marked `linguist-vendored` in `.gitattributes`. Offline lychee still resolves every link inside them. A finding in a house file is never hidden by widening these exclusions.

## Bridges

Each `.claude/skills/<name>/SKILL.md` carries the canonical skill's `name` and `description` lines verbatim, quotes included, and nothing else from its frontmatter, then exactly one sentence:

```markdown
Follow `../../../.agents/skills/<name>/SKILL.md`. That file is canonical and this bridge adds nothing to it.
```

The number of `../` segments is derived from the bridge directory's depth in `[agents.bridges]`. The body is compared against the template rather than measured against a word budget: a bridge that grows an instruction of its own is a second source of truth for the skill it points at, and fails whether or not it is short.

## The inventory

The validator lists managed files from Git, honouring only this repository's `.gitignore`, and compares that against what it expects. Managed directories are `.agents/` and the first component of every bridge directory, so `.claude/skills` manages all of `.claude/`.

- Every expected file must exist: `AGENTS.md`, each adapter, each `SKILL.md`, each bridge, and each lock-listed file.
- No other file may exist in a managed directory unless `[agents] tolerated` lists it. Knarr tolerates nothing: no plugin is enabled, so there is no committed `.claude/settings.json`.
- Managed files must be regular UTF-8 files, never symlinks.

Local assistant state stays out of the inventory by being listed in `.gitignore`, as `.claude/settings.local.json` is. The check reads Git rather than walking the filesystem, so an ignored file is invisible to it, while an untracked file a reviewer would receive still counts.

On this tree `just agents-check` prints `Validated AGENTS.md, 2 adapters, 7 house skills, 7 vendored skills and 14 bridges.`

## Related pages

- [Documentation contract](documentation-contract.md)
- [Decision 0004: Gate checkers](../decisions/0004-gate-checkers.md)
- [Decision 0002: Effects live behind sans-IO boundaries](../decisions/0002-sans-io-boundaries.md)
