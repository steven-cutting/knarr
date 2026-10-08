# 17: Allium objective map and skeleton specs

**Context:** OVERVIEW §4–§9 describe knarr's behaviour at concept level and mark each item decided, recommended or OPEN. Specs decide behaviour (06's carried decision). Before any clause is elicited, the behaviours need a home and a status.

**What to build:** A map from OVERVIEW §4–§9 to proposed spec modules, with each behaviour classed as decided, open, or blocked on a spike. Skeleton modules contain only the open questions, so each elicitation ticket starts from a module the gate already accepts.

**Non-goals:** Settling any open question (18–25). Writing clauses for decided behaviour beyond naming it.

**Blocked by:** 07, 09

**MVP critical path:** yes. Every elicitation ticket starts from this map.

**Status:** done. See [Decision 0009](../../../docs/decisions/0009-allium-objective-map.md).

- [x] Every behaviour in OVERVIEW §4–§9 maps to one proposed module. Candidates include worker_contract, config, banding, reconcile, ownership, lifecycle, budget and safe_to_evict.
- [x] Each behaviour is classed as decided, open, or blocked on a spike (S1 → 14, S2 → 15 and 16), with the OVERVIEW § it comes from.
- [x] One skeleton module exists per proposed module, holding only open questions. `check-specs` and `analyse-specs` report nothing.
- [x] The map names an owner for every behaviour, decided or open, and nothing is left unowned. An owner is an elicitation ticket (18–25) or a follow-up drafted under the next box. A decided behaviour counts as owned by an elicitation ticket only if that ticket's acceptance checks already name it. This includes the §4 safeguards that no §9 item raises, such as no patches once a pod has `deletionTimestamp` set and never patching the Deployment's pod template. §9.16's success-criterion thresholds are owned the same way: 23 and 24 each hand one value to it, and the first criterion (fewer busy pods killed) has no ticket, so it is drafted as a round-2 follow-up with the KEDA harness.
- [x] A decision record is written. Any open question that no ticket in 18–25 covers is drafted as an elicitation follow-up. Any decided behaviour that no elicitation ticket's acceptance checks name is drafted as a spec-then-build follow-up for round 2, with acceptance checks that name each behaviour.

## Hand-back notes

**What changed.** [Decision 0009](../../../docs/decisions/0009-allium-objective-map.md) holds the map: one table per OVERVIEW section with the module, the class (decided, open, or blocked on a spike) and the owner of every behaviour, plus the reading of what counts as a behaviour. Ten skeleton modules sit beside `docs/specs/knarr.allium`: `worker_contract`, `config`, `banding`, `reconcile`, `ownership`, `lifecycle`, `budget`, `safe_to_evict`, `k8s_client` and `observability`. Each holds a scope header and `open question` lines only, one per §9 sub-point, each naming its OVERVIEW §. Five follow-up tickets are drafted as files, [30](30-elicit-observability.md) to [34](34-user-guides.md), and the [bootstrap README](../README.md) carries them in the graph and the waves table. Tickets 18 to 25 are unchanged.

**What was verified.** `just check-specs` and `just analyse-specs` report nothing across eleven modules. `just plan-spec` reports 0 obligations for every module, including the root. `just docs-check` validates 21 pages. `just check` ends with "All checks passed and the worktree is unchanged."

**Choices a maintainer may reverse.** Follow-ups are new ticket files numbered from 30, not hand-back subsections; ticket 28's wording and this ticket's "acceptance checks that name each behaviour" read as a full ticket shape. Two owners sit outside this ticket's definition: ticket 14 owns the `k8s_client` rows, and ticket 28 owns §9.15. Recommended, proposed and to-be-confirmed items are classed open, so they go to their elicitation ticket rather than to round 2.

### For 18 to 25

- Start from your module's skeleton. Delete each `open question` as the maintainer settles it, and add clauses in the same module; the header comment states its scope.
- Hand back `just plan-spec docs/specs/<module>.allium`. Every module reports 0 today.
- Where your spec-then-build follow-up overlaps [31](31-spec-then-build-reconcile-core.md) or [32](32-spec-then-build-ownership-lifecycle.md), amend that ticket rather than draft a second one. 22 also amends `k8s_client`'s questions with what the write mode needs.
- The pinned Allium 3.6.1 emits nothing for an `open question`; the vendored language reference says a checker should warn. If the pin moves and the gate starts to warn, the questions in your module are the ones that fail it.

### For 30 to 34

- Each ticket's **From 17** line points at the map rows it owns. 30 is an elicitation ticket for §9.14 and starts from `docs/specs/observability.allium`. 31 and 32 name every decided behaviour they build, so `propagate` has a clause per box. 33 needs the threshold from the maintainer and the sink 29 names. 34 writes each page only after the elicitation ticket it names has settled the behaviour.
