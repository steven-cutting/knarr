# 06: Docs contract and decision records

**Context:** This adapts libpawdoku's T07, T08 and T09. The repository already holds OVERVIEW, DEFERRED and the HTML explainer. Decisions 01 and 02 will each have produced a record, and the spikes later add more.

**What to build:** Documentation laid out by Diátaxis, with a manifest that registers every page with its kind and audience, and the docs validator chosen in 02 running in `just check`. A decision-record index holds the decisions carried into this repository.

**Non-goals:** Maintainer docs: README, CHANGELOG, SECURITY and CONTRIBUTING (12). The testing reference page (08). Rewriting OVERVIEW's content.

**Blocked by:** 03

**From 02:** [Decision 0004](../../../docs/decisions/0004-gate-checkers.md) settles 02. This ticket copies `validate_docs.py` into `scripts/checks/`, with its predicates in `checks.toml` `[docs]`. See [02's hand-back notes](02-gate-checkers-decision.md#follow-ups-for-06).

**MVP critical path:** yes. It gates the testing toolkit (08) and the agent contract (09).

**Status:** done. The [documentation index](../../../docs/README.md) and [contract](../../../docs/reference/documentation-contract.md) are the entry points.

- [x] There are sections for tutorials, how-to, explanation, reference, project, and decisions, each with at least a stub page the validator accepts.
- [x] The manifest registers every page. OVERVIEW, DEFERRED and the explainer are registered where they are, or moved with every inbound link updated. The explainer gets whatever exception an HTML page needs.
- [x] The docs validator (copied or rewritten per 02) runs in `just check`, as do markdownlint, typos and lychee (offline in the gate, external links in the audit workflow).
- [x] A decision-record index lists, in this order, records for:
  - specs decide behaviour
  - effects live behind sans-IO boundaries
  - the tool-manager decision (01)
  - the gate-checker decision (02)
  - a project-managed Allium binary (carried from libpawdoku; 07 implements it in parallel and amends this record if its findings differ)
  - Apache-2.0
- [x] Each carried record names where it was adapted from, when it was.
- [x] `just check` is green and the worktree is clean.

## Hand-back notes

Implemented on 2026-10-07. The manifest registers 17 pages across tutorials, how-to, explanation, reference, project, and decisions. OVERVIEW and DEFERRED received frontmatter only; their bodies and paths are unchanged. The HTML explainer is unchanged and uses manifest-only metadata. HTML remains subject to registration, topic ownership, predicates, and reachability; offline lychee checks its links and fragments.

`validate_docs.py` is copied from biscuit_games_tooling `v0.3.0`, commit `6c5c07f6bec86e86b3930dfa41392e4b440e8c85`, with the provenance and SPDX header required by decision 0004. It imports the existing `_project` loader and reads `[docs] predicates = {}`. The other adaptation adds HTML discovery and anchor-link navigation. Decision 0007's `requires` is now empty: its tool-manager dependency remains a prose link, because `requires` names feature predicates rather than decisions.

The decision index lists 0001–0006 in the requested order, then retains 0007. Each carried record cites its libpawdoku source and adaptation date. Decision 0005 reflects the `tools.txt` installer and explicitly leaves Allium gate implementation to 07.

### Verification

- The validator CLI is tested through temporary Git repositories, including failing fixtures. All 31 cases pass and assert that validation never writes files.
- `just docs-check` validates 17 pages and 18 canonical topics.
- `just check` covers the Gleam build/tests, checker suite, docs validator, TOML checks, and every read-only hook, including Markdown/HTML offline lychee and workflow actionlint.
- `just links-audit` passed 296 link checks with zero errors on 2026-10-07, with network access. This is separate from the offline gate.
- Taplo's sandboxed invocation failed in macOS system configuration; the same read-only TOML checks passed outside the sandbox.
- The requested `code-review` skill was unavailable. A direct review checked the upstream-copy diff, documentation metadata, workflow permissions/pins, scope, and whitespace. GitHub-hosted execution is not claimed here.

### Follow-ups for 05

The [audit workflow](../../../.github/workflows/audit.yml) already runs `just links-audit` weekly on Mondays at 06:00 UTC and on manual dispatch. It installs the locked default environment through pinned setup-pixi, activates that environment for `just`, and grants only `contents: read` to its job. When 05 introduces the shared setup action, reuse it here without introducing an online check into the required gate. Retain the audit's separate, non-required role.

### Follow-ups for 07, 08, and 09

- 07 owns implementing and, if necessary, amending [Decision 0005](../../../docs/decisions/0005-project-managed-allium-cli.md). Allium files are not handbook pages and do not go in the docs manifest. Any accompanying Markdown page does.
- 08 owns the testing reference page. Register it and link it from the documentation index or another reachable page; this ticket does not pre-write it.
- 09 owns the agent contract and related guidance. Every new Markdown or HTML page under `docs/` needs a manifest entry and navigation link. The [documentation contract](../../../docs/reference/documentation-contract.md) defines the fields and allowed values.
