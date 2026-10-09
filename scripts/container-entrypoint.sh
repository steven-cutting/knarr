#!/bin/bash
# kind/containerd can inherit a near-unlimited descriptor ceiling. Bound the
# soft limit before Erlang allocates its descriptor tables; preserve lower caps.
set -eu
limit=$(ulimit -Sn)
if [ "$limit" = unlimited ] || [ "$limit" -gt 65536 ]; then
    ulimit -Sn 65536
fi
exec "$@"
