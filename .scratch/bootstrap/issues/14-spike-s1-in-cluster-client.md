# 14: Spike S1: an in-cluster k8s client from a pod on kind

**Context:** OVERVIEW §9.2 decides option (A): a pure Gleam client with Erlang FFI. §8 names in-cluster TLS as the hard part. The cluster CA is not in the OS trust store. `gleam_httpc` passes no ssl options when verification is on, so knarr must pass explicit `verify_peer`, the service-account `ca.crt` as `cacertfile`, and a hostname check. Whether hostname verification against the IP in `KUBERNETES_SERVICE_HOST` works is unverified. Projected tokens rotate on disk, so they must be re-read. 01 confirms that conda-forge's Erlang can do verified TLS at all.

**What to build:** From the walking-skeleton pod on kind, knarr lists pods in its namespace and patches one annotation over verified TLS with a reloading token. Wrong-CA attempts are rejected. The client follows the sans-IO pattern from 08.

**Non-goals:** Watch-based discovery. Deployment and ReplicaSet reads beyond what proves the path. Rate limiting (§9.8).

**Blocked by:** 13

**From 11:** [35](35-bootstrap-verification-gaps.md) tracks native Linux TLS/rebar3 probes and `/version` fixture provenance; coordinate those items before treating 01's emulated TLS results or 08's hand-written fixture as native or captured evidence.

**MVP critical path:** yes. The whole controller depends on this client, and S1 validates §9.2.

**Status:** ready-for-agent

- [ ] TLS uses explicit ssl options: `verify_peer`, the SA `ca.crt` as `cacertfile`, and a hostname check that passes against the IP in `KUBERNETES_SERVICE_HOST` (IP-SAN). The OTP version is the one from 01.
- [ ] A negative test with a wrong CA fails the handshake visibly. It must not fall back to an unverified connection.
- [ ] The token is re-read from disk on a schedule and never cached for the life of the process. The proof uses a custom projected token volume with a short `expirationSeconds` (600, the minimum), because the API server extends the default token's expiry. Rotation alone proves nothing, since the old token stays valid until it expires. The same knarr process must keep succeeding after the original token's expiry time. Logs show the token file's hash changing. The token itself is never logged.
- [ ] knarr LISTs pods in its namespace and PATCHes one annotation on one pod with a merge patch. The Role grants exactly the verbs used.
- [ ] Request builders and response decoders are pure. `send` is injected. Unit tests use a closure fake and a birdie snapshot of each request.
- [ ] The findings confirm or amend the §9.2 decision in a decision record.
- [ ] Follow-ups are drafted: the client module's spec-then-build pair, and anything found about OTP or ssl.
