# 29: Fake-worker fixture

**Context:** A §3 success criterion runs a KEDA-scaled Deployment with a mixed fake-worker load on kind and compares how many busy pods are killed with and without knarr. §9.16 names a fake worker image. The worker contract comes from 18.

**What to build:** A configurable worker image that implements the elicited worker contract. A control endpoint can set its cost, its accepting state and its failure modes at runtime, so the round-2 KEDA e2e harness can drive a realistic mixed load.

**Non-goals:** The KEDA e2e harness and the success-criterion run (round 2). knarr's poller.

**Blocked by:** 13, 18

**MVP critical path:** yes. The MVP success criterion is measured with it.

**Status:** ready-for-agent

- [ ] The status endpoint matches the clauses from 18 exactly, and tests trace each clause.
- [ ] A control endpoint sets cost, accepting or draining, response latency, and failure modes (timeout, 5xx, 404, invalid payload) per pod at runtime.
- [ ] On SIGTERM it drains gracefully within a configurable time and records whether it was busy when killed, so a test run can count busy kills.
- [ ] The image is built the same way as knarr's (13): non-root, small, and loadable into the cluster from 10.
- [ ] A kind smoke test deploys several replicas, sets mixed states through the control endpoint, and reads them back from the status endpoint.
