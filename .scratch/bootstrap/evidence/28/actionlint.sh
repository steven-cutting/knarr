#!/bin/sh
# Ticket 28 evidence: the drafted release workflow passes actionlint, with
# ShellCheck on its run blocks, as it would under .github/workflows/. It is
# linted here by explicit path: the prek hook's file filter only matches
# .github/workflows/, so nothing under evidence ever runs or is linted on its
# own. Offline.
# Needs actionlint and shellcheck from the pixi default environment.
# Usage: sh actionlint.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
PATH=$root/.pixi/envs/default/bin:$PATH
printf 'date: %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)"
printf 'actionlint %s, shellcheck %s\n' "$(actionlint -version | head -1)" "$(shellcheck --version | sed -n 's/^version: //p')"
actionlint -no-color -shellcheck "$(command -v shellcheck)" "$here/release.yml"
echo 'release.yml: no findings'
grep -c 'Authorization required' "$here/release.yml" | sed 's/^/"Authorization required" marks in release.yml: /'
printf 'permissions at the top level: %s\n' "$(grep -E '^permissions:' "$here/release.yml")"
printf 'triggers: %s\n' "$(sed -n '/^on:/,/^permissions:/p' "$here/release.yml" | grep -E '^ +- ' | tr -d ' ' | tr '\n' ' ')"
uses=$(grep -E '^ +- uses: ' "$here/release.yml" | sed 's/^ *- uses: //')
unpinned=$(printf '%s\n' "$uses" | grep -vE '@[0-9a-f]{40} # v[0-9]+\.[0-9]+\.[0-9]+$' || true)
[ -z "$unpinned" ] || { printf 'not pinned to a full commit SHA with a version comment:\n%s\n' "$unpinned" >&2; exit 1; }
printf 'every action (%s uses) is pinned to a full commit SHA with a version comment: %s\n' "$(printf '%s\n' "$uses" | wc -l | tr -d ' ')" "$(printf '%s\n' "$uses" | sort -u | tr '\n' ' ')"
