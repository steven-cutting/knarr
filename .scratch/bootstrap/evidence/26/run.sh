#!/bin/sh
# Reproduce ticket 26 on macOS. Only ignored build/ and ai_tmp/ paths are written.
# A native Linux network-denial run remains a follow-up, not an inferred result.
set -eu
root=$(git rev-parse --show-toplevel)
cd "$root"
export PATH="$root/.pixi/envs/default/bin:$root/.tools/bin:$PATH"
export PYTHONDONTWRITEBYTECODE=1
case $(uname -s) in
  Darwin) ;;
  *) echo 'This evidence harness needs macOS sandbox-exec; see the Linux follow-up.' >&2; exit 2;;
esac
mkdir -p ai_tmp
work=$(mktemp -d "$root/ai_tmp/coverage-evidence-XXXXXX")
printf 'Evidence working directory: %s\n' "$work"
offline() {
  sandbox-exec -p '(version 1)(allow default)(deny network-outbound (remote ip))(allow network-outbound (remote ip "localhost:*"))' "$@"
}

{
  date -u +%Y-%m-%dT%H:%M:%SZ
  uname -sm
  git rev-parse HEAD
  git diff --stat
  shasum -a 256 Justfile scripts/checks/coverage.py scripts/checks/coverage_ffi.erl scripts/checks/tests/test_coverage.py
  gleam --version
  erl -noshell -eval 'io:format("~s", [erlang:system_info(system_version)]), halt().'
  offline python3 -c '
import errno
import socket
with socket.socket() as remote:
    remote.settimeout(1)
    assert remote.connect_ex(("192.0.2.1", 9)) == errno.EPERM
with socket.socket() as server, socket.socket() as client:
    server.bind(("127.0.0.1", 0))
    server.listen()
    client.connect(server.getsockname())
print("Verified: external IP connections denied with EPERM; loopback allowed")
'
} > "$work/environment.txt" 2>&1

offline /usr/bin/time -p python3 scripts/checks/run_project_check.py run coverage > "$work/coverage.txt" 2>&1
report=$(sed -n 's/^Reports: //p' "$work/coverage.txt")
test -n "$report"
cp "$report/coverage.json" "$work/coverage.json"
offline /usr/bin/time -p python3 -m pytest scripts/checks/tests/test_coverage.py -v > "$work/tests.txt" 2>&1
