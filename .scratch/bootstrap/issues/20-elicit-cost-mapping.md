# 20: Elicit: cost mapping, bands, hysteresis and sign convention (§9.5)

**Context:** OVERVIEW §6 explains how `pod-deletion-cost` biases ReplicaSet victim ranking, and the explainer illustrates bands and the sign convention. §9.5 leaves open:

- the sign convention
- the knarr-owned range
- the number of bands and their edges
- hysteresis
- reserved bands
- how `cost` and `accepting` combine (§5 drain states)

The sign convention also fixes what removing an annotation means, which §9.12 depends on (23).

**What to build:** Allium clauses for the reconciler's clamp → band → hysteresis → decide-patch path (OVERVIEW §8), settled with the maintainer.

**Non-goals:** Unknown and unreachable handling (21). Write budgets (24).

**Blocked by:** 18

**MVP critical path:** yes. This is the core MVP mechanism.

**Status:** done. See [the hand-back notes](#hand-back-notes).

- [x] The `elicit` skill is run with the maintainer in a live session.
- [x] Every open point above is settled and recorded before any clause is written, including what an absent annotation means.
- [x] The clauses cover clamping, banding, hysteresis, reserved bands and the cost-accepting combination. `check-specs` and `analyse-specs` report nothing. (Banding and hysteresis are settled as none and a change threshold; the clauses say so.)
- [x] Any open question 19 left on the default or valid range of a band or hysteresis override is closed.
- [x] The hand-back gives the `plan-spec` obligation count and drafts the spec-then-build follow-up ticket.

## Settled

The live session ran on 2026-10-10 in four rounds. The maintainer departed from the recommended option three times, and those three choices shape the module: there are no bands, no quantization and no hysteresis. The module and this table are the record; no decision record is written, as 18 did.

| # | Point | Decision | Rejected |
| --- | --- | --- | --- |
| 1 | Sign convention | Idle is 0, busy is above 0. Unannotated pods tie with idle pods. | Idle below 0 with 0 reserved as neutral (recommended); all positive with 0 as unknown. |
| 2 | Absent annotation | Absent means 0 and is the neutral value. Removal, the neutral fallback (21) and cleanup (23) are one operation. | Absent as a state distinct from idle. |
| 3 | Draining | A valid reading with `accepting` false and cost 0 maps to `-1`, below every idle and unannotated pod. With a positive cost the cost rules, draining or not: no override, no floor. | Ignoring `accepting` in the mapping; the §5 candidate floor for draining pods. |
| 4 | Idle write | Nothing is written for 0: the annotation is removed. The string `"0"` is never emitted. | Writing `"0"`. |
| 5 | Quantization | None. The written value is the clamped cost itself. | Two busy bands with edges 1 and 600 (recommended); one busy band; three bands. |
| 6 | Hysteresis | None. The change threshold (8) is the only damping. | Descend after N consecutive polls (recommended); a value margin below each edge; both. |
| 7 | Clamp | A cost above 2147483647 is written as 2147483647. A negative cost never reaches the mapping (worker_contract `ValidReading`). | Treating it as an invalid reading. |
| 8 | Change threshold | With w the last applied value and n the new mapped value, both positive, n replaces w when the absolute difference between n and w, multiplied by 100, is at least `min_change_percent` multiplied by w, in integers with no rounding. A move to or from 0 or `-1` always writes; n = w never writes. Default 10, valid 0 to 100, 0 disables; overridable per Deployment (19). | No threshold, the write budget alone; the last reading as the baseline, which lets a slow drift never write. |
| 9 | Canonical string | Signed decimal int32: no plus sign, no leading zeros, `"-1"` for drained, no string for 0. | None. |
| 10 | Module name | `cost_mapping`, in `docs/specs/cost_mapping.allium`, replacing `banding.allium`. | Keeping `banding`. |
| 11 | Follow-up | Ticket [31](31-spec-then-build-reconcile-core.md)'s boxes are amended, as Decision 0009 asks of follow-ups that overlap it. No new ticket. | A new spec-then-build ticket. |
| 12 | Network | `just initialize` was authorized once in this session, to install the gate toolchain. Nothing was pushed. | Verifying by inspection only. |

The departure from OVERVIEW §6 was put to the maintainer in full before it was taken: KEP-2255 and the ReplicaSet docs ask for coarse-grained updates and warn against writing a metric value, and Decision 0009 mapped quantization and hysteresis to this module. The maintainer chose the continuous value with the change threshold. Decision 0009 says a ticket that finds the overview wrong amends the overview and the map follows; both are amended here.

Boundaries kept: `cost_mapping` owns the mapped value, its string and whether a change is due. `worker_contract` owns the wire shape and the `draining` predicate. When a reading other than a valid one feeds the mapping, and the removal itself, are `reconcile` (21, 31); expiry and cleanup are `lifecycle` (23); whether a due write may go now is `budget` (24); the override key for the threshold and an invalid override are `config` (19).

## Hand-back notes

### What changed

- `docs/specs/cost_mapping.allium` (renamed from `banding.allium`): the seven open questions became the `CostMapping` contract with the signatures `map`, `render` and `due`, the invariants `Continuous`, `Sign`, `Absent`, `Drained`, `Clamp`, `Canonical`, `ChangeThreshold` and `Pure`, the value type `Mapped`, and a `config` block with `min_change_percent`. `just plan-spec docs/specs/cost_mapping.allium` reports 6 obligations.
- Sibling modules, wording only, each still its owner's: `worker_contract` names `cost_mapping` and its `ReadinessWarning` reads "maps to a value above 0"; `knarr` lists the module; `reconcile`'s neutral question names the removal; `config`'s override question names the change threshold; `safe_to_evict`'s threshold question names a cost, not a band; `lifecycle` and `observability` say cost where they said band.
- `docs/OVERVIEW.md`: §4 step 3, the §5 drain-state table and state diagram, the §6 update-frequency bullets, diagram and sign-convention paragraph, §7, §8 and §9.5 point at the module and no longer say band, quantize or hysteresis; the glossary's **Band** is **Mapped value**. `docs/overview-explainer.html` section 2 shows the continuous axis, the threshold zone and the settled sign convention. `docs/DEFERRED.md` and `docs/explanation/README.md` follow. No page was added, so `docs/manifest.yml` is untouched.
- [Decision 0009](../../../docs/decisions/0009-allium-objective-map.md): the module table and every `banding` row name `cost_mapping`; the quantize, hysteresis and reserved-band rows read "settled as none" or "settled as a change threshold" rather than being deleted; the Consequences record the amendment.
- Tickets: [31](31-spec-then-build-reconcile-core.md) names `cost_mapping`, its readiness, desired-state and patch boxes read value and threshold instead of band, and it gains the `CostMapping` test box. The [bootstrap README](../README.md) is unchanged: 20's edges did not move.

### What was verified

- `just check-specs` and `just analyse-specs`: 11 specifications, no diagnostics and no findings.
- `just plan-spec docs/specs/cost_mapping.allium`: 6 obligations (one value type at two, three contract signatures, one config default).
- `just docs-check` validates 26 pages and 30 canonical topics, including the new links into `docs/specs/cost_mapping.allium`.
- `just check` ends with "All checks passed and the worktree is unchanged." Nothing under `src/` or `test/` changed, and nothing ran against a cluster.

### Choices a maintainer may reverse

- `due` is false when the next value equals the written one, although the literal rule "either side 0 or -1 always writes" would make `due(absent, absent)` true. Strike that sentence of `ChangeThreshold` if equality should be reconcile's concern alone.
- The threshold is stated in words in the clause, not as a formula, because the gate fails on any diagnostic and the language reference warns on prose that resembles a formal expression. Try the symbolic form and let the gate decide if it is preferred.
- `render` returns `String?`, with null as the removal. The pinned checker accepts the optional return. If a later pin does not, split it into `render: (mapped: Mapped) -> String` and `removes: (mapped: Mapped) -> Boolean`.
- Decision 0009's quantize, hysteresis and reserved-band rows are kept as settled rather than deleted, so the map still shows what §6 asked and what was decided.
- No decision record for the departure from the KEP's coarse-grained advice; the module header, OVERVIEW §6 and this ticket are the record. Say so if a Decision 0014 is wanted.
- 31 is amended rather than a new ticket drafted.

### What later tickets need

- **19:** one override, `min_change_percent`, an Integer with default `config.min_change_percent` (10) and valid range 0 to 100. What happens on an invalid override is yours. No band or hysteresis override exists.
- **21:** the neutral value is the removed annotation, which `render` spells as no string. Only a valid reading reaches `map`; which reading kinds keep the last value and for how long is yours, and the fallback write is a removal.
- **23:** cleanup is the same removal. Writes are sparse by the threshold as well as by banding, so the marker-freshness tension in §8 stands with "the same cost reported for hours".
- **25:** the `safe-to-evict` threshold is a cost, not a band. Decision 0008's "hysteresis wider than the cost banding" reads as wider than the change threshold: your removal rule needs its own dwell, since `due` damps writes of the cost and nothing else.
- **30:** the readiness gauge counts NotReady pods whose last valid reading maps to a value above 0; the distribution metric is of the mapped value, not of bands.
- **31:** build `CostMapping` with a test per invariant as your new box says; the desired state carries the mapped value, `due` compares against the last applied value, and `render`'s null is a removal patch.
- **43:** box 17 now says 31 holds the mapped value, not the band; nothing else in the poller changes.
