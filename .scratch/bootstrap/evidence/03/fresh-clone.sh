#!/bin/sh
# Ticket 03 evidence: a fresh clone reaches a green `just check` with one
# `just initialize`, and the gate then runs with the network denied. Also shows,
# in that clone: the pre-commit hook works when git runs it with a bare PATH,
# lock drift and manifest drift fail without rewriting either file, and a
# recipe that writes a tracked file fails the gate. Needs network for the first
# run only. On macOS the offline run uses sandbox-exec; on Linux, unshare.
# Exits non-zero on any unexpected result.
# Usage: sh fresh-clone.sh <repository> <branch> <empty-work-dir> > fresh-clone.txt 2>&1
set -eu
source=${1:?usage: fresh-clone.sh <repository> <branch> <work-dir>}
branch=${2:?usage: fresh-clone.sh <repository> <branch> <work-dir>}
work=${3:?usage: fresh-clone.sh <repository> <branch> <work-dir>}
mkdir -p "$work"; work=$(cd "$work" && pwd)
[ -z "$(ls -A "$work")" ] || { echo "work dir $work is not empty" >&2; exit 2; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }
sha() { if command -v sha256sum > /dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
now() { date +%s; }
offline() { # run a command with outbound network denied
  case $(uname -s) in
    Darwin) sandbox-exec -p '(version 1)(allow default)(deny network-outbound (remote ip))' "$@" ;;
    Linux) unshare -rn "$@" ;;
    *) fail "no offline runner for $(uname -s)" ;;
  esac
}
clean() { [ -z "$(git status --porcelain --untracked-files=all)" ] || { git status --short; fail "$1: worktree not clean"; }; }

clone=$work/clone
git clone -q --branch "$branch" --single-branch "$source" "$clone"
cd "$clone"
printf 'date: %s\nhost: %s\npixi: %s\ncommit: %s (%s)\n\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$(uname -sm)" \
  "$(pixi --version)" "$(git rev-parse --short HEAD)" "$branch"
[ "$(git rev-parse --path-format=absolute --git-dir)" = "$(git rev-parse --path-format=absolute --git-common-dir)" ] ||
  fail 'the clone is not a primary checkout'
echo 'ok   a fresh clone is a primary checkout'

echo; echo '== first run (network): one command, just initialize'
[ ! -e .pixi ] || fail 'the clone already has a pixi environment'
# The just on the host's PATH, as a contributor would have; without one, the
# script the recipe runs.
if command -v just > /dev/null; then first="just initialize ($(just --version))"; set -- just initialize
else first='sh scripts/initialize.sh (no just on PATH)'; set -- sh scripts/initialize.sh; fi
start=$(now)
"$@" > "$work/initialize.log" 2>&1 || { cat "$work/initialize.log"; fail "$first"; }
printf 'ok   %s, the only command run before the gate\n' "$first"
printf 'ok   first run took %ss (pixi and gleam caches may be warm on this machine)\n' "$(($(now) - start))"
sed 's/^/     /' "$work/initialize.log"
[ -f .git/hooks/pre-commit ] || fail 'the primary checkout has no pre-commit hook'
echo 'ok   the pre-commit hook is installed in the primary checkout'
clean 'after initialize'
echo 'ok   initialize left the worktree clean'

echo; echo '== the sandbox denies network'
if offline curl -fsS --max-time 10 -o /dev/null https://github.com > /dev/null 2>&1; then fail 'curl reached github.com inside the sandbox'; fi
echo 'ok   curl https://github.com fails inside the sandbox'

echo; echo '== just check, offline'
start=$(now)
offline .pixi/envs/default/bin/just check > "$work/check.log" 2>&1 || { cat "$work/check.log"; fail 'offline just check'; }
printf 'ok   just check passed offline in %ss\n' "$(($(now) - start))"
grep -E '^==> |passed|All checks' "$work/check.log" | sed 's/\x1b\[[0-9;]*m//g; s/^/     /'
clean 'after the offline gate'
echo 'ok   the worktree is unchanged'

echo; echo '== the hook under a bare PATH (git runs hooks without the Justfile PATH)'
bare() { env -i HOME="$HOME" PATH=/usr/bin:/bin "$@"; }
printf '# Hook probe\n' > probe.md
git add probe.md
bare git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -qm 'probe' > "$work/hook-ok.log" 2>&1 ||
  { cat "$work/hook-ok.log"; fail 'a clean commit was refused'; }
grep -q 'markdownlint.*Passed' "$work/hook-ok.log" || { cat "$work/hook-ok.log"; fail 'markdownlint did not run in the hook'; }
echo 'ok   a clean commit passes; markdownlint (a node script) ran under the bare PATH'
printf 'pub fn  bad( ) { 1 }\n' > src/bad.gleam
git add src/bad.gleam
if bare git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -qm 'bad' > "$work/hook-bad.log" 2>&1; then
  fail 'an unformatted Gleam file was committed'
fi
grep -q 'gleam format check.*Failed' "$work/hook-bad.log" || { cat "$work/hook-bad.log"; fail 'gleam format did not refuse it'; }
echo 'ok   an unformatted Gleam file is refused by the hook'
git reset -q --hard HEAD~1
clean 'after the hook probe'

echo; echo '== lock drift fails and never rewrites pixi.lock'
before=$(sha pixi.lock)
# A pin the lock does not satisfy: shellcheck moved off its locked version.
sed 's/^shellcheck = "==0.11.0"$/shellcheck = "==0.10.0"/' pixi.toml > pixi.toml.new && mv pixi.toml.new pixi.toml
grep -q '^shellcheck = "==0.10.0"$' pixi.toml || fail 'the drift edit did not apply'
set +e; offline .pixi/envs/default/bin/just lock-check > "$work/lock.log" 2>&1; rc=$?; set -e
[ "$rc" -ne 0 ] || fail 'lock-check passed on a drifted manifest'
[ "$(sha pixi.lock)" = "$before" ] || fail 'lock-check rewrote pixi.lock'
printf 'ok   just lock-check exit %s on drift; pixi.lock unchanged\n' "$rc"
git checkout -q pixi.toml

echo; echo '== manifest.toml drift fails the gate rather than being rewritten'
before=$(sha manifest.toml)
sed 's/^gleeunit = .*/gleeunit = ">= 1.0.0 and < 2.0.0"/' gleam.toml > gleam.toml.new && mv gleam.toml.new gleam.toml
set +e; offline .pixi/envs/default/bin/just check > "$work/manifest.log" 2>&1; rc=$?; set -e
[ "$rc" -ne 0 ] || fail 'just check passed with a drifted manifest.toml'
grep -q '==> just manifest-check' "$work/manifest.log" || fail 'the gate did not reach manifest-check'
grep -q 'manifest.toml disagrees with gleam.toml' "$work/manifest.log" || { cat "$work/manifest.log"; fail 'no drift message'; }
grep -q '==> just build' "$work/manifest.log" && fail 'the gate ran gleam after the pre-check failed'
[ "$(sha manifest.toml)" = "$before" ] || fail 'manifest.toml was rewritten'
printf 'ok   just check exit %s at manifest-check; manifest.toml unchanged\n' "$rc"
git checkout -q gleam.toml

echo; echo '== a recipe that writes a tracked file fails the gate'
printf '\nwrites:\n    printf x >> README.md\n' >> Justfile
PATH="$clone/.pixi/envs/default/bin:$PATH" PYTHONDONTWRITEBYTECODE=1
export PATH PYTHONDONTWRITEBYTECODE
set +e; python3 scripts/checks/run_project_check.py run writes > "$work/writes.log" 2>&1; rc=$?; set -e
[ "$rc" -eq 1 ] || { cat "$work/writes.log"; fail "the gate exited $rc for a writing recipe"; }
grep -q 'changed: README.md' "$work/writes.log" || { cat "$work/writes.log"; fail 'the change was not named'; }
printf 'ok   the runner exits %s and names README.md\n' "$rc"
git checkout -q Justfile README.md
clean 'at the end'

echo; echo 'fresh-clone.sh: all cases passed'
