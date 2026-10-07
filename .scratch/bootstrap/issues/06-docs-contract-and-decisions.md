# 06: Docs contract and decision records

**Context:** This adapts libpawdoku's T07, T08 and T09. The repository already holds OVERVIEW, DEFERRED and the HTML explainer. Decisions 01 and 02 will each have produced a record, and the spikes later add more.

**What to build:** Documentation laid out by Diátaxis, with a manifest that registers every page with its kind and audience, and the docs validator chosen in 02 running in `just check`. A decision-record index holds the decisions carried into this repository.

**Non-goals:** Maintainer docs: README, CHANGELOG, SECURITY and CONTRIBUTING (12). The testing reference page (08). Rewriting OVERVIEW's content.

**Blocked by:** 03

**MVP critical path:** yes. It gates the testing toolkit (08) and the agent contract (09).

**Status:** ready-for-agent

- [ ] There are sections for tutorials, how-to, explanation, reference, project, and decisions, each with at least a stub page the validator accepts.
- [ ] The manifest registers every page. OVERVIEW, DEFERRED and the explainer are registered where they are, or moved with every inbound link updated. The explainer gets whatever exception an HTML page needs.
- [ ] The docs validator (copied or rewritten per 02) runs in `just check`, as do markdownlint, typos and lychee (offline in the gate, external links in the audit workflow).
- [ ] A decision-record index lists, in this order, records for:
  - specs decide behaviour
  - effects live behind sans-IO boundaries
  - the tool-manager decision (01)
  - the gate-checker decision (02)
  - a project-managed Allium binary
  - Apache-2.0
- [ ] Each carried record names where it was adapted from, when it was.
- [ ] `just check` is green and the worktree is clean.
