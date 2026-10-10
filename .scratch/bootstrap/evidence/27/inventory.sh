#!/bin/sh
# Ticket 27 evidence: every pin in the committed tree, counted from the files
# themselves rather than from Renovate, with what covers it after 27 or the gap
# Decision 0013 records. renovate.sh shows the same pins as Renovate extracts
# them; the two counts are compared there, not here.
# Offline. Needs git and the pixi default environment.
# Usage: sh inventory.sh <empty-work-dir>
# The gate runs shellcheck without -x, so it cannot see that lib.sh sets
# wt and py.
# shellcheck disable=SC2154
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh disable=SC1091
. "$here/lib.sh"
work=$(work_dir "${1:?usage: inventory.sh <empty-work-dir>}")
export_head "$work/tree"
printf 'revision: %s\n' "$(git -C "$wt" rev-parse --short HEAD)"
"$py" -I - "$work/tree" <<'EOF'
import json
import re
import sys
import tomllib
from pathlib import Path

tree = Path(sys.argv[1])


def text(path):
    return (tree / path).read_text(encoding="utf-8")


def count(pattern, *paths):
    return sum(len(re.findall(pattern, text(p), re.MULTILINE)) for p in paths)


workflows = sorted(str(p.relative_to(tree)) for p in (tree / ".github").rglob("*.yml"))
workflows = [p for p in workflows if "/workflows/" in p or p.endswith("/action.yml")]
pixi = tomllib.loads(text("pixi.toml"))
conda_pins = {
    "default": pixi["dependencies"],
    **{f"feature {name}": f["dependencies"] for name, f in pixi["feature"].items()},
}
exact = sum(1 for pins in conda_pins.values() for v in pins.values() if v.startswith("=="))
locked = len(set(re.findall(r"^- conda: (\S+)$", text("pixi.lock"), re.MULTILINE)))
manifest = tomllib.loads(text("manifest.toml"))
gleam = tomllib.loads(text("gleam.toml"))
hooks = re.findall(r"^\s*- repo: (\S+)", text(".pre-commit-config.yaml") + text(".pre-commit-fix.yaml"), re.MULTILINE)
remote_hooks = [h for h in hooks if h not in {"local", "builtin", "meta"}]
schemas = json.loads(text("scripts/schemas/kubernetes/sources.json"))["files"]
skills = json.loads(text("skills-lock.json"))["skills"]
tools = [line.split() for line in text("tools.txt").splitlines() if line and not line.startswith("#")]
pixi_sites = (
    count(r'^requires-pixi = ">=\S+"$', "pixi.toml")
    + count(r"^\s+pixi-version: v\S+$", ".github/actions/setup/action.yml")
    + count(r"^\s+cache-key: knarr-pixi-v\S+-$", ".github/actions/setup/action.yml")
    + count(r"^FROM ghcr\.io/prefix-dev/pixi:", "Dockerfile")
    + count(r"\[pixi\]\(https://pixi\.sh\) \S+ or later", "README.md")
)
kwok_image = count(r'"registry\.k8s\.io/kwok/kwok:[^"\s]+@sha256:[0-9a-f]{64}"', "scripts/checks/cluster.py")
rows = [
    ("hex package range", "gleam.toml", len(gleam["dependencies"]) + len(gleam["dev-dependencies"]), "renovate gleam (hex), group hex packages"),
    ("hex package lock", "manifest.toml", sum(1 for p in manifest["packages"] if p.get("source") == "hex"), "renovate gleam: update-lockfile, lockFileMaintenance"),
    ("conda pin (==)", "pixi.toml", exact, "renovate pixi, held for approval"),
    ("conda package lock", "pixi.lock", locked, "renovate pixi lockFileMaintenance, held; hosted relock unproven (41)"),
    ("action SHA", ", ".join(workflows), count(r"uses: [\w.-]+/[\w./-]+@[0-9a-f]{40} # v", *workflows), "renovate github-actions, group GitHub Actions"),
    ("runner label", ", ".join(w for w in workflows if "/workflows/" in w), count(r"^\s+runs-on: ubuntu-\S+$", *workflows), "renovate github-actions (github-runners), group GitHub Actions"),
    ("prek remote hook rev", ".pre-commit-config.yaml, .pre-commit-fix.yaml", len(remote_hooks), f"none to cover: {len(hooks)} repos, all local or builtin"),
    ("base image digest", "Dockerfile FROM", count(r"^FROM \S+@sha256:[0-9a-f]{64}", "Dockerfile"), "renovate dockerfile, docker:pinDigests"),
    ("cluster image digest", "scripts/checks/cluster.py", count(r'"[^"\s]+@sha256:[0-9a-f]{64}"', "scripts/checks/cluster.py") - kwok_image, "renovate regex (docker), group local cluster, held"),
    ("kwok image digest", "scripts/checks/cluster.py", kwok_image, "gap: manual, with kwokctl's tools.txt lines; renovate has it disabled"),
    ("pixi version", "pixi.toml, setup action (2), Dockerfile, README.md", pixi_sites, "renovate: setup-pixi input, dockerfile, regex; group pixi, held"),
    ("tools.txt sha256", "tools.txt", len(tools), f"gap: manual; {len({t[0] for t in tools})} tools on 2 platforms, no bot rehashes a download"),
    ("rebar3 ADD --checksum", "Dockerfile", count(r"^ADD --checksum=sha256:[0-9a-f]{64} ", "Dockerfile"), "gap: manual, with tools.txt's rebar3 line (test_image.py)"),
    ("Kubernetes schema sha256", "scripts/schemas/kubernetes/sources.json", len(schemas), "gap: manual, re-vendored with its sources.json"),
    ("vendored skill hash", "skills-lock.json", len(skills), "gap: manual, re-vendored from the tag the lock names"),
]
width = max(len(r[0]) for r in rows)
for pin, where, n, coverage in rows:
    print(f"{pin:<{width}}  {n:>3}  {coverage}")
    print(f"{'':<{width}}       in {where}")
print(f"-- {sum(r[2] for r in rows)} pins in {len(rows)} kinds; "
      f"{sum(r[2] for r in rows if r[3].startswith('gap'))} in the {sum(1 for r in rows if r[3].startswith('gap'))} manual kinds")
EOF
