---
title: "Documentation contract"
kind: "reference"
audience: ["contributor", "maintainer", "agent"]
canonical_for: ["documentation_contract"]
requires: []
---

# Documentation contract

`just docs-check` runs the copied documentation validator. `just check` includes it under the worktree snapshot guarantee: a check may report problems but may not change tracked or untracked, unignored files. The source and permitted adaptations are recorded in [Decision 0004](../decisions/0004-gate-checkers.md).

## Manifest and metadata

`docs/manifest.yml` is JSON-compatible YAML with `schema_version` set to `1` and a `pages` array. Every Markdown or HTML page under `docs/` appears exactly once. Paths are relative to that directory. Specification files, images, root maintainer documents, and bootstrap evidence are not handbook pages.

Every entry has exactly these six fields:

| Field | Contract |
| --- | --- |
| `path` | A relative page path without parent traversal; the file must exist. |
| `title` | The page's title. |
| `kind` | One of `project`, `tutorial`, `how-to`, `explanation`, `reference`, `operations`, or `decision`. |
| `audience` | A nonempty list drawn from `user`, `contributor`, `maintainer`, `operator`, and `agent`. |
| `canonical_for` | A nonempty list of topics owned exclusively by this page. |
| `requires` | A list of enabled feature predicates declared in `[docs] predicates` in `checks.toml`. |

Markdown frontmatter repeats exactly the five fields other than `path`, using scalar strings and inline lists. Duplicate keys are errors. Its first heading is level one and matches the title. Body content contains at least forty words and no unfinished annotations, template syntax, or placeholder prose. An introductory page explains current scope and future ownership instead of pretending an unimplemented feature exists.

`requires` is not a list of related pages or decision dependencies. Those are ordinary prose links. Knarr currently declares no feature predicates, so every page uses an empty list. Only the TOML boolean `true` enables a predicate.

## Navigation and HTML

Every page must be reachable through links from [the documentation index](../README.md). Markdown links and HTML anchor links participate in this graph. Local targets must exist with the correct case and stay inside the repository. Markdown heading fragments are checked by the validator. Pages must be regular files, not symlinks.

HTML pages use manifest metadata alone. They do not need Markdown frontmatter, Markdown headings, or a Markdown word count. They still require registration, unique canonical topics, valid predicates, and reachability. This exception lets the [overview explainer](../overview-explainer.html) remain a standalone HTML document. Lychee checks HTML links, resources, and fragments.

## Gate and audit

`just lint` runs markdownlint, typos, and offline lychee through local hooks. Lychee covers Markdown and HTML, including local fragments. The gate never fetches external links. `just links-audit` checks links online over the repository's Markdown and HTML files, including bootstrap documentation; generated tool and build directories are outside its inputs.

The separate audit workflow runs weekly and on manual dispatch, with no required status-check role. External failures belong there because remote availability can change independently of a commit. Fix a reported link at its source; do not add broad exclusions simply to make a check green.
