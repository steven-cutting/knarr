# 17: Allium objective map and skeleton specs

**Context:** OVERVIEW §4–§9 describe knarr's behaviour at concept level and mark each item decided, recommended or OPEN. Specs decide behaviour (06's carried decision). Before any clause is elicited, the behaviours need a home and a status.

**What to build:** A map from OVERVIEW §4–§9 to proposed spec modules, with each behaviour classed as decided, open, or blocked on a spike. Skeleton modules contain only the open questions, so each elicitation ticket starts from a module the gate already accepts.

**Non-goals:** Settling any open question (18–25). Writing clauses for decided behaviour beyond naming it.

**Blocked by:** 07, 09

**MVP critical path:** yes. Every elicitation ticket starts from this map.

**Status:** ready-for-agent

- [ ] Every behaviour in OVERVIEW §4–§9 maps to one proposed module. Candidates include worker_contract, config, banding, reconcile, ownership, lifecycle, budget and safe_to_evict.
- [ ] Each behaviour is classed as decided, open, or blocked on a spike (S1 → 14, S2 → 15 and 16), with the OVERVIEW § it comes from.
- [ ] One skeleton module exists per proposed module, holding only open questions. `check-specs` and `analyse-specs` report nothing.
- [ ] The map shows which elicitation ticket (18–25) owns each open question, and nothing is left unowned.
- [ ] A decision record is written. Any open question that no ticket in 18–25 covers is drafted as a follow-up.
