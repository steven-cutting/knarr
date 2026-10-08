#!/bin/sh
# Run glinter, failing where it would pass without having linted everything.
# glinter 2.19.2 skips a file it cannot read or parse, a directory it cannot
# read, and a gleam.toml it cannot parse (then linting with its defaults). It
# reports each on stderr with an `Error: ` or `Warning: ` prefix and still exits
# 0. This wrapper keeps glinter's status and output, and fails on any such line.
# gleam's own diagnostics are lower case (`error: `) and keep their status.
#
# gleam resolves from PATH: `just lint-gleam` puts the pinned one first, as
# every recipe does. Arguments pass through to glinter.
# Usage: sh scripts/checks/run_glinter.sh [glinter argument...]
set -u
command -v gleam > /dev/null 2>&1 || { echo 'gleam is unavailable; run just initialize' >&2; exit 2; }
# stdout goes straight through on descriptor 3; stderr is captured, then
# printed after it.
exec 3>&1
errors=$(gleam run --no-print-progress -m glinter "$@" 2>&1 1>&3 3>&-)
status=$?
exec 3>&-
[ -z "$errors" ] || printf '%s\n' "$errors" >&2
if printf '%s\n' "$errors" | grep -Eq '^(Error|Warning): '; then
  echo 'glinter skipped input it could not read or parse (above); failing instead of passing' >&2
  [ "$status" -ne 0 ] || status=1
fi
exit "$status"
