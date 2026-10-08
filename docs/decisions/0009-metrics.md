---
title: "Decision 0009: Prometheus metrics"
kind: "decision"
audience: ["maintainer", "agent"]
canonical_for: ["decision_metrics"]
requires: []
---

# Decision 0009: Prometheus metrics

## Decision

Use prometheus.erl behind a Gleam metrics module, with Erlang calls confined to
`metrics_ffi.erl`. Ticket 01 compiled prometheus 6.1.3 with the checksum-pinned
rebar3 on both supported platforms. Its mature collectors provide BEAM VM
metrics as well as application counters. Themis avoids FFI and rebar3, but its
younger implementation would require replacing the already-proven integration
and supplying VM instrumentation separately.

The skeleton exposes `knarr_startups_total`, incremented once when the
application starts. Listener recovery neither resets the counter nor registers
it again. Metrics initialize before the supervised listener accepts requests.
Prometheus owns its collectors; application routing receives collection as an
injected adapter function. Poll and patch counters arrive with those features.

## Consequences

The runtime shipment includes the prometheus OTP application and its dependencies.
rebar3 remains a build tool only. The public exposition uses Prometheus text
format, including the library's VM collectors. Tests exercise collection through
the metrics module and the HTTP boundary, including listener recovery.

Reconsider this choice if maintenance stops, collection materially affects
controller latency, or a Gleam alternative supplies equivalent instrumentation
with lower operational cost. Tool ownership remains with
[Decision 0003](0003-tool-manager.md).
