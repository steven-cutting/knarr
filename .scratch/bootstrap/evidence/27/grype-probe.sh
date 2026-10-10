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
#   3. The runtime environment's conda records, the packages pixi.lock's
#      runtime environment locks for linux-64, scanned as an image and as a
#      directory. Syft picks its catalogers by source, and only a directory
#      scan reads conda records, so `just image-scan` does not see the image's
#      own runtime environment (erlang, openssl, perl).
#
# grype's vulnerability database is downloaded into the work directory on
# first use (about 3 GB unpacked); part 3's image is built locally and removed.
# Needs network, docker, git, and the pixi default and audit environments
# (`just initialize`, `just audit-install`).
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

# The knarr image carries its runtime environment's conda records too. Syft,
# which grype runs to catalogue packages, picks its catalogers by source, so
# the same records are scanned as an image and as a directory: a throwaway
# FROM scratch image, built locally and removed on any exit, against that
# directory. The records are the runtime environment's packages only, not the
# whole default environment: each package pixi.lock's runtime environment
# locks for linux-64, by the default environment's record of the same name
# and version. The two environments share one solve group, so the versions
# agree; a package this host installs no record for (Linux's own libraries,
# on macOS) is named, not scanned.
echo "-- 3. the runtime environment's conda records, as an image and as a directory"
mkdir -p "$work/conda/conda-meta"
git -C "$wt" show HEAD:pixi.lock > "$work/pixi.lock"
"$py" -I - "$work/pixi.lock" "$wt/.pixi/envs/default/conda-meta" "$work/conda/conda-meta" <<'PY'
import json
import shutil
import sys
from pathlib import Path

lock, meta, out = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
lines = open(lock, encoding="utf-8").read().splitlines()
if not lines or lines[0] != "version: 7":
    sys.exit("FAIL: pixi.lock is not lock version 7, the only one this probe reads")
# Lock version 7 writes list items at their key's own indent, so the runtime
# environment's linux-64 entries sit at indent 6 under these keys.
target = ["environments:", "runtime:", "packages:", "linux-64:"]
keys, locked = [], []
for line in lines[1:]:
    text = line.strip()
    if not text:
        continue
    indent = len(line) - len(line.lstrip(" "))
    if text.startswith("- "):
        if keys == target and indent == 6:
            if not text.startswith("- conda: "):
                sys.exit(f"FAIL: a runtime entry this probe cannot read: {text}")
            archive = text.rsplit("/", 1)[-1].removesuffix(".conda").removesuffix(".tar.bz2")
            name, version, _build = archive.rsplit("-", 2)
            locked.append((name, version))
        continue
    keys = keys[: indent // 2] + [text]
if not locked:
    sys.exit("FAIL: pixi.lock locks no packages for the runtime environment on linux-64")
records = {}
for path in meta.glob("*.json"):
    record = json.loads(path.read_text(encoding="utf-8"))
    records[(record["name"], record["version"])] = path
copied = sorted(key for key in locked if key in records)
for key in copied:
    shutil.copy2(records[key], out / records[key].name)
missing = sorted(set(locked) - set(copied))
print(f"  runtime locks {len(locked)} packages for linux-64; the default environment here "
      f"holds {len(copied)} at the same version: " + ", ".join(f"{n} {v}" for n, v in copied))
if missing:
    print("  no record here, not scanned: " + ", ".join(f"{n} {v}" for n, v in missing))
if not copied:
    sys.exit("FAIL: the default environment holds none of the runtime environment's packages")
PY
printf 'FROM scratch\nCOPY conda-meta /opt/env/conda-meta\n' > "$work/conda/Dockerfile"
probe=knarr27-conda-probe-$(sh "$wt/scripts/cluster-name.sh" "$wt" name)
# A failed command or a signal still removes the probe image; on success it is
# removed below, where a failure to remove it fails the run.
trap 'docker image rm "$probe" > /dev/null 2>&1 || :' EXIT
trap 'exit 1' HUP INT TERM
docker build -q -t "$probe" "$work/conda" > /dev/null
for source in "docker:$probe" "dir:$work/conda"; do
  GRYPE_DB_AUTO_UPDATE=false "$grype" -vv "$source" -o json --file "$work/conda.json" 2> "$work/conda.log"
  "$py" -I - "$source" "$work/conda.json" "$work/conda.log" <<'PY'
import json
import re
import sys

source, scan, log = sys.argv[1:]
text = open(log, encoding="utf-8").read()
tasks = re.search(r"selected (\d+) package cataloger tasks", text)
found = re.search(r"discovered (\d+) packages cataloger=conda-meta-cataloger", text)
matches = [m for m in json.load(open(scan, encoding="utf-8"))["matches"] if m["artifact"]["type"] == "conda"]
fixed = [m for m in matches if m["vulnerability"].get("fix", {}).get("state") == "fixed"]
kind = source.split(":", 1)[0]
print(f"  {kind:<6} {tasks[1] if tasks else '?'} catalogers, conda-meta "
      f"{found[1] + ' packages' if found else 'not run'}; {len(matches)} conda matches, {len(fixed)} with a fix")
for m in sorted(fixed, key=lambda m: m["vulnerability"]["id"]):
    v, a = m["vulnerability"], m["artifact"]
    print(f"         {v['severity']:<8} {v['id']:<16} {a['name']} {a['version']} -> {', '.join(v['fix']['versions'])} ({v['namespace']})")
PY
done
docker image rm "$probe" > /dev/null
trap - EXIT
