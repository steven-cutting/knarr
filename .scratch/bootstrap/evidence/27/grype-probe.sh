#!/bin/sh
# Ticket 27 evidence: grype, from the pixi audit environment, on the image the
# runtime stage starts from: the Dockerfile's pinned ubuntu:24.04 index, its
# linux/amd64 manifest, read straight from the registry. The knarr image itself
# is built on amd64 in CI only (Decision 0012), so the branch's audit.yml run
# (ci-audit.txt) is the scan of the real image; this shows the base it adds
# to, and what `just image-scan`'s flags decide.
#
#   1. Every match, by severity, and those with a fix.
#   2. The recipe's flags, --only-fixed --fail-on high: exit 0 passes, exit 2
#      is grype's "a fixed vulnerability at or above high", a finding the audit
#      reports. Any other exit fails the run.
#
# grype's vulnerability database is downloaded into the work directory on
# first use (about 3 GB unpacked), so nothing is written outside it.
# Needs network, git, and the pixi audit environment (`just audit-install`).
# Usage: sh grype-probe.sh <empty-work-dir>
# The gate runs shellcheck without -x, so it cannot see that lib.sh sets
# wt and py.
# shellcheck disable=SC2154
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh disable=SC1091
. "$here/lib.sh"
work=$(work_dir "${1:?usage: grype-probe.sh <empty-work-dir>}")
grype=$wt/.pixi/envs/audit/bin/grype
[ -x "$grype" ] || fail "$grype is missing; run just audit-install"
GRYPE_DB_CACHE_DIR=$work/db
export GRYPE_DB_CACHE_DIR
printf 'date: %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)"
printf 'revision: %s\n' "$(git -C "$wt" rev-parse --short HEAD)"
"$grype" version | grep -E '^(Version|Syft Version|Supported DB Schema):' | sed 's/:  */: /'
base=$(git -C "$wt" show HEAD:Dockerfile | sed -n 's/^FROM \(ubuntu:[^ ]*\) AS runtime$/\1/p')
[ -n "$base" ] || fail 'the Dockerfile has no ubuntu runtime stage'
printf 'image: registry:%s, linux/amd64\n' "$base"

echo '-- 1. every match'
"$grype" -q "registry:$base" --platform linux/amd64 -o json --file "$work/scan.json"
"$py" -I - "$work/scan.json" <<'EOF'
import json
import sys
from collections import Counter

scan = json.load(open(sys.argv[1], encoding="utf-8"))
db = scan["descriptor"]["db"]["status"]
print(f"database: schema {db['schemaVersion']}, built {db['built']}")
print(f"source: {scan['source']['target']['userInput']}")
print(f"  amd64 manifest {scan['source']['target']['manifestDigest']}, "
      f"distro {scan['distro']['name']} {scan['distro']['version']}")
order = ["Critical", "High", "Medium", "Low", "Negligible", "Unknown"]
matches = scan["matches"]
counts = Counter(m["vulnerability"]["severity"] for m in matches)
fixed = [m for m in matches if m["vulnerability"].get("fix", {}).get("state") == "fixed"]
fixed_counts = Counter(m["vulnerability"]["severity"] for m in fixed)
print(f"{len(matches)} matches: " + ", ".join(f"{counts[s]} {s}" for s in order if counts[s]))
print(f"{len(fixed)} with a fix: " + ", ".join(f"{fixed_counts[s]} {s}" for s in order if fixed_counts[s]))
for m in sorted(fixed, key=lambda m: (order.index(m["vulnerability"]["severity"]), m["vulnerability"]["id"])):
    v, a = m["vulnerability"], m["artifact"]
    print(f"  {v['severity']:<8} {v['id']:<16} {a['name']} {a['version']} -> {', '.join(v['fix']['versions'])}")
EOF

echo "-- 2. just image-scan's flags: --only-fixed --fail-on high"
set +e
"$grype" -q "registry:$base" --platform linux/amd64 --only-fixed --fail-on high -o table > "$work/table.txt" 2>&1
rc=$?
set -e
sed 's/^/  /' "$work/table.txt"
case $rc in
  0) echo 'exit 0: no fixed vulnerability at or above high; the scan passes' ;;
  2) echo 'exit 2: a fixed vulnerability at or above high; the audit job reports it' ;;
  *) fail "grype exited $rc" ;;
esac
