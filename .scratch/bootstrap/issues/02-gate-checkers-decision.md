# 02: Gate checkers decision: copy, rewrite or drop each biscuit_games_tooling checker

**Context:** libpawdoku's gate leaned on the Python checkers in `biscuit_games_tooling`. knarr does not depend on that package; anything it wants from it is copied in. The checkers are:

- the worktree-snapshot gate runner, which hashes every tracked and untracked-unignored path after each recipe and aborts on any change
- `validate_docs`
- `validate_agents`, which hard-codes a required-phrase list that includes the game-only word `runes`
- the Allium installer and runner, which pins the binary by checksum and reads JSON diagnostics because the exit code cannot be trusted
- the ripsecrets wrapper

**What to build:** A decision record with one row per checker: copy it (vendored with provenance), rewrite it (and in what language and runtime), or drop it (and what replaces it, if anything). The read-only gate keeps its main guarantee: no gate recipe may modify the worktree.

**Non-goals:** Wiring the checkers into the gate. That is done by the lane that owns each one: the runner and the ripsecrets wrapper in 03, docs in 06, Allium in 07, agents in 09.

**Blocked by:** 01

**From 01:** [Decision 0003](../../../docs/decisions/0003-tool-manager.md) settles 01. Read [01's hand-back notes](01-tool-manager-decision.md#follow-ups-for-02) first: they fix where a checker's runtime comes from, rule out remote hooks for tools pixi already provides, and name the source of ripsecrets and editorconfig-checker.

**MVP critical path:** yes. It gates the foundation (03).

**Status:** ready-for-agent

- [ ] Every checker listed above has a decision and a reason.
- [ ] Every copied file has provenance recorded: source repository, commit and original path. Its licence is confirmed compatible with Apache-2.0.
- [ ] The runtime for kept or rewritten checkers (for example Python from the pixi environment) is owned by the manifest decided in 01, not by a second installer.
- [ ] The agents checker's required phrases come from project configuration. `runes` and other game-only wording are gone.
- [ ] The snapshot guarantee is kept as is or replaced by an equivalent, and the record says which.
- [ ] A decision record is written. Follow-ups for 03 (runner and ripsecrets), 06, 07 and 09 name which checker each lane brings in.
