---
name: gleam-change
description: Implement or review a change to the controller with the sans-IO boundary, confined FFI, supervision, tests and documentation the invariants require.
---

# Change the controller

1. Read `AGENTS.md` and `docs/decisions/0002-sans-io-boundaries.md`. Identify which module under `src/` the change lands in and whether it changes what the controller writes to the cluster; an annotation, a label or a patch shape is part of the worker contract and so part of the change.
2. Find the clause. Every behaviour has an owning module under `docs/specs/`; read the rule, its guards and its outcomes before writing code. If no clause says what you need, this is a `spec-change` first, not a judgement call in code.
3. Put every effect behind the sans-IO boundary. Decision logic takes observations, a clock value and configuration as plain values and returns the decision; HTTP polls, Kubernetes reads and patches, timers and scheduling live in adapters that call pure builders and decoders and send through an injected function. A change that wants to read the clock, the network or the environment inside the decision logic has found a design problem, not a missing import.
4. Keep Erlang calls in a named `*_ffi.erl` module beside the Gleam module that owns them, and nothing else may `@external`. Every process starts under a supervisor; a bare spawned process is a finding.
5. Derive the test from the clause before implementing, and confirm it fails first. A test under `test/` drives the decision logic with values and asserts the decision; an adapter test proves the HTTP or Kubernetes behaviour against a fake or the local cluster tier the test-tier decision assigns. A test already green proves nothing about the new behaviour.
6. The controller writes only the annotations it owns on live Pod objects. It never changes replica counts, never touches a Deployment's pod template, and stops patching a pod once `deletionTimestamp` is set. A change that would do any of these is a specification question, not a code change.
7. Run `just format-check`, `just build` and `just test`, then `just check` before handing back. Warnings are errors in `build` and in the gate alike, and `build` and `test` refuse a drifted `manifest.toml`; `gleam deps download` and a reviewed diff fix that, never a hand edit.
8. Report by `file:line`: what changed, which clause it implements, and which test proves it.
