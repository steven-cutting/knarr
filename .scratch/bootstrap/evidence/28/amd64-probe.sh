#!/bin/sh
# Ticket 28 evidence: whether the real linux/amd64 image can be built on the
# maintainer's arm64 host, where amd64 is emulated. Ticket 13 left this
# unverified. The Dockerfile is built as is; the expected result is a failure
# at the first step that starts the BEAM (`gleam export erlang-shipment`
# compiles a rebar3 dependency), with the prim_tty crash 13 saw. If it builds
# instead, that is recorded with the time. Either way the native number is
# CI's (ci-durations.txt); this one is labelled emulated.
# Needs docker and network for the layers not in the cache.
# Usage: sh amd64-probe.sh <empty-work-dir>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh disable=SC1091
. "$here/lib.sh"
work=${1:?usage: amd64-probe.sh <empty-work-dir>}
work=$(work_dir "$work")
root=$(cd "$here/../../../.." && pwd)
image=knarr28-amd64-probe-$(sh "$root/scripts/cluster-name.sh" "$root" name)
trap 'docker image rm -f "$image" > /dev/null 2>&1 || true' EXIT
say() { printf '%s\n' "$*"; }
printf 'date: %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)"
say "host: $(uname -sm); docker $(docker version --format '{{.Server.Version}} {{.Server.Os}}/{{.Server.Arch}}'); linux/amd64 is emulated here, so no time below is a CI number"
start=$(date +%s)
rc=0; docker build --platform linux/amd64 --tag "$image" "$root" > "$work/build.log" 2>&1 || rc=$?
secs=$(($(date +%s) - start))
cached=$(grep -c '^#[0-9]* CACHED$' "$work/build.log" || true)
if [ "$rc" -eq 0 ]; then
  say "the emulated amd64 build succeeded in $secs s ($cached cached layers): 13's prim_tty failure did not recur"
  say "arch: $(docker image inspect "$image" --format '{{.Os}}/{{.Architecture}}')"
  exit 0
fi
step=$(grep -oE '^#[0-9]+ \[build +[0-9]+/[0-9]+\] RUN .*' "$work/build.log" | tail -1 | sed -E 's/^#[0-9]+ //' | cut -c1-110)
say "the emulated amd64 build failed after $secs s ($cached cached layers) at: $step"
say 'the failure (build.log):'
grep -E "prim_tty|nif_error|Kernel pid terminated|problem when running the shell command" "$work/build.log" | sed -E "s/^#[0-9]+ [0-9.]+ +//" | sort -u | head -6 | cut -c1-200 | sed "s/^/  /"
# The kernel cannot start its user process: prim_tty:isatty/1 hits an undefined
# NIF under emulation (13, and the first run of this probe, which printed the
# ERROR REPORT; BuildKit does not always keep that stderr in the log).
grep -qE "prim_tty|failed_to_start_child,user,nouser" "$work/build.log" || fail "the build failed for a reason other than the BEAM failing to start under emulation"
say "finding: the BEAM does not start under this host's amd64 emulation (the kernel's user process fails in prim_tty), so the image is built natively in CI only (ci-durations.txt)"
