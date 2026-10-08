---
name: spec-change
description: Change an Allium specification and carry the change through the tests and the implementation.
---

# Change a specification

The specifications under `docs/specs/` decide behaviour. Code that disagrees with one is wrong until the specification is changed to say otherwise, so the specification moves first and the implementation follows.

1. Read `AGENTS.md` and `docs/decisions/0001-specs-decide-behaviour.md`. Identify which module under `docs/specs/` owns the behaviour; each module's header states its scope. `docs/OVERVIEW.md` is direction and its open questions stay open until the owning ticket settles them.
2. Read the whole module before editing, including its `open question` blocks. A change that belongs in another module's scope goes there instead. The vendored `tend` skill is the editing procedure and `allium` is the language reference.
3. Edit the specification: state the rule as a trigger, its guards and its outcomes. Record what you could not decide as a new `open question` rather than guessing at a product decision.
4. Check that dependent modules still hold. A module others import is depended on by each of them, so a change to a trigger or an entity ripples.
5. Derive the tests from the changed clauses before writing implementation, and confirm they fail first. The vendored `propagate` skill derives them; `just plan-spec docs/specs/<module>.allium` prints the obligation count to record in the hand-back notes.
6. Implement until the tests pass. Never weaken a test to make it pass; fix the specification and re-derive instead. The vendored `weed` skill finds where code and specification have diverged.
7. Run `just check-specs`. It reads the JSON report rather than the exit code, so an `info` diagnostic fails it too, and an untouched checkout is clean, so anything it reports is a regression your change introduced. Then run `just analyse-specs`, which fails on any finding as well; a finding cannot be waived. Both run inside `just check` and need the pinned `allium` binary that `just initialize` installs into `.tools/bin`.
8. Run `just test`, then `just check` before handing back.
