---
title: "Decision 0002: Effects live behind sans-IO boundaries"
kind: "decision"
audience: ["contributor", "maintainer", "agent"]
canonical_for: ["decision_sans_io"]
requires: []
---

# Decision 0002: Effects live behind sans-IO boundaries

Adapted on 2026-10-07 from libpawdoku’s [0003-effects-behind-traits.md](https://github.com/steven-cutting/libpawdoku/blob/51d8b55ac4f769a6a4d66abacb9642a7d4062127/docs/decisions/0003-effects-behind-traits.md) at commit `51d8b55ac4f769a6a4d66abacb9642a7d4062127`. The source record remains in its original repository.

## Decision

Knarr's decision logic consumes ordinary values and produces decisions without performing I/O. HTTP requests, Kubernetes reads and writes, clocks, process scheduling, and other effects live in adapters around that logic. Tests supply observations and time explicitly, and inspect the resulting decisions without requiring a live cluster.

This adapts the source record's effect isolation to Gleam and the BEAM. It does not carry over Rust traits, a no-std core, randomness APIs, or compiler-enforced guarantees from a different project. The [overview](../OVERVIEW.md) supplies the proposed controller context; later implementation tickets choose the concrete adapter interfaces.

## Consequences

Policy can be exercised deterministically with small values, including stale or failed worker observations. Adapter tests still have to prove HTTP and Kubernetes behaviour; pure tests cannot establish those guarantees. Effects must not leak back into the decision logic through hidden global reads. Review enforces this architectural boundary until more specific checks exist.

The [local cluster and test-tier decision](0007-local-cluster.md) assigns the real and simulated environments for testing adapters. [Specifications decide behaviour](0001-specs-decide-behaviour.md); sans-IO boundaries make those obligations easier to test without choosing new product policy here.
