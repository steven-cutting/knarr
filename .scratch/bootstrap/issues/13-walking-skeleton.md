# 13: Walking skeleton: knarr runs in the local cluster

**Context:** OVERVIEW §8 sketches the supervision tree and names a single replica with the `Recreate` strategy. §9.14 wants metrics, and controllers conventionally expose `/metrics`. The metrics library options are:

- `prometheus` (prometheus.erl): mature, with VM collectors, behind a thin FFI. It needs rebar3; 01 says where rebar3 comes from.
- `themis`: pure Gleam, but young.

Either way the library sits behind a `metrics` module. Metric names follow controller-runtime style, for example `knarr_poll_total{result}` and `knarr_patch_total{result,code}`.

**What to build:** knarr starts as a supervised OTP application, serves health and metrics endpoints, ships as a small non-root image, and deploys to the cluster chosen in 10 with one `just` recipe. A smoke test proves it end to end. It does nothing to pods yet.

**Non-goals:** A Kubernetes client (14). Any polling, banding or patching. A release pipeline (28).

**Blocked by:** 05, 08, 10

**From 11:** [35](35-bootstrap-verification-gaps.md) tracks native Linux TLS/rebar3 evidence that ordinary CI does not establish; coordinate that item before relying on 01's emulated results for the image and metrics-library choice.

**MVP critical path:** yes. It is the base every MVP feature is built and deployed on.

**Status:** implemented; Linux image and cluster validation verified

- [x] A short decision record picks the metrics library, weighing the rebar3 finding from 01.
- [x] A supervised application on `gleam_otp` restarts a crashed child, and a test shows it.
- [x] `mist` serves:
  - `/healthz`: 200 while the VM is up
  - `/readyz`: 200 once the supervision tree has started
  - `/metrics`: Prometheus text exposition with one `knarr_` counter, plus VM collectors if the library provides them
- [x] The image is built from an `erlang-shipment` in a multi-stage build. It runs as a non-root numeric UID with a read-only root filesystem. A check proves the build and runtime stages use the same OTP major (the owner set in 01). hadolint passes, if 01 kept it.
- [x] A kustomize base renders:
  - a ServiceAccount
  - a minimal Role
  - a Deployment with `replicas: 1`, strategy `Recreate`, liveness and readiness probes, and a restrictive securityContext
- [x] kubeconform validates the rendered base, if 01 kept it; otherwise the record names the replacement check.
- [x] `just` recipes cover cluster up, deploy and smoke, using the per-worktree naming from 10. The smoke test hits all three endpoints in the cluster.
- [x] A CI smoke job runs on kind. It is not a dependency of the aggregate `check` job (05) and is not a required status check until it has been stable for a stated period.

## Hand-back notes

The skeleton has an OTP application callback, a Gleam supervisor and a Mist
listener. Diagnostics routing is pure; metrics collection is injected at the
adapter boundary. Decision 0010 chooses prometheus.erl, using 01's rebar3 proof.
The startup counter registers before listener startup and survives listener
recovery. The skeleton makes no Kubernetes API calls.

The image uses the locked pixi default and runtime environments and a production
Erlang shipment, with numeric UID/GID 10001. The local deployment supplies a
read-only root, writable `/tmp`, probes and an empty Role. Kubernetes schemas
are vendored as plain upstream JSON at a recorded upstream revision, with their
checksums and the upstream license. Validation has no remote schema fallback.

The cluster recipes promote 10's naming seam. They isolate kubeconfig and kwok
state, guard against switching runners without cleanup, preserve state when
teardown fails, and trigger a rollout when a rebuilt local image changes ID.
The kind endpoint smoke and kwok readiness jobs are outside aggregate `check`.
The guide states 14 consecutive days of infrastructure stability before a
maintainer considers making kind required.

Verification so far:

- 21 Gleam tests passed, including real local HTTP and killing the supervised
  listener, then observing recovery with counter value one, both on an
  OS-assigned port and on a fixed port that the restarted listener rebinds.
  Occupied-port startup returns failure. Separate Erlang subprocess tests prove
  exit code 1 after startup failure or exhausted supervision and exit code 0
  on normal shutdown. Routing tests cover readiness before
  and after startup, unknown paths, method rejection and injected exposition.
- 310 Python checker and process tests cover, including worktree names, command isolation,
  runner changes, failed cleanup, image rollout identity, missing kubeconfig,
  inherited in-cluster configuration, image failure diagnostics and manifest security.
- Production `gleam export erlang-shipment` succeeded. The entrypoint starts the
  OTP application before calling `main` and exits nonzero on startup failure.
- The rendered base passes strict kubeconform validation: three valid resources,
  none skipped. hadolint, actionlint and the documentation checks passed.
- `just check-specs` reports no diagnostics; `just analyse-specs` no findings.
  `just plan-spec docs/specs/knarr.allium` reports eleven structural obligations.
  The diagnostic and lifecycle guarantees are prose contract invariants, tested
  explicitly; that structural count is not a claim of formal behaviour coverage.
- The full `just check` passed with "All checks passed and the worktree is
  unchanged." after the review follow-up below.
- Native Linux GitHub Actions verified image build/execution, kind endpoint
  smoke and kwok readiness. The kwok readiness job has not run since `kwok`
  left `tools.txt`; rerunning it needs a push. ARM-host image builds remain
  unverified: the local amd64 runtime failed in `prim_tty` under emulation.

Later tickets:

- **14:** add the Kubernetes client and its permissions; the skeleton deliberately
  has no RoleBinding, no rules and no mounted ServiceAccount token. Reuse the
  existing runtime supervision and cluster recipes. `gleam_http` is now a runtime
  dependency; `gleam_json` remains a development dependency until source uses it.
  The review follow-up below found that, on a fixed port, one listener crash
  uses both restarts the root tolerates. Decide whether the code or the Recovery
  clause changes before adding children under the same root.
- **15:** use the kwok tier for controller/API semantics and kind for actual pods.
- **27:** `env-check` refuses installed tools whose pin moved, but ignores an
  installed tool that `tools.txt` no longer pins. Existing worktrees keep
  `.tools/bin/kwok` and its `.pins` record until someone removes them by hand.
  Dependency updates have to handle a removed pin, not only a changed one.
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
standalone kwok binary was initially retained from 01/10's tool inventory; the
PR feedback follow-up below removes it from mandatory installation. No registry
publication or branch-protection change is part of this ticket.

The same Opus 5.5 reviewer checked the applied fixes in a focused follow-up at
medium effort and reported no new definite, actionable bugs.

### CI follow-up

Cold CI exposed a missing build prerequisite: running glinter starts the OTP
application without compiling its Gleam modules. `lint-gleam` now depends on
`build`; isolated cold-package tests prove success and build-error propagation.
Claude Code reviewed this fix with Opus 5.5 at medium effort and reproduced both
outcomes independently.

Kind then exposed an inherited descriptor-limit problem. Its containerd service
sets `LimitNOFILE=infinity`; pods exited with `OOMKilled` before application
logging at both 256 and 512 MiB, while standalone Docker used about 53 MiB.
An offline runtime probe reproduced exit 137 with 1,073,741,816 descriptors;
a bounded limit got past memory initialization. The container entrypoint now
caps the soft limit at 65,536 and preserves lower inherited limits. The original
64 MiB request and 256 MiB limit remain. Kind smoke passed with that fix.

Image validation checks the actual entrypoint configuration, tests its cap, and
starts the application with a high descriptor limit and the deployment's memory
budget without swap. Informational stats cannot fail a healthy image. Failure
diagnostics include container state, pod termination reasons and previous logs.
Shell tests cover lower, high and unlimited limits without requiring the host to
raise its hard limit; Docker supplies the real high-limit integration test.
Opus 5.5 reviewed the follow-up at medium effort; its entrypoint-wiring and
host-limit portability findings are covered by these regressions.

### PR feedback follow-up

All five findings on PR 10 were valid and have local fixes:

- The diagnostics response now models headers. Its contract specifies
  `Allow: GET` for rejected methods and the Prometheus content type. The
  routing test covers POST, HEAD and OPTIONS on all three known paths without
  collecting metrics; existing exposition tests cover the content type.
- The recovery test starts Mist on port zero, removing the released-socket
  allocation race and the `local_port` FFI helper. The specification explicitly
  permits a new OS-assigned port after restart. The helper verifies a positive
  port, loopback binding and all three endpoints after child replacement,
  preserving startup-counter and VM-metric assertions. Occupied-port startup
  failure remains covered. The review follow-up below adds a fixed-port test
  beside it.
- Mandatory downloads no longer include the unused standalone `kwok` binary.
  `kwokctl` and its controller image remain. No installer change or new pin is
  needed; the original tool investigation evidence is preserved.
- Decision 0003 now documents Docker's checksum-verified rebar3 download,
  `tools.txt` ownership and the existing URL/checksum regression check.
- Decision 0007 distinguishes the tag-based experiment from the implemented
  five digest-pinned image flags and documents the installed kwok tooling.

Verification: changing the recovery test to port zero first produced 19 passing
Gleam tests and one `RecoveryTimeout` failure under the old same-port assertion.
After the helper fix, all 20 passed; `just format-check` and `just build` passed.
All 310 checker/process tests and packaging validation also passed.
The expanded header tests already pass against the existing HTTP implementation;
this finding corrected its specification, not its runtime behavior.
`just check-specs` and `just analyse-specs` report no diagnostics or findings.
`just plan-spec docs/specs/knarr.allium` reports 11 structural obligations, up
from nine because of the Header value. Prose contract invariants still require
explicit behavioral tests; this count is not formal behavior coverage.
The full offline gate remains the acceptance check for the follow-up. Later
tickets inherit the same runtime interfaces and cluster commands.

### Review follow-up

`/code-review xhigh` with Opus 5.5 reviewed the PR feedback follow-up commit
and reported nine findings. Six are fixed here; none changes product behavior.

- The recovery helper counted accepted keep-alive sockets as listeners, so a
  retry after a partly successful attempt failed while those connections stayed
  open. It now counts only sockets with no peer. One `serves` helper checks the
  loopback listener, all three endpoints, the startup counter and VM metrics,
  before and after the kill.
- Port zero had replaced, not joined, the same-port recovery check. The Lifecycle
  `Listening` clause now states that a supervised restart rebinds the configured
  port, and a fixed-port test proves it beside the port-zero test. The
  free-port allocator is back for that test only: a failed start retries on a
  new port up to five times, so another process taking the released port no
  longer fails the test.
- The routing test covers `POST /other`: 404 with no `Allow` header.
- Decision 0003 marks its kwok-inventory and Dockerfile-stage bullets as amended
  by ticket 13, quoting what they originally said, and its reopen criterion names
  `kwokctl`. Decision 0007 notes where ticket 13 later removed the `kwok` pin.
- The testing reference says recovery is proven on an OS-assigned port and on a
  fixed port.
- The verification above previously claimed a full `just check` the follow-up
  had not rerun; it now refers to the run below.

`HEAD` on a known path stays 405, as the Routing clause states. The `env-check`
gap for removed pins is left to 27, above.

The fixed-port test exposed a pre-existing gap against the Recovery clause.
After the kill, the supervisor's first restart fails with `Eaddrinuse` because
the killed listener's socket is still closing; the supervisor's retry then
binds. The retry counts as a second restart, so one crash on a fixed port uses
the root's whole tolerance of two restarts in five seconds, and a second crash
in that window stops the root and, through the entrypoint, the VM. Port 8080 is
a fixed port. An experiment against the built runtime, outside the gate, killed
the listener, waited for recovery and killed it again at once: on a fixed port
the root shut down three times out of three; on port zero it survived three
times out of three. The runtime is unchanged here because this follow-up
changes no product behavior; 14 inherits the decision.

Verification: the fixed-port test passed on its first run, before the socket
filter changed, so it was never observed failing. Every run logs the
`Eaddrinuse` restart failure above, and the test passes through the
supervisor's retry; if the retry also found the socket still closing, the root
would stop and the test would fail. That did not happen in the 13 runs
observed. `POST /other` and the peername filter also passed against the
existing code. After the changes, 21 Gleam tests passed ten consecutive times,
and `just format-check` and `just build` passed. `just check-specs` and
`just analyse-specs` report no diagnostics or findings;
`just plan-spec docs/specs/knarr.allium` still reports 11 structural
obligations. `just docs-check` validated 23 pages, and all 310 checker and
process tests passed. The full `just check` passed with "All checks passed and
the worktree is unchanged."

### Plain schemas

The Kubernetes schemas were committed gzipped, with no recorded reason beyond
size, which made them the repository's only binary files. They are now the
upstream JSON, byte for byte, so a schema update is a readable diff.
`sources.json` keeps the upstream sha256 and drops the compressed one, and
`deployment.py` verifies the files in place instead of unpacking them to a
temporary directory. The upstream text has no final newline and trips the
spelling check, so the layout and spelling hooks and the fix config skip
`scripts/schemas/kubernetes/`, as they skip the vendored skills.

Verification: two new checker tests, one that the vendored schemas are plain
JSON matching their recorded sha256 and one that a changed schema is refused,
failed before the change and pass after it. `just packaging-check` and
`just deployment-check` each validated three resources with none skipped, and
the fix config left the schemas unchanged.
