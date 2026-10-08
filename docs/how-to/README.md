---
title: "How to change the documentation"
kind: "how-to"
audience: ["contributor", "maintainer", "agent"]
canonical_for: ["change_documentation"]
requires: []
---

# How to change the documentation

Choose the section that matches the reader's task: tutorials teach through an exercise, how-to guides solve a concrete problem, explanation develops understanding, and reference states precise facts. Project pages record direction; decisions record accepted choices and their reasons.

1. Create a Markdown page with matching frontmatter and a first level-one heading. Write at least forty words of useful body content.
2. Register its path and metadata in `docs/manifest.yml`, relative to `docs/`. Give it a canonical topic that no other page owns.
3. Link it from a reachable section page so readers can navigate to it from the [documentation index](../README.md).
4. Run `just docs-check` and `just lint`. Run `just check` before committing.

When moving a page, update its manifest path and every inbound link. Keep requirements empty unless a declared, enabled feature predicate actually gates the page. See the [contract](../reference/documentation-contract.md) for exact fields and the HTML exception.
