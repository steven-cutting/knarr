# 13: Walking skeleton: knarr runs in the local cluster

**Context:** OVERVIEW §8 sketches the supervision tree and names a single replica with the `Recreate` strategy. §9.14 wants metrics, and controllers conventionally expose `/metrics`. The metrics library options are:

- `prometheus` (prometheus.erl): mature, with VM collectors, behind a thin FFI. It needs rebar3; 01 says where rebar3 comes from.
- `themis`: pure Gleam, but young.

Either way the library sits behind a `metrics` module. Metric names follow controller-runtime style, for example `knarr_poll_total{result}` and `knarr_patch_total{result,code}`.

**What to build:** knarr starts as a supervised OTP application, serves health and metrics endpoints, ships as a small non-root image, and deploys to the cluster chosen in 10 with one `just` recipe. A smoke test proves it end to end. It does nothing to pods yet.

**Non-goals:** A Kubernetes client (14). Any polling, banding or patching. A release pipeline (28).

**Blocked by:** 05, 08, 10

**From 11:** [30](30-bootstrap-verification-gaps.md) tracks native Linux TLS/rebar3 evidence that ordinary CI does not establish; coordinate that item before relying on 01's emulated results for the image and metrics-library choice.

**MVP critical path:** yes. It is the base every MVP feature is built and deployed on.

**Status:** ready-for-agent

- [ ] A short decision record picks the metrics library, weighing the rebar3 finding from 01.
- [ ] A supervised application on `gleam_otp` restarts a crashed child, and a test shows it.
- [ ] `mist` serves:
  - `/healthz`: 200 while the VM is up
  - `/readyz`: 200 once the supervision tree has started
  - `/metrics`: Prometheus text exposition with one `knarr_` counter, plus VM collectors if the library provides them
- [ ] The image is built from an `erlang-shipment` in a multi-stage build. It runs as a non-root numeric UID with a read-only root filesystem. A check proves the build and runtime stages use the same OTP major (the owner set in 01). hadolint passes, if 01 kept it.
- [ ] A kustomize base renders:
  - a ServiceAccount
  - a minimal Role
  - a Deployment with `replicas: 1`, strategy `Recreate`, liveness and readiness probes, and a restrictive securityContext
- [ ] kubeconform validates the rendered base, if 01 kept it; otherwise the record names the replacement check.
- [ ] `just` recipes cover cluster up, deploy and smoke, using the per-worktree naming from 10. The smoke test hits all three endpoints in the cluster.
- [ ] A CI smoke job runs on kind. It is not a dependency of the aggregate `check` job (05) and is not a required status check until it has been stable for a stated period.
