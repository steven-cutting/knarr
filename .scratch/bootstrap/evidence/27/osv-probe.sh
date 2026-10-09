#!/bin/sh
# Ticket 27 evidence: the hex advisory source, live. The committed
# scripts/checks/hex_audit.py runs three times against api.osv.dev:
#
#   1. on the committed tree: the verdict `just hex-audit` gives today (exit 0
#      or 1 are both findings; 2, cannot decide, fails the run);
#   2. on a control whose manifest.toml locks plug 1.3.0, which GitHub's
#      advisories for the erlang ecosystem list as vulnerable
#      (GHSA-2q6v-32mr-8p8x): it must exit 1 and name that advisory;
#   3. on the committed manifest with the erlang pin moved back to 27.3.2,
#      the release CVE-2025-32433 was fixed after: it must exit 1 and name it.
#
# Then OSV's own record of CVE-2025-32433, to show it is a GIT entry for
# github.com/erlang/otp, which is why the audit asks for an OTP tag there.
# Needs network, curl, git and the pixi default environment.
# Usage: sh osv-probe.sh <empty-work-dir>
# The gate runs shellcheck without -x, so it cannot see that lib.sh sets
# wt and py.
# shellcheck disable=SC2154
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh disable=SC1091
. "$here/lib.sh"
work=$(work_dir "${1:?usage: osv-probe.sh <empty-work-dir>}")
printf 'date: %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)"
printf 'revision: %s\n' "$(git -C "$wt" rev-parse --short HEAD)"
export_head "$work/head"
audit="$work/head/scripts/checks/hex_audit.py"

run() { # label, project: prints the audit's output and sets rc
  echo "-- $1"
  set +e
  "$py" -I "$audit" "$2" > "$work/out" 2>&1
  rc=$?
  set -e
  sed 's/^/  /' "$work/out"
  echo "  exit $rc"
}

run '1. the committed tree' "$work/head"
[ "$rc" != 2 ] || fail 'the audit could not decide on the committed tree'

mkdir "$work/hex-control"
cp "$work/head/pixi.toml" "$work/hex-control/"
cat > "$work/hex-control/manifest.toml" <<'EOF'
packages = [
  { name = "plug", version = "1.3.0", build_tools = ["mix"], requirements = [], otp_app = "plug", source = "hex", outer_checksum = "0" },
]
EOF
run '2. control: plug 1.3.0 locked from hex' "$work/hex-control"
[ "$rc" = 1 ] || fail "the hex control exited $rc, want 1"
grep -q '^GHSA-2q6v-32mr-8p8x  plug 1.3.0 ' "$work/out" || fail 'the hex control does not name GHSA-2q6v-32mr-8p8x'

mkdir "$work/otp-control"
cp "$work/head/manifest.toml" "$work/otp-control/"
sed 's/^erlang = "==[^"]*"$/erlang = "==27.3.2"/' "$work/head/pixi.toml" > "$work/otp-control/pixi.toml"
grep -q '^erlang = "==27.3.2"$' "$work/otp-control/pixi.toml" || fail 'could not move the erlang pin'
run '3. control: the committed manifest with erlang ==27.3.2' "$work/otp-control"
[ "$rc" = 1 ] || fail "the OTP control exited $rc, want 1"
grep -q '^CVE-2025-32433  Erlang/OTP 27.3.2 ' "$work/out" || fail 'the OTP control does not name CVE-2025-32433'

echo '-- 4. OSV.dev record CVE-2025-32433'
curl -sS --max-time 60 -o "$work/record.json" https://api.osv.dev/v1/vulns/CVE-2025-32433
"$py" -I - "$work/record.json" <<'EOF'
import json
import sys

record = json.load(open(sys.argv[1], encoding="utf-8"))
print(f"  {record['id']}: {record.get('summary') or record.get('details', '')[:90]}")
for affected in record.get("affected", []):
    for r in affected.get("ranges", []):
        events = ", ".join(f"{k} {v[:12]}" for e in r.get("events", []) for k, v in e.items())
        print(f"  {r['type']} {r.get('repo', affected.get('package', {}).get('name', ''))}: {events}")
if not any(r["type"] == "GIT" and "github.com/erlang/otp" in r.get("repo", "")
           for a in record.get("affected", []) for r in a.get("ranges", [])):
    sys.exit("FAIL: no GIT range for github.com/erlang/otp")
EOF
