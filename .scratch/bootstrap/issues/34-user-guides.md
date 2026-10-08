# 34: User-facing guides for workers, KEDA pairing and operation

**Context:** OVERVIEW carries guidance that is for the people who run workers and clusters, not controller behaviour: workers own graceful shutdown (§5), the readiness trade-off (§5, §9.7), pairing knarr with a KEDA ScaledObject including scale-from-zero and `behavior` tuning (§7), rollouts with `maxUnavailable` and `maxSurge` (§9.13), the `PodDeletionCost` prerequisite (§6, §9.11), NetworkPolicy configuration (§5, §9.4b), and uninstall with manual recovery (§8). Ticket 12 leaves user-facing install and KEDA pairing guides to round 2. [Decision 0009](../../../docs/decisions/0009-allium-objective-map.md) maps each item to a module and assigns the pages here.

**What to build:** Handbook pages for that guidance, each written once the owning elicitation ticket has settled the behaviour it describes, registered in `docs/manifest.yml` and reachable from `docs/README.md` as the documentation contract requires.

**Non-goals:** Controller behaviour. The API reference. The install guide 28's packaging decides.

**Blocked by:** 12, 18, 23, 24, 25

**From 17:** [Decision 0009](../../../docs/decisions/0009-allium-objective-map.md), map rows marked guidance.

**MVP critical path:** no. The MVP runs without them; users need them to adopt it.

**Status:** ready-for-agent, round 2

- [ ] A worker guide covers graceful shutdown (SIGTERM, exec-form entrypoint, `terminationGracePeriodSeconds`, `preStop` sleep, Cluster Autoscaler's termination cap) and the readiness trade-off as 18 settled it (§5, §9.7).
- [ ] A KEDA pairing guide covers scale-from-zero and `behavior` tuning (§7).
- [ ] An operations guide covers rollouts (§9.13), the `PodDeletionCost` prerequisite as 24 settled it (§9.11), NetworkPolicy configuration as 18 settled it (§9.4b), and uninstall with manual recovery as 23 settled it (§8).
- [ ] Every page passes `just docs-check`, and each paragraph that states behaviour names the clause it describes.
