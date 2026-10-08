---
title: "Decision 0001: Specifications decide behaviour"
kind: "decision"
audience: ["contributor", "maintainer", "agent"]
canonical_for: ["decision_spec_first"]
requires: []
---

# Decision 0001: Specifications decide behaviour

Adapted on 2026-10-07 from libpawdoku’s [0002-specs-are-the-source-of-truth.md](https://github.com/steven-cutting/libpawdoku/blob/51d8b55ac4f769a6a4d66abacb9642a7d4062127/docs/decisions/0002-specs-are-the-source-of-truth.md) at commit `51d8b55ac4f769a6a4d66abacb9642a7d4062127`. The source record remains in its original repository.

## Decision

Behavioural specifications decide what Knarr does. The agent contract governs how contributors and agents build it. A behaviour change starts in the specification, continues in tests, and then reaches implementation; code must not quietly invent a different guard, threshold, or policy. Open product questions remain explicit until the responsible decision-maker answers them.

The [overview](../OVERVIEW.md) is direction for drafting those specifications, not an alternative source of settled behaviour. Specification authoring and the Allium gate are later bootstrap work. This record does not claim that the controller's contracts are already complete.

## Consequences

A passing parser cannot prove implementation agreement. Tests and review must trace behaviour back to its specification, and tests must not be weakened merely to accommodate an implementation. When a contract is wrong, correct it explicitly and derive the tests again. The cost is keeping specification and implementation changes together; the benefit is one place to resolve behavioural disagreements.

The [project-managed Allium decision](0005-project-managed-allium-cli.md) establishes the tool that checks specification syntax and analysis. Effects follow the separate [sans-IO decision](0002-sans-io-boundaries.md).
