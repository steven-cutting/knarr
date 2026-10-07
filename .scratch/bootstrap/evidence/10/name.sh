#!/bin/sh
# Ticket 10: the per-worktree cluster name and paths, derived from a worktree
# path. 13's cluster recipes reuse this scheme; name_test.sh specifies it.
#
#   name          <basename>-<8 hex>, at most 32 characters. The basename is
#                 cut to DNS-1123 label characters and 23 characters; the hash
#                 is of the physical absolute path, lower-cased, so two worktrees
#                 that share a basename differ, and a symlinked path or a path
#                 typed in another case (macOS filesystems ignore case) names
#                 the same cluster. The cost: on a case-sensitive filesystem,
#                 two directories whose paths differ only in case share a name.
#   dir           <worktree>/.cluster, all per-worktree cluster state
#   kubeconfig    <worktree>/.cluster/kubeconfig
#   kwok-workdir  <worktree>/.cluster/kwok (KWOK_WORKDIR; kwokctl's default is ~/.kwok)
#
# Usage: sh name.sh <worktree-dir> name|dir|kubeconfig|kwok-workdir
set -eu
# Byte-wise character classes, whatever the caller's locale.
export LC_ALL=C
usage='usage: name.sh <worktree-dir> name|dir|kubeconfig|kwok-workdir'
wt=${1:?$usage}
field=${2:?$usage}
abs=$(cd "$wt" && pwd -P)
sha() { if command -v sha256sum >/dev/null; then sha256sum; else shasum -a 256; fi | cut -c1-8; }
# DNS-1123 label characters: lower case, any run of other characters becomes
# one dash, no dash at either end. k3d refuses names over 32 characters (the
# tightest of kind, k3d and kwokctl), so the basename keeps 23: 23 + dash +
# 8 hex = 32.
base=$(printf '%s' "${abs##*/}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//' | cut -c1-23 | sed 's/-*$//')
# A basename with no usable character (all punctuation or non-ASCII) is "wt".
base=${base:-wt}
case $field in
  name) printf '%s-%s\n' "$base" "$(printf '%s' "$abs" | tr '[:upper:]' '[:lower:]' | sha)";;
  dir) printf '%s\n' "$abs/.cluster";;
  kubeconfig) printf '%s\n' "$abs/.cluster/kubeconfig";;
  kwok-workdir) printf '%s\n' "$abs/.cluster/kwok";;
  *) echo "$usage" >&2; exit 2;;
esac
