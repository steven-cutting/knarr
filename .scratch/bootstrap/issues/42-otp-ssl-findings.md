# 42: OTP and ssl findings from spike S1

**Context:** Spike S1 ([14](14-spike-s1-in-cluster-client.md)) recorded behaviour of OTP 29's `ssl`, `httpc` and runtime that is not knarr behaviour but that a later change could trip over. [Decision 0013](../../../docs/decisions/0013-in-cluster-client.md) names them; this ticket is where each is either closed as accepted or turned into a code or documentation change.

**What to build:** A short note per finding under `docs/reference/` or in the owning decision record, each with a decision: keep as is, change the code, or watch the OTP pin.

**Non-goals:** Changing the OTP pin (ticket 27). Any client behaviour (ticket 41).

**Blocked by:** 14

**MVP critical path:** no.

**Status:** ready-for-agent

- [ ] **IP-literal SNI.** With a string IP host, OTP 29 sends `server_name` carrying the IP, which RFC 6066 says a client should not. The apiserver tolerates it (the `cluster-s1` job). Decide whether to pass `{server_name_indication, disable}` once OTP separates it from the hostname check, or to keep the default and say so in 0013.
- [ ] **Rosetta needs `+JMsingle true`.** The amd64 OTP 29 runtime fails in `prim_tty` under OrbStack's Rosetta unless the JIT maps code single-mapped ([emulation.txt](../evidence/14/emulation.txt)). Decide whether the local cluster guide documents the flag as a pod env var for ARM hosts, given the image still cannot be built there.
- [ ] **httpc error shapes.** `k8s_http_ffi` maps `{failed_connect, [...]}` by position. Record the shapes from [tls.txt](../evidence/14/tls.txt) in the testing reference so a pin move that changes them is found by the loopback test and understood from the page.
- [ ] **`pkix_test_data/1` returns the root twice in `cacerts`** for a chain with no intermediate; the test FFI deduplicates. Note it beside the loopback test.
- [ ] **gleam_otp actors do not answer `gen_server:stop`.** The actor loop handles get_state, suspend, resume and status but not the `terminate` system message, so `gen_server:stop` on a bare actor waits for its timeout; a supervisor's `exit(Pid, shutdown)` works. The probe test stops the bare actor with an exit signal for that reason. Decide whether this is a note in the testing reference or an upstream report.
