#!/bin/sh
# Ticket 10 evidence: tests for name.sh, the per-worktree naming seam that 13's
# cluster recipes reuse. Each test builds worktree directories under a fresh
# temp dir and checks name.sh's output through its command-line interface.
# Usage: sh name_test.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
pass=0; failed=0
name() { sh "$here/name.sh" "$@"; }
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
no() { failed=$((failed + 1)); printf 'FAIL %s\n     %s\n' "$1" "$2"; }
check() { # description, actual, extended regex the whole value must match
  if printf '%s' "$2" | grep -Eqx "$3"; then ok "$1"; else no "$1" "got '$2', want /$3/"; fi
}

mkdir -p "$tmp/a/knarr"
check 'a plain basename gives <basename>-<8 hex>' "$(name "$tmp/a/knarr" name)" 'knarr-[0-9a-f]{8}'

mkdir -p "$tmp/b/knarr"
a=$(name "$tmp/a/knarr" name); b=$(name "$tmp/b/knarr" name)
if [ "$a" != "$b" ]; then ok 'two worktrees sharing a basename get different names'
else no 'two worktrees sharing a basename get different names' "both '$a'"; fi

ln -s "$tmp/a/knarr" "$tmp/link"
l=$(name "$tmp/link" name)
if [ "$l" = "$a" ]; then ok 'a symlink to a worktree names the same cluster'
else no 'a symlink to a worktree names the same cluster' "'$l' vs '$a'"; fi

# On a case-insensitive filesystem (macOS by default) one directory has many
# spellings, and pwd -P keeps the one typed.
mkdir -p "$tmp/Case/Tree"
if [ -d "$tmp/CASE/TREE" ]; then
  u=$(name "$tmp/CASE/TREE" name); m=$(name "$tmp/Case/Tree" name)
  if [ "$u" = "$m" ]; then ok 'one worktree spelled in two cases names the same cluster'
  else no 'one worktree spelled in two cases names the same cluster' "'$u' vs '$m'"; fi
else ok 'one worktree spelled in two cases names the same cluster (skipped: case-sensitive filesystem)'; fi

mkdir -p "$tmp/c/_Feature__Branch #12!.v2-"
check 'odd characters become DNS-1123: lower case, runs of others to one dash, trimmed' \
  "$(name "$tmp/c/_Feature__Branch #12!.v2-" name)" 'feature-branch-12-v2-[0-9a-f]{8}'

# k3d refuses a cluster name over 32 characters (the tightest of the three
# tools, measured in worktree.sh), so the basename keeps 23 and the hash 8.
mkdir -p "$tmp/d/abcdefghijklmnopqrstuvwxyz0123456789"
check 'a long basename is cut so the name is exactly 32 characters' \
  "$(name "$tmp/d/abcdefghijklmnopqrstuvwxyz0123456789" name)" 'abcdefghijklmnopqrstuvw-[0-9a-f]{8}'

mkdir -p "$tmp/e/aaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbb"
check 'a cut that lands on a dash leaves no double dash' \
  "$(name "$tmp/e/aaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbb" name)" 'a{22}-[0-9a-f]{8}'

mkdir -p "$tmp/f/__ö!__"
check 'a basename with nothing usable falls back to wt-<8 hex>' "$(name "$tmp/f/__ö!__" name)" 'wt-[0-9a-f]{8}'

# Every path name.sh hands out is under the worktree, so nothing a cluster
# recipe writes lands in ~/.kube or ~/.kwok.
mkdir -p "$tmp/g/my tree"
wt=$(cd "$tmp/g/my tree" && pwd -P)
for pair in "dir $wt/.cluster" "kubeconfig $wt/.cluster/kubeconfig" "kwok-workdir $wt/.cluster/kwok"; do
  field=${pair%% *}; want=${pair#* }
  got=$(name "$tmp/g/my tree" "$field")
  if [ "$got" = "$want" ]; then ok "$field is under the worktree, spaces kept"
  else no "$field is under the worktree, spaces kept" "got '$got', want '$want'"; fi
done

if name "$tmp/a/knarr" colour > /dev/null 2>&1; then no 'an unknown field exits non-zero' 'exit 0'
else ok 'an unknown field exits non-zero'; fi
if name "$tmp/no-such-dir" name > /dev/null 2>&1; then no 'a missing worktree exits non-zero' 'exit 0'
else ok 'a missing worktree exits non-zero'; fi

printf '%d passed, %d failed\n' "$pass" "$failed"
[ "$failed" -eq 0 ]
