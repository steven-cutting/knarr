#!/bin/sh
# Ticket 27 evidence: Renovate itself, on the local platform, against the
# committed tree. The local platform looks up updates and stops: it creates no
# branch, no issue and no pull request (sources.txt), so the landing hold and
# the branches themselves are ticket 43's to see on the hosted app.
#
#   1. renovate-config-validator --strict on .github/renovate.json.
#   2. A lookup on an export of HEAD: every pin extracted, and what is pending
#      today.
#   3. The same on a stale copy, with real older pins put back in every managed
#      location: a hex lock, a conda pin, an action SHA, a dated noble digest,
#      an older kind node, and pixi 0.80.0 in all five places. Each manager is
#      then shown proposing an update, even where the live pin is current, and
#      in the pull request its group names.
#   4. The stale copy again with setup-pixi's native reading of pixi-version
#      switched back on: it finds the releases and proposes nothing, which is
#      why the configuration reads that input with the regex manager instead.
#      A finding either way, never a failure.
#
# Lookups reach hex.pm, conda-forge, the image registries and api.github.com.
# Renovate refuses a github.com lookup without a token, so a read-only token
# from `gh auth token` is passed to the container by name in its environment;
# the run fails if that token appears in any log. No run fails on a proposal:
# a proposal is the finding. It fails on a missing expected proposal, on any
# proposal to pin a digest (every pin already is one), on an etcd proposal
# past 3.6, and on a skipped dependency other than the two switched off on
# purpose (setup-pixi's pixi-version input and the kwok controller image),
# which must show as disabled.
# Needs docker, git, gh (authenticated) and the pixi default environment.
# Usage: sh renovate.sh <empty-work-dir>
# The gate runs shellcheck without -x, so it cannot see that lib.sh sets
# wt, py and renovate_image.
# shellcheck disable=SC2154
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh disable=SC1091
. "$here/lib.sh"
work=$(work_dir "${1:?usage: renovate.sh <empty-work-dir>}")
GITHUB_COM_TOKEN=$(gh auth token) || fail 'gh has no token; run gh auth login'
export GITHUB_COM_TOKEN
printf 'date: %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)"
printf 'revision: %s\n' "$(git -C "$wt" rev-parse --short HEAD)"
printf 'image: %s\n' "$renovate_image"

lookup() { # tree, log
  docker run --rm -v "$1:/usr/src/app" -w /usr/src/app -e GITHUB_COM_TOKEN \
    -e LOG_LEVEL=debug -e LOG_FORMAT=json "$renovate_image" --platform=local > "$2" 2>&1 ||
    fail "renovate exited non-zero; see $2"
  ! grep -qF -- "$GITHUB_COM_TOKEN" "$2" || fail "the token appears in $2"
}

echo '-- 1. renovate-config-validator --strict'
export_head "$work/head"
docker run --rm -v "$work/head:/usr/src/app:ro" -w /usr/src/app \
  --entrypoint renovate-config-validator "$renovate_image" --strict > "$work/validate.log" 2>&1 ||
  { cat "$work/validate.log"; fail 'the config does not validate'; }
sed 's/^ *//' "$work/validate.log"

echo '-- 2. HEAD: extracted, and pending today'
lookup "$work/head" "$work/head.log"

cp -R "$work/head" "$work/stale"
"$py" -I - "$work/stale" <<'EOF'
import sys
from pathlib import Path

stale = Path(sys.argv[1])
# path, the live text, the older text, how many times it appears. Each older
# value is a real release: birdie 2.0.0 on hex.pm, just 1.57.0 on conda-forge,
# actions/checkout v7.0.0's commit, ubuntu noble-20260911's index, kindest/node
# v1.35.0's index, and ghcr.io/prefix-dev/pixi 0.80.0's index.
ROLLBACKS = [
    ("gleam.toml", 'birdie = ">= 2.0.2 and < 3.0.0"', 'birdie = ">= 2.0.0 and < 3.0.0"', 1),
    ("manifest.toml", '{ name = "birdie", version = "2.0.2",', '{ name = "birdie", version = "2.0.0",', 1),
    ("manifest.toml", 'birdie = { version = ">= 2.0.2 and < 3.0.0" }', 'birdie = { version = ">= 2.0.0 and < 3.0.0" }', 1),
    ("pixi.toml", 'just = "==1.58.0"', 'just = "==1.57.0"', 1),
    (".github/workflows/ci.yml",
     "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1",
     "actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0", 3),
    ("Dockerfile",
     "ubuntu:24.04@sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55",
     "ubuntu:24.04@sha256:008173c23f95b170204355c12626cb5a965d779a7e1283b09e9cffbb1bf33ca3", 1),
    ("scripts/checks/cluster.py",
     "kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0",
     "kindest/node:v1.35.0@sha256:4613778f3cfcd10e615029370f5786704559103cf27bef934597ba562b269661", 1),
    ("pixi.toml", 'requires-pixi = ">=0.81.0"', 'requires-pixi = ">=0.80.0"', 1),
    (".github/actions/setup/action.yml", "pixi-version: v0.81.0", "pixi-version: v0.80.0", 1),
    (".github/actions/setup/action.yml", "cache-key: knarr-pixi-v0.81.0-", "cache-key: knarr-pixi-v0.80.0-", 1),
    ("Dockerfile",
     "ghcr.io/prefix-dev/pixi:0.81.0@sha256:788ae451641666e2d1f79d3dbe35392dfc7e9b394b16a3acb75c347f3badb2ab",
     "ghcr.io/prefix-dev/pixi:0.80.0@sha256:4cb073300e2c5eaee287bb3bcbadd3ddb7bce4ce36b27c41a19aad74c297c2f3", 1),
    ("README.md", "[pixi](https://pixi.sh) 0.81.0 or later", "[pixi](https://pixi.sh) 0.80.0 or later", 1),
]
for path, live, older, times in ROLLBACKS:
    file = stale / path
    text = file.read_text(encoding="utf-8")
    if text.count(live) != times:
        sys.exit(f"FAIL: {path} holds {live!r} {text.count(live)} times, want {times}; "
                 "the live pin moved, so move this rollback with it")
    file.write_text(text.replace(live, older), encoding="utf-8")
EOF
lookup "$work/stale" "$work/stale.log"

cp -R "$work/stale" "$work/native"
"$py" -I - "$work/native/.github/renovate.json" <<'EOF'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as stream:
    config = json.load(stream)
rules = config["packageRules"]
off = [r for r in rules if r.get("enabled") is False and r.get("matchPackageNames") == ["prefix-dev/pixi"]]
if len(off) != 1:
    sys.exit(f"FAIL: expected one rule switching prefix-dev/pixi off, found {len(off)}")
rules.remove(off[0])
with open(path, "w", encoding="utf-8") as stream:
    json.dump(config, stream, indent=2)
EOF
lookup "$work/native" "$work/native.log"

"$py" -I - "$work/head.log" "$work/stale.log" "$work/native.log" <<'EOF'
import json
import sys
from collections import Counter

FAILED = []
# Switched off on purpose, as (manager, dependency, depType): setup-pixi's own
# reading of the pixi version, which the regex manager reads instead, and the
# kwok controller image, which moves only by hand with kwokctl's line in
# tools.txt.
OFF = [
    ("github-actions", "prefix-dev/pixi", "uses-with"),
    ("regex", "registry.k8s.io/kwok/kwok", None),
]


def records(path):
    for line in open(path, encoding="utf-8"):
        if line.startswith("{"):
            yield json.loads(line)


def read(path):
    stats = deps = version = None
    for r in records(path):
        if r.get("msg") == "Dependency extraction complete":
            stats = r["stats"]
        if r.get("msg") == "packageFiles with updates":
            deps = [
                (manager, package_file["packageFile"], dep)
                for manager, files in r["config"].items()
                for package_file in files
                for dep in package_file["deps"]
            ]
        version = version or r.get("renovateVersion")
    if stats is None or deps is None:
        sys.exit(f"FAIL: {path} has no extraction or lookup result")
    return version, stats, deps


def proposals(deps):
    out = []
    for manager, package_file, dep in deps:
        for update in dep.get("updates", []):
            out.append((manager, package_file, dep, update))
    return out


def report(label, path):
    version, stats, deps = read(path)
    print(f"renovate {version}: {stats['total']['depCount']} dependencies in "
          f"{stats['total']['fileCount']} files")
    for manager, s in sorted(stats["managers"].items()):
        print(f"  {manager:<15} {s['depCount']:>3} in {s['fileCount']} files")
    off = []
    for m, f, d in deps:
        key = (m, d["depName"], d.get("depType"))
        if key in OFF and d.get("skipReason") == "disabled":
            off.append(f"{d['depName']} ({f})")
        elif d.get("skipReason"):
            FAILED.append(f"{label}: skipped {(m, f, d['depName'], d['skipReason'])}")
    if len(off) != len(OFF):
        FAILED.append(f"{label}: switched off {off}, want one of each of {OFF}")
    print(f"switched off, disabled: {', '.join(off)}")
    for m, f, d, u in proposals(deps):
        if d["depName"] == "registry.k8s.io/etcd" and not (u.get("newValue") or "").startswith("3.6."):
            FAILED.append(f"{label}: proposes etcd {u.get('newValue')}, past 3.6")
    pins = [(m, d["depName"]) for m, _, d, u in proposals(deps) if u.get("updateType") == "pinDigest"]
    for item in pins:
        FAILED.append(f"{label}: proposes to pin a digest for {item}")
    branches = Counter()
    for manager, package_file, dep, update in proposals(deps):
        branches[update["branchName"]] += 1
    print(f"{len(proposals(deps))} proposals in {len(branches)} branches:")
    for manager, package_file, dep, update in sorted(
        proposals(deps), key=lambda p: (p[3]["branchName"], p[0], p[1], p[2]["depName"])
    ):
        current = dep.get("currentValue") or ""
        # Whole digests and SHAs: a truncated one splits into fragments the
        # spelling check reads as words.
        if dep.get("currentDigest"):
            current += f"@{dep['currentDigest']}"
        new = update.get("newValue") or ""
        if update.get("newDigest"):
            new += f"@{update['newDigest']}"
        print(f"  {update['branchName']:<38} {update['updateType']:<6} {manager:<14} "
              f"{dep['depName']} {current} -> {new}  ({package_file})")
    return deps


report("HEAD", sys.argv[1])
print("-- 3. stale copy: real older pins in every managed location")
deps = report("stale", sys.argv[2])
# manager, file, dependency, the branch its proposal must land in, the update type
EXPECTED = [
    ("gleam", "gleam.toml", "birdie", "renovate/hex-packages", None),
    ("pixi", "pixi.toml", "just", "renovate/just-1.x", None),
    ("github-actions", ".github/workflows/ci.yml", "actions/checkout", "renovate/github-actions", None),
    ("dockerfile", "Dockerfile", "ubuntu", None, "digest"),
    ("regex", "scripts/checks/cluster.py", "kindest/node", "renovate/local-cluster", None),
    ("dockerfile", "Dockerfile", "ghcr.io/prefix-dev/pixi", "renovate/pixi", None),
    ("regex", "pixi.toml", "ghcr.io/prefix-dev/pixi", "renovate/pixi", None),
    ("regex", ".github/actions/setup/action.yml", "ghcr.io/prefix-dev/pixi", "renovate/pixi", None),
    ("regex", "README.md", "ghcr.io/prefix-dev/pixi", "renovate/pixi", None),
]
# setup-pixi's input and the cache key are both in the setup action.
TIMES = {("regex", ".github/actions/setup/action.yml"): 2}
print("-- each manager proposes from the stale copy")
for manager, package_file, name, branch, kind in EXPECTED:
    hits = [
        u for m, f, d, u in proposals(deps)
        if (m, f, d["depName"]) == (manager, package_file, name)
        and (branch is None or u["branchName"] == branch)
        and (kind is None or u["updateType"] == kind)
    ]
    where = branch or kind
    if len(hits) >= TIMES.get((manager, package_file), 1):
        print(f"  yes  {manager:<14} {name:<24} {package_file:<34} {where}")
    else:
        print(f"  NO   {manager:<14} {name:<24} {package_file:<34} {where}")
        FAILED.append(f"stale: no {where} proposal for {name} in {package_file}")
print("-- 4. setup-pixi's native reading of pixi-version, switched back on in the stale copy")
_, _, native = read(sys.argv[3])
found = [
    d for m, f, d in native
    if (m, d["depName"], d.get("depType")) == ("github-actions", "prefix-dev/pixi", "uses-with")
]
if len(found) != 1:
    FAILED.append(f"native: expected one prefix-dev/pixi pixi-version dependency, found {len(found)}")
else:
    d = found[0]
    print(f"  {d['datasource']}, versioning {d['versioning']}: current {d['currentValue']} "
          f"(released {d.get('currentVersionTimestamp', '?')[:10]}), newest release seen "
          f"{d.get('mostRecentTimestamp', '?')[:10]}, {len(d.get('updates', []))} proposals")
    if d.get("updates"):
        print("  it proposes now: the rule that switches it off can go (Decision 0014)")
    else:
        print("  it proposes nothing, so the regex manager reads this input instead")
if FAILED:
    sys.exit("FAIL:\n" + "\n".join(FAILED))
print(f"-- {len(EXPECTED)} of {len(EXPECTED)} expected proposals; no dependency skipped but "
      "the two switched off, no etcd proposal past 3.6, no digest-pin proposal, and the token "
      "in no log")
EOF
