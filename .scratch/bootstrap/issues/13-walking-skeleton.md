# 13: Walking skeleton: knarr runs in the local cluster

**Context:** OVERVIEW §8 sketches the supervision tree and names a single replica with the `Recreate` strategy. §9.14 wants metrics, and controllers conventionally expose `/metrics`. The metrics library options are:

- `prometheus` (prometheus.erl): mature, with VM collectors, behind a thin FFI. It needs rebar3; 01 says where rebar3 comes from.
- `themis`: pure Gleam, but young.

Either way the library sits behind a `metrics` module. Metric names follow controller-runtime style, for example `knarr_poll_total{result}` and `knarr_patch_total{result,code}`.

**What to build:** knarr starts as a supervised OTP application, serves health and metrics endpoints, ships as a small non-root image, and deploys to the cluster chosen in 10 with one `just` recipe. A smoke test proves it end to end. It does nothing to pods yet.

**Non-goals:** A Kubernetes client (14). Any polling, banding or patching. A release pipeline (28).

**Blocked by:** 05, 08, 10

**MVP critical path:** yes. It is the base every MVP feature is built and deployed on.

**Status:** implemented; live validation pending

- [x] A short decision record picks the metrics library, weighing the rebar3 finding from 01.
- [x] A supervised application on `gleam_otp` restarts a crashed child, and a test shows it.
- [x] `mist` serves:
  - `/healthz`: 200 while the VM is up
  - `/readyz`: 200 once the supervision tree has started
  - `/metrics`: Prometheus text exposition with one `knarr_` counter, plus VM collectors if the library provides them
- [ ] The image is built from an `erlang-shipment` in a multi-stage build. It runs as a non-root numeric UID with a read-only root filesystem. A check proves the build and runtime stages use the same OTP major (the owner set in 01). hadolint passes, if 01 kept it.
- [x] A kustomize base renders:
  - a ServiceAccount
  - a minimal Role
  - a Deployment with `replicas: 1`, strategy `Recreate`, liveness and readiness probes, and a restrictive securityContext
- [x] kubeconform validates the rendered base, if 01 kept it; otherwise the record names the replacement check.
- [ ] `just` recipes cover cluster up, deploy and smoke, using the per-worktree naming from 10. The smoke test hits all three endpoints in the cluster.
- [x] A CI smoke job runs on kind. It is not a dependency of the aggregate `check` job (05) and is not a required status check until it has been stable for a stated period.

## Hand-back notes

The skeleton has an OTP application callback, a Gleam supervisor and a Mist
listener. Diagnostics routing is pure; metrics collection is injected at the
adapter boundary. Decision 0009 chooses prometheus.erl, using 01's rebar3 proof.
The startup counter registers before listener startup and survives listener
recovery. The skeleton makes no Kubernetes API calls.

The image uses the locked pixi default and runtime environments and a production
Erlang shipment, with numeric UID/GID 10001. The local deployment supplies a
read-only root, writable `/tmp`, probes and an empty Role. Kubernetes schemas
are vendored at a recorded upstream revision, with compressed and original
checksums and the upstream license. Validation has no remote schema fallback.

The cluster recipes promote 10's naming seam. They isolate kubeconfig and kwok
state, guard against switching runners without cleanup, preserve state when
teardown fails, and trigger a rollout when a rebuilt local image changes ID.
The kind endpoint smoke and kwok readiness jobs are outside aggregate `check`.
The guide states 14 consecutive days of infrastructure stability before a
maintainer considers making kind required.

Verification so far:

- 20 Gleam tests passed, including real local HTTP and killing the supervised
  listener, then observing recovery on the same port with counter value one.
  Occupied-port startup returns failure. Separate Erlang subprocess tests prove
  exit code 1 after startup failure or exhausted supervision and exit code 0
  on normal shutdown. Routing tests cover readiness before
  and after startup, unknown paths, method rejection and injected exposition.
- 302 Python checker and process tests passed, including worktree names, command isolation,
  runner changes, failed cleanup, image rollout identity, missing kubeconfig,
  inherited in-cluster configuration, image failure diagnostics and manifest security.
- Production `gleam export erlang-shipment` succeeded. The entrypoint starts the
  OTP application before calling `main` and exits nonzero on startup failure.
- The rendered base passes strict kubeconform validation: three valid resources,
  none skipped. hadolint, actionlint and the documentation checks passed.
- `just check-specs` reports no diagnostics; `just analyse-specs` no findings.
  `just plan-spec docs/specs/knarr.allium` reports nine structural obligations.
  The diagnostic and lifecycle guarantees are prose contract invariants, tested
  explicitly; that structural count is not a claim of formal behaviour coverage.
- The full `just check` passed with "All checks passed and the worktree is
  unchanged."
- Image execution, kind endpoint smoke and kwok readiness await network
  authorization. Native GitHub Actions execution has not been observed.

Later tickets:

- **14:** add the Kubernetes client and its permissions; the skeleton deliberately
  has no RoleBinding, no rules and no mounted ServiceAccount token. Reuse the
  existing runtime supervision and cluster recipes. `gleam_http` is now a runtime
  dependency; `gleam_json` remains a development dependency until source uses it.
- **15:** use the kwok tier for controller/API semantics and kind for actual pods.
- **28:** image publication, multi-platform releases and registry policy remain
  outside this ticket. The local image targets the locked linux/amd64 platform.

### Adversarial review

Claude Code reviewed the complete implementation with `--model opus --effort
medium`. Its response identified the selected model as **Claude Opus 5.5**
(`claude-opus-5-5`). Read-only tools were used; it did not claim to run checks.

Applied findings, with failing regression tests observed before the fixes:

- Commands now reject a missing local kubeconfig before any cluster tool runs,
  and clear inherited Kubernetes service environment variables.
- Image verification retains an exited container long enough to print its logs,
  then removes it without replacing the original failure with a cleanup error.
- The entrypoint monitors the application's root supervisor. Exhausting the
  explicit two-restarts-in-five-seconds tolerance exits the VM unsuccessfully;
  normal VM shutdown remains successful. The contract states the tolerance.
- Test and lint listeners now bind loopback. The socket test asserts the bound
  address, and the spec records the default and configurable listening endpoint.
- Naming comments and the image check's OTP ownership wording are corrected.
  Rendered validation is explicitly separate from the default offline gate.

The cached pixi image was inspected with networking disabled: it has CA
certificates but no curl, confirming the build-tool finding. The Dockerfile now
fetches rebar3 with checksum-verified `ADD`; a regression check ties its URL and
checksum to `tools.txt`. Running the amd64 image inside kind on an ARM host
still needs live validation. The
reviewer's other live-run questions (image attestations, kwok reuse and cleanup)
are likewise unverified. The version-tagged base images are not digest-pinned;
locked package and tool inputs do not make the base OS immutable. The unused
standalone kwok binary retains 01/10's pinned tool inventory for the integration
tier. No registry publication or branch-protection change is part of this ticket.

The same Opus 5.5 reviewer checked the applied fixes in a focused follow-up at
medium effort and reported no new definite, actionable bugs.
