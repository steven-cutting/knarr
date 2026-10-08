#!/bin/sh
# Ticket 08 evidence: how birdie behaves in the read-only gate. birdie has no
# check mode and writes <title>.new whenever a snapshot is new or changed. In a
# throwaway clone of the committed branch, this shows that the gate then fails
# at `just test` without changing anything Git can see, that `just
# snapshots-check` fails on the pending .new and on a stale snapshot, that
# `just snapshots-accept` restores the committed file, where the referenced
# list lives, and the glinter fail-open that scripts/checks/run_glinter.sh
# closes.
# The clone borrows this checkout's .pixi and .tools (symlinked) and a copy of
# build/packages, so it needs no network; every just command runs with outbound
# network denied (sandbox-exec on macOS, unshare on Linux). It writes only to
# the work directory, and reads the checkout without changing it.
# Exits non-zero on any unexpected result.
# Usage: sh birdie-check.sh <empty-work-dir> > birdie-check.txt 2>&1
set -eu
work=${1:?usage: birdie-check.sh <empty-work-dir>}
mkdir -p "$work"; work=$(cd "$work" && pwd)
[ -z "$(ls -A "$work")" ] || { echo "work dir $work is not empty" >&2; exit 2; }
source=$(cd "$(dirname "$0")" && git rev-parse --show-toplevel)
branch=$(git -C "$source" rev-parse --abbrev-ref HEAD)
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }
offline() { # run a command with outbound network denied
  case $(uname -s) in
    Darwin) sandbox-exec -p '(version 1)(allow default)(deny network-outbound (remote ip))' "$@" ;;
    Linux) unshare -rn "$@" ;;
    *) fail "no offline runner for $(uname -s)" ;;
  esac
}
esc=$(printf '\033')
plain() { sed "s/$esc\[[0-9;]*m//g"; } # strip colour codes from a log
show() { plain < "$1" | grep -E "$2" | sed 's/^/     /'; }
run() { # run <log> <just argument...>: output to <work>/<log>, exit status in rc
  log=$work/$1; shift
  set +e; offline "$clone/.pixi/envs/default/bin/just" "$@" > "$log" 2>&1; rc=$?; set -e
}
porcelain() { git status --porcelain --untracked-files=all; }
clean() { [ -z "$(porcelain)" ] || { porcelain; fail "$1: worktree not clean"; }; }

snapshots=test/birdie_snapshots
accepted=$snapshots/version_request_sent_by_fetch_version.accepted
new=$snapshots/version_request_sent_by_fetch_version.new
title='version request sent by fetch_version'

# Lists that a run outside this clone would have written instead: this
# checkout's own, and the shared one in the system's temporary directory.
untouched() { [ -z "$(find "$1" -newer "$work/started" 2> /dev/null)" ] || fail "$1 changed during the run"; }
touch "$work/started"

clone=$work/clone
git clone -q --branch "$branch" --single-branch "$source" "$clone"
cd "$clone"
printf 'date: %s\nhost: %s\ncommit: %s (%s)\n\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$(uname -sm)" \
  "$(git rev-parse --short HEAD)" "$branch"

echo '== setup: the clone borrows this checkout'"'"'s tools'
[ -x "$source/.pixi/envs/default/bin/just" ] || fail "$source has no pixi environment; run just initialize there"
[ -d "$source/build/packages" ] || fail "$source has no build/packages; run just initialize there"
ln -s "$source/.pixi" .pixi
ln -s "$source/.tools" .tools
mkdir build && cp -R "$source/build/packages" build/packages
# .gitignore names .pixi/ and .tools/ as directories; these are symlinks.
printf '%s\n' .pixi .tools >> .git/info/exclude
clean 'after setup'
echo 'ok   .pixi and .tools symlinked, build/packages copied; the worktree is clean'
if offline curl -fsS --max-time 10 -o /dev/null https://github.com > /dev/null 2>&1; then fail 'curl reached github.com inside the sandbox'; fi
echo 'ok   curl https://github.com fails inside the sandbox every just command runs in'

echo; echo '== baseline: just check passes'
run check.log check
[ "$rc" -eq 0 ] || { plain < "$work/check.log"; fail 'the baseline just check failed'; }
show "$work/check.log" '^==> just (lint-gleam|test|snapshots-check)$|^All checks'
clean 'after the baseline gate'
echo 'ok   just check passed offline; the worktree is unchanged'

echo; echo '== a changed snapshot: one character of the accepted file'
sed 's/^accept: application\/json$/accept: application\/jsom/' "$accepted" > "$work/edited" && cp "$work/edited" "$accepted"
grep -q 'application/jsom' "$accepted" || fail 'the edit did not apply'
run changed.log check
[ "$rc" -ne 0 ] || fail 'just check passed with a changed snapshot'
last=$(plain < "$work/changed.log" | grep '^==> ' | tail -1)
[ "$last" = '==> just test' ] || fail "the gate stopped at '$last', not at just test"
plain < "$work/changed.log" | grep -q "title: $title" || { plain < "$work/changed.log"; fail 'the failure did not name the snapshot'; }
if grep -q 'changed the worktree' "$work/changed.log"; then fail 'the runner reported a worktree change'; fi
printf 'ok   just check exit %s, stopped at just test, naming the snapshot:\n' "$rc"
show "$work/changed.log" '^==> |title:|application/jso|passed|failures'
[ "$(porcelain)" = " M $accepted" ] || { porcelain; fail 'Git sees more than the deliberate edit'; }
printf 'ok   git status --untracked-files=all shows only the deliberate edit: %s\n' "$(porcelain)"
git status --porcelain --ignored "$snapshots" | grep -qx "!! $new" || fail 'no ignored .new'
printf 'ok   git status --ignored shows the .new as ignored: !! %s\n' "$new"

run pending.log snapshots-check
[ "$rc" -ne 0 ] || fail 'snapshots-check passed with a pending .new'
grep -qx "$new" "$work/pending.log" || { plain < "$work/pending.log"; fail 'snapshots-check did not name the .new'; }
printf 'ok   just snapshots-check exit %s, naming the pending .new:\n' "$rc"
show "$work/pending.log" "^$new\$|^pending snapshots"

run accept.log snapshots-accept
[ "$rc" -eq 0 ] || { plain < "$work/accept.log"; fail 'snapshots-accept failed'; }
git diff --quiet || { git diff; fail 'accepting did not restore the committed file'; }
[ ! -e "$new" ] || fail 'a .new remains after accepting'
clean 'after accepting the changed snapshot'
echo 'ok   just snapshots-accept restored the committed file: git diff is empty and no .new remains'
show "$work/accept.log" 'Accepting|Done'

echo; echo '== a new snapshot: the accepted file deleted'
rm "$accepted"
run created.log check
[ "$rc" -ne 0 ] || fail 'just check passed with a new snapshot'
last=$(plain < "$work/created.log" | grep '^==> ' | tail -1)
[ "$last" = '==> just test' ] || fail "the gate stopped at '$last', not at just test"
plain < "$work/created.log" | grep -q 'new snapshot' || { plain < "$work/created.log"; fail 'no new-snapshot report'; }
plain < "$work/created.log" | grep -q "title: $title" || fail 'the failure did not name the snapshot'
if grep -q 'changed the worktree' "$work/created.log"; then fail 'the runner reported a worktree change'; fi
printf 'ok   just check exit %s, stopped at just test, naming the snapshot:\n' "$rc"
show "$work/created.log" '^==> |new snapshot|title:|passed|failures'
[ "$(porcelain)" = " D $accepted" ] || { porcelain; fail 'Git sees more than the deletion'; }
git status --porcelain --ignored "$snapshots" | grep -qx "!! $new" || fail 'no ignored .new'
printf 'ok   Git sees only the deletion (%s); the .new is ignored\n' "$(porcelain)"
run created-pending.log snapshots-check
[ "$rc" -ne 0 ] || fail 'snapshots-check passed with a pending .new'
grep -qx "$new" "$work/created-pending.log" || fail 'snapshots-check did not name the .new'
printf 'ok   just snapshots-check exit %s, naming the pending .new\n' "$rc"
run created-accept.log snapshots-accept
[ "$rc" -eq 0 ] || { plain < "$work/created-accept.log"; fail 'snapshots-accept failed'; }
git diff --quiet || { git diff; fail 'accepting did not restore the committed file'; }
[ ! -e "$new" ] || fail 'a .new remains after accepting'
clean 'after accepting the new snapshot'
echo 'ok   just snapshots-accept restored the committed file: git diff is empty and no .new remains'

echo; echo '== a stale snapshot: an accepted file no test refers to'
printf '%s\n' '---' 'version: 2.0.2' 'title: orphan' '---' 'no test refers to this' > "$snapshots/orphan.accepted"
run orphan-test.log test
[ "$rc" -eq 0 ] || { plain < "$work/orphan-test.log"; fail 'just test failed with an orphan'; }
echo 'ok   just test passes with the orphan present'
show "$work/orphan-test.log" 'passed'
run orphan-check.log snapshots-check
[ "$rc" -ne 0 ] || fail 'snapshots-check passed with a stale snapshot'
plain < "$work/orphan-check.log" | grep -qx '  - orphan' || { plain < "$work/orphan-check.log"; fail 'snapshots-check did not name the orphan'; }
printf 'ok   just snapshots-check exit %s, naming it:\n' "$rc"
show "$work/orphan-check.log" 'stale|^  - '
run orphan-stale.log snapshots-stale
plain < "$work/orphan-stale.log" | grep -qx '  - orphan' || { plain < "$work/orphan-stale.log"; fail 'snapshots-stale did not list the orphan'; }
printf 'ok   just snapshots-stale (exit %s) lists it\n' "$rc"

echo; echo '== the referenced list is per worktree'
referenced=build/birdie/knarr_referenced.txt
[ -f "$referenced" ] || fail "no $referenced"
grep -qx 'version_request_sent_by_fetch_version.accepted' "$referenced" || fail "$referenced does not list the snapshot"
printf 'ok   just test wrote %s, inside this clone:\n' "$referenced"
sed 's/^/     /' "$referenced"
untouched "$source/build/birdie/knarr_referenced.txt"
untouched "${TMPDIR:-/tmp}/knarr_referenced.txt"
echo 'ok   neither this checkout'"'"'s build/birdie list nor the one in the system TMPDIR changed'
rm "$snapshots/orphan.accepted"
clean 'after removing the orphan'

echo; echo '== glinter passes a file it cannot parse; the wrapper fails it'
# Outside src/ and test/, so the compiler, which builds both, never sees it.
printf 'pub fn broken( {\n' > "$work/broken.gleam"
set +e; offline env PATH="$clone/.pixi/envs/default/bin:$PATH" gleam run --no-print-progress -m glinter "$work/broken.gleam" > "$work/glinter.log" 2>&1; rc=$?; set -e
[ "$rc" -eq 0 ] || { cat "$work/glinter.log"; fail "bare glinter exited $rc"; }
grep -q '^Error: Failed to parse ' "$work/glinter.log" || { cat "$work/glinter.log"; fail 'no parse error printed'; }
printf 'ok   gleam run -m glinter exit %s on a file it cannot parse:\n' "$rc"
sed "s|$work|<work>|; s/^/     /" "$work/glinter.log"
set +e; offline env PATH="$clone/.pixi/envs/default/bin:$PATH" sh scripts/checks/run_glinter.sh "$work/broken.gleam" > "$work/wrapper.log" 2>&1; rc=$?; set -e
[ "$rc" -eq 1 ] || { cat "$work/wrapper.log"; fail "the wrapper exited $rc"; }
printf 'ok   sh scripts/checks/run_glinter.sh exit %s on the same file:\n' "$rc"
sed "s|$work|<work>|; s/^/     /" "$work/wrapper.log"
clean 'at the end'

echo; echo 'birdie-check.sh: all cases passed'
