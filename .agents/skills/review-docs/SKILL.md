---
name: review-docs
description: Add or revise a handbook page so it satisfies the documentation contract and stays reachable.
---

# Add or revise a documentation page

1. Read `AGENTS.md` and `docs/reference/documentation-contract.md`. The contract is enforced by `scripts/checks/validate_docs.py`, which `just docs-check` runs and which reports every violation at once.
2. Find the topic's owner first. Every topic in `docs/manifest.yml` has exactly one canonical page, so prefer editing the owning page over writing a new one.
3. A new page needs a `docs/manifest.yml` entry whose `title`, `kind`, `audience`, `canonical_for` and `requires` match the page frontmatter exactly, including list order. The comparison is order-sensitive. `requires` names feature predicates from `checks.toml`, not related pages; knarr declares none, so it is empty.
4. Give the page one level-one heading identical to its `title`, at least forty words of substance, and no unfinished markers, template syntax or placeholder prose.
5. Link the page in from `docs/README.md`, directly or transitively. An unreachable page fails the contract even when everything else about it is correct. An HTML page uses manifest metadata alone and joins reachability through its anchors.
6. Use relative links and check the case; the contract verifies link targets exist with exact case, and heading anchors within Markdown targets. Allium modules and bootstrap evidence are not handbook pages and never enter the manifest.
7. Run `just docs-check`, then `just lint` for markdownlint, typos and offline lychee, then `just check` before handing back.
