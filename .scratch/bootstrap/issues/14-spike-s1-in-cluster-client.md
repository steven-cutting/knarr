# 14: Spike S1: an in-cluster k8s client from a pod on kind

**Context:** OVERVIEW §9.2 decides option (A): a pure Gleam client with Erlang FFI. §8 names in-cluster TLS as the hard part. The cluster CA is not in the OS trust store. `gleam_httpc` passes no ssl options when verification is on, so knarr must pass explicit `verify_peer`, the service-account `ca.crt` as `cacertfile`, and a hostname check. Whether hostname verification against the IP in `KUBERNETES_SERVICE_HOST` works is unverified. Projected tokens rotate on disk, so they must be re-read. 01 confirms that conda-forge's Erlang can do verified TLS at all.

**What to build:** From the walking-skeleton pod on kind, knarr lists pods in its namespace and patches one annotation over verified TLS with a reloading token. Wrong-CA attempts are rejected. The client follows the sans-IO pattern from 08.

**Non-goals:** Watch-based discovery. Deployment and ReplicaSet reads beyond what proves the path. Rate limiting (§9.8).

**Blocked by:** 13

**From 11:** [35](35-bootstrap-verification-gaps.md) tracks native Linux TLS/rebar3 probes and `/version` fixture provenance; coordinate those items before treating 01's emulated TLS results or 08's hand-written fixture as native or captured evidence.

**MVP critical path:** yes. The whole controller depends on this client, and S1 validates §9.2.

**Status:** in-review, kind run pending in CI

- [ ] TLS uses explicit ssl options: `verify_peer`, the SA `ca.crt` as `cacertfile`, and a hostname check that passes against the IP in `KUBERNETES_SERVICE_HOST` (IP-SAN). The OTP version is the one from 01.
- [ ] A negative test with a wrong CA fails the handshake visibly. It must not fall back to an unverified connection.
- [ ] The token is re-read from disk on a schedule and never cached for the life of the process. The proof uses a custom projected token volume with a short `expirationSeconds` (600, the minimum), because the API server extends the default token's expiry. Rotation alone proves nothing, since the old token stays valid until it expires. The same knarr process must keep succeeding after the original token's expiry time. Logs show the token file's hash changing. The token itself is never logged.
- [ ] knarr LISTs pods in its namespace and PATCHes one annotation on one pod with a merge patch. The Role grants exactly the verbs used.
- [x] Request builders and response decoders are pure. `send` is injected. Unit tests use a closure fake and a birdie snapshot of each request.
- [x] The findings confirm or amend the §9.2 decision in a decision record.
- [x] Follow-ups are drafted: the client module's spec-then-build pair, and anything found about OTP or ssl.

## Hand-back notes

The first four boxes stay unticked until the `cluster-s1` CI job has run: each
names something only the pod on kind shows. What is proven locally, and
where, is below; [Decision 0011](../../../docs/decisions/0011-in-cluster-client.md)
holds the findings and marks the kind row pending.

### What changed

- `docs/specs/k8s_client.allium`: the three §9.2 open questions became the
  `Client` contract with `VerifiedTls`, `TokenReload`, `Verbs` and
  `NoPatchWhileTerminating`; the §9.10 question stays. `knarr.allium`'s
  `NoPodEffects` now describes the probe and says the gate runs with it off.
  `just plan-spec docs/specs/k8s_client.allium` reports 8 structural
  obligations.
- `src/knarr/k8s_client.gleam`: pure builders and decoders for the pod list
  and the merge patch, joined by `list_pods` and `patch_annotation` with an
  injected `send`. `src/knarr/token.gleam` reads a JWT's `exp`.
- `src/knarr/k8s_http.gleam` with `k8s_http_ffi.erl`: the production `send`,
  one `httpc:request` with `verify_peer`, the given CA file and the https
  hostname check; every failure is a `SendError` value. No `gleam_httpc`.
- `src/knarr/s1_probe.gleam` with `s1_probe_ffi.erl`: the probe actor under
  its own supervisor (three restarts a minute), added as the root's second
  child only when `-knarr s1_probe true` is set. `runtime.start` takes
  `probe: Option(Config)`; `application_ffi.erl` builds the config from the
  pod's environment through the positional `s1_probe.config`.
- `deploy/base/resources.json`: Role rules `list` and `patch` on pods, a
  RoleBinding, the projected `kube-api-access` volume (token at 600 s,
  `kube-root-ca.crt`, namespace), `POD_NAME` and `ERL_FLAGS`.
  `deploy/wrong-ca/` is the negative variant; `just deploy <image> <variant>`
  and `just deployment-check` render variants, and the RoleBinding schema is
  vendored with its sha256.
- `.github/workflows/ci.yml`: the non-required `cluster-s1` job runs the
  three evidence scripts. `ci.yml` runs on pull requests and pushes to main
  only, so the job needs a pull request for this branch.
- Docs: Decision 0011, its manifest and index entries, the testing reference,
  the local cluster guide and OVERVIEW §8 and §9.2 point at it. Tickets
  [36](36-k8s-client-spec-then-build.md) and [37](37-otp-ssl-findings.md)
  are drafted and in the bootstrap README.

### What was verified

- `just check` ends with "All checks passed and the worktree is unchanged."
  55 Gleam tests pass: builders and decoders by value, a fixed-seed property,
  closure fakes, two accepted snapshots (`pod list request sent by
  list_pods`, `merge patch request sent by patch_annotation`, both with the
  token `test-token`), the JWT tests, the loopback TLS test (right CA, wrong
  CA refused with `unknown_ca`, closed port, one content-type header, an
  unsupported method as a value) and the probe tests (token re-read between
  ticks, a missing token or namespace file skips the cycle, a failing send leaves the process
  alive, the sub-supervisor restarts the probe while the listener pid is
  unchanged, the terminating-pod decision, the positional config).
- 318 checker tests pass, including the Role, RoleBinding, projected token,
  variant rendering and refused unknown variant.
- `evidence/14/tls.txt`: all eight local ssl, httpc and `pkix_test_data`
  cases matched; OTP 29 sends the IP literal as SNI.
- `evidence/14/emulation.txt`: the amd64 runtime and the image build fail
  under Rosetta in `prim_tty`; `+JMsingle true` fixes the runtime only. The
  kind proof therefore runs in CI, as agreed for the plan.
- The exported shipment, run locally with `-knarr s1_probe true` against a
  closed loopback port, logged `token_changed token_sha256=... jwt_exp=...`
  and `list_pods_failed error=connect_failed econnrefused` and stayed up;
  with `POD_NAME` unset the start failed with
  `missing_environment_variable`.

### What later tickets need

- **The maintainer, now:** open a pull request for this branch so
  `cluster-s1` runs (a push alone triggers nothing), then copy its
  `s1-kind.txt` and `wrong-ca.txt` beside the scripts, tick the first four
  boxes and settle the pending row in Decision 0011. Before the run, read
  the SNI and `+JMsingle` findings there. A local kind cluster already
  accepted both variants server-side and gave `version.json`.
  `cancel-in-progress` is on for pull requests, so a second push while the
  job runs cancels it.
- **36:** the full module and the probe's removal, with the IPv6 bracketing
  the adapter does not do, and narrowing `cluster-s1` to a `paths:` filter
  or a label once its transcripts are committed, so every pull request does
  not pay its twenty runner-minutes.
- **37:** the OTP findings listed there.
- **35:** the CI `tls/run.sh` step is the native-Linux TLS evidence for the
  default environment and `version.json` the captured `/version`; the
  runtime environment's probe and the rebar3 probe stay open.
- **22:** `Verbs` and the §9.10 question change with the write mode.
