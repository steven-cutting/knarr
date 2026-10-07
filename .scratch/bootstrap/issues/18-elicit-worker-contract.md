# 18: Elicit: worker contract (§9.4a, §9.4b) and readiness guidance (§9.7)

**Context:** OVERVIEW §5 drafts worker contract v1. It is pull-based, and the payload is a worker-supplied cost plus an accepting/drain state, nothing else. The open questions are:

- **§9.4a:** the endpoint shape: path, port, schema, field types, versioning and timeouts.
- **§9.4b:** how knarr discovers the endpoint on a pod, auth (if any), and compatibility with NetworkPolicies and service meshes.
- **§9.7:** how to document the readiness trade-off (NotReady pods are deleted first), and whether knarr warns on "high cost while NotReady".

**What to build:** Allium clauses for the worker contract and the readiness guidance, settled with the maintainer, that the fake worker (29) and the poller can be built against.

**Non-goals:** Cost-to-band mapping (20). Unreachable-pod policy (21). Implementation.

**Blocked by:** 17

**MVP critical path:** yes. The contract is the MVP's external interface, and 20 and 29 depend on it.

**Status:** needs-human

- [ ] The `elicit` skill is run with the maintainer in a live session.
- [ ] Every open point above is settled and recorded before any clause is written.
- [ ] The clauses cover the endpoint shape, discovery, auth, network compatibility, the drain states and readiness guidance. `check-specs` and `analyse-specs` report nothing.
- [ ] Any open question 19 left on the default or valid values of an endpoint override is closed.
- [ ] The hand-back gives the `plan-spec` obligation count and drafts the spec-then-build follow-up ticket.
