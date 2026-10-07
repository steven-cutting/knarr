#!/bin/sh
# Ticket 02 evidence: the provenance of every file 0004 copies, rewrites or
# drops. Reads a local clone of biscuit_games_tooling and prints the commit
# behind tag v0.3.0, what changed after it, the licence evidence, and each
# source file's sha256 and line count at that commit. Exits non-zero if the tag
# has moved, anything under src/ changed after it, a licence appears, or a
# source file is missing.
# Usage: sh provenance.sh <biscuit_games_tooling-clone> > provenance.txt 2>&1
set -eu
clone=${1:?usage: provenance.sh <biscuit_games_tooling-clone>}
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }
sha() { if command -v sha256sum > /dev/null; then sha256sum; else shasum -a 256; fi | cut -d' ' -f1; }
g() { git -C "$clone" "$@"; }
tag=v0.3.0 want=6c5c07f6bec86e86b3930dfa41392e4b440e8c85
printf 'date: %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)"
# Read-only: the clone is never fetched into. ls-remote proves that the local
# tag and origin/main are what the remote has now.
printf 'repository: %s\n' "$(g remote get-url origin)"
commit=$(g rev-parse "$tag^{commit}")
[ "$commit" = "$want" ] || fail "$tag is $commit, not $want"
remote_tag=$(g ls-remote origin "refs/tags/$tag^{}" | cut -f1)
[ -n "$remote_tag" ] || remote_tag=$(g ls-remote origin "refs/tags/$tag" | cut -f1)
[ "$remote_tag" = "$want" ] || fail "the remote's $tag is $remote_tag, not $want"
printf 'tag %s: commit %s (%s), same on the remote\n' "$tag" "$commit" "$(g log -1 --format=%cs "$commit")"
main=$(g ls-remote origin refs/heads/main | cut -f1)
[ "$main" = "$(g rev-parse origin/main)" ] || fail "the clone's origin/main is stale; fetch it first"
printf 'origin/main: %s\n' "$main"
echo
echo "== files changed between $tag and origin/main"
g diff --name-only "$tag" origin/main
g diff --name-only "$tag" origin/main -- src | grep . && fail "src changed after $tag" || echo '(nothing under src/)'
echo
echo "== licence at $tag"
if g ls-tree -r --name-only "$tag" | grep -iE '(^|/)(licen[cs]e|notice|copying)' ; then
  fail "a licence file exists at $tag; 0004's grant assumed none"
else
  echo 'no LICENSE, NOTICE or COPYING file in the tree'
fi
if g show "$tag:pyproject.toml" | grep -iE '^license' ; then fail "pyproject.toml declares a licence at $tag"; else echo 'pyproject.toml declares no license field'; fi
echo
echo "== source files at $tag (sha256 of the blob content, lines)"
for f in _project run_project_check validate_docs validate_agents install_allium run_allium run_ripsecrets_redacted; do
  p=src/biscuit_games_tooling/$f.py
  g cat-file -e "$tag:$p" || fail "$p missing at $tag"
  printf '%s  %4s  %s\n' "$(g show "$tag:$p" | sha)" "$(g show "$tag:$p" | wc -l | tr -d ' ')" "$p"
done
