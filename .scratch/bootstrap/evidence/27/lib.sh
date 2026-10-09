# Ticket 27 evidence: helpers sourced by every script, so all of them use one
# set of rules. Not run on its own.
#
#   wt                  the worktree this directory sits in
#   py                  the pixi default environment's python3
#   renovate_image      the Renovate image every run uses, pinned by digest
#   work_dir <path>     creates it, refuses a non-empty one, prints the
#                       absolute path
#   export_head <dir>   the committed tree at HEAD, unpacked into <dir>
#   sha256_of           stdin, the hex digest
#   fail <message>      FAIL: <message> to stderr, exit 1

# This file is sourced, so it has no shebang.
# shellcheck shell=sh

here=${here:?set here before sourcing lib.sh}
wt=$(cd "$here/../../../.." && pwd)
py=$wt/.pixi/envs/default/bin/python3
# 44.149.0 was the newest release on 2026-10-09; the digest is its OCI index.
# shellcheck disable=SC2034  # read by the scripts that source this file
renovate_image='ghcr.io/renovatebot/renovate:44.149.0@sha256:33e1ce773404122fd3bcf1dca6ce9b5638a080da68a8972ad942d4d991cec464'

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
work_dir() { # path: the scripts' one work-directory rule
  mkdir -p "$1"
  wd=$(cd "$1" && pwd)
  [ -z "$(ls -A "$wd")" ] || { echo "work dir $wd is not empty" >&2; exit 2; }
  printf '%s\n' "$wd"
}
export_head() { # dir
  mkdir -p "$1"
  git -C "$wt" archive HEAD | tar -x -C "$1"
}
sha256_of() { if command -v sha256sum > /dev/null; then sha256sum; else shasum -a 256; fi | cut -d' ' -f1; }
[ -x "$py" ] || fail "$py is missing; run just initialize"
