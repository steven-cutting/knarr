#!/bin/sh
# Ticket 02 evidence: the ripsecrets wrapper rewritten as POSIX sh
# (ripsecrets-redacted.sh, beside this script) keeps the Python original's
# behaviour. Each case builds a throwaway Git worktree, runs the wrapper in it,
# and asserts the exit status and the exact output. The binary is 0003's pinned
# ripsecrets 0.1.11 for the host, downloaded and checked against its sha256
# before anything runs it. Needs network and curl. Exits non-zero on any
# unexpected result.
# Usage: sh ripsecrets.sh <empty-work-dir> > ripsecrets.txt 2>&1
set -eu
here=$(cd "$(dirname "$0")" && pwd)
wrapper=$here/ripsecrets-redacted.sh
work=${1:?usage: ripsecrets.sh <empty-work-dir>}
mkdir -p "$work"; work=$(cd "$work" && pwd)
[ -z "$(ls -A "$work")" ] || { echo "work dir $work is not empty" >&2; exit 2; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }
sha() { if command -v sha256sum > /dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

# 0003's pins (evidence/01/tools.txt).
case $(uname -sm) in
  'Darwin arm64') target=aarch64-apple-darwin want=b2c822742e8cbf355ba0cb4cc690c3cd8fdc9ec1916c8148f27bd9098cb7aee4 ;;
  'Linux x86_64') target=x86_64-unknown-linux-gnu want=9daf017dfdea242a58f672450a2526f0406211afe9e872c740adc49b42feccf5 ;;
  *) fail "no ripsecrets pin for $(uname -sm)" ;;
esac
mkdir "$work/download" "$work/bin"
archive=$work/download/ripsecrets.tar.gz
curl -fsSL --proto '=https' -o "$archive" \
  "https://github.com/sirwart/ripsecrets/releases/download/v0.1.11/ripsecrets-0.1.11-$target.tar.gz"
[ "$(sha "$archive")" = "$want" ] || fail "ripsecrets archive sha256 $(sha "$archive"), pin $want"
# Extract the one member, so no other entry decides where anything lands.
tar -xzf "$archive" -C "$work/bin" --strip-components 1 "ripsecrets-0.1.11-$target/ripsecrets"
real=$work/bin/ripsecrets
printf 'date: %s\nhost: %s\nripsecrets: %s (archive sha256 matches the 0003 pin)\n\n' \
  "$(date -u +%Y-%m-%dT%H:%MZ)" "$(uname -sm)" "$("$real" --version)"

# A worktree with the pinned binary where 0003 installs it.
repo() { # name -> prints the path
  r=$work/$1; mkdir -p "$r/.tools/bin"; git -C "$r" init -q
  printf '.tools/\n' > "$r/.gitignore"; printf 'nothing to see\n' > "$r/clean.txt"
  cp "$real" "$r/.tools/bin/ripsecrets"; printf '%s' "$r"
}
# label, want-status, want-stdout, want-stderr, dir, wrapper args...
check() {
  label=$1 want_rc=$2 want_out=$3 want_err=$4 dir=$5; shift 5
  set +e; (cd "$dir" && sh "$wrapper" "$@") > "$work/out" 2> "$work/err"; rc=$?; set -e
  out=$(cat "$work/out"); err=$(cat "$work/err")
  [ "$rc" = "$want_rc" ] || fail "$label: status $rc, want $want_rc (stdout: $out; stderr: $err)"
  [ "$out" = "$want_out" ] || fail "$label: stdout [$out], want [$want_out]"
  [ "$err" = "$want_err" ] || fail "$label: stderr [$err], want [$want_err]"
  printf 'ok   %-58s status %s\n' "$label" "$rc"
}

r=$(repo clean)
check 'clean worktree: silent pass' 0 '' '' "$r"
# Inherited from ripsecrets 0.1.11, recorded so a new version that changes it
# fails here: a path that does not exist is an error message and status 0.
set +e; (cd "$r" && "$real" no-such-file > /dev/null 2>&1); bare_rc=$?; set -e
[ "$bare_rc" = 0 ] || fail "bare ripsecrets on a missing path exited $bare_rc; 0.1.11 exits 0"
check 'missing path argument: ripsecrets itself exits 0' 0 '' '' "$r" no-such-file

# The token is made at run time, so no committed file carries one.
found='ripsecrets found credential material; the matched values are suppressed'
token="ghp_$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 36)"
r=$(repo planted); printf 'token = "%s"\n' "$token" > "$r/config.py"
# Control: bare ripsecrets flags the token and prints it, so the wrapper has
# something real to suppress.
set +e; bare=$(cd "$r" && "$real" 2>&1); bare_rc=$?; set -e
[ "$bare_rc" = 1 ] || fail "control: bare ripsecrets exited $bare_rc on the planted token"
case $bare in *"$token"*) ;; *) fail 'control: bare ripsecrets did not print the token';; esac
printf 'ok   %-58s status %s\n' 'control: bare ripsecrets prints the planted token' "$bare_rc"
check 'planted token: status 1, fixed message' 1 "$found" '' "$r"
grep -qF "$token" "$work/out" "$work/err" && fail 'the token reached the output'
printf 'ok   %-58s\n' 'the token is absent from stdout and stderr'
check 'planted file named as an argument (as prek passes it)' 1 "$found" '' "$r" config.py
check 'clean file named as an argument, token elsewhere' 0 '' '' "$r" clean.txt
# A staged path may start with '-'; it must be scanned, not read as a flag.
cp "$r/config.py" "$r/-planted.py"
check 'planted file whose name starts with "-"' 1 "$found" '' "$r" -planted.py
rm "$r/-planted.py"

# The wrapper passes no flags: a flag-shaped argument is a path that does not
# exist, which ripsecrets 0.1.11 passes (status 0, as above).
check 'flag-shaped argument is a path, not a flag' 0 '' '' "$r" --no-such-flag
# Any other non-zero status is kept, with its own fixed message. A stand-in
# that prints the token and exits 3 shows that this path suppresses output too.
printf '#!/bin/sh\necho "%s"; echo "%s" >&2; exit 3\n' "$token" "$token" > "$r/.tools/bin/ripsecrets"
check 'stand-in prints the token and exits 3: status kept' 3 'ripsecrets failed with status 3; output suppressed' '' "$r"

# A refusal is status 2, not the original's 1, so it never reads as a finding.
# Only the pinned binary counts: a ripsecrets elsewhere on PATH (here a
# stand-in that would pass everything) is never used.
unavailable='ripsecrets is unavailable; run just initialize'
r=$(repo missing); rm "$r/.tools/bin/ripsecrets"
mkdir "$work/elsewhere"; printf '#!/bin/sh\nexit 0\n' > "$work/elsewhere/ripsecrets"; chmod +x "$work/elsewhere/ripsecrets"
(PATH="$work/elsewhere:$PATH"; export PATH; check 'no pinned binary, another on PATH: refusal' 2 '' "$unavailable" "$r")
printf 'not a binary\n' > "$r/.tools/bin/ripsecrets"
check 'pinned path is not executable: refusal' 2 '' "$unavailable" "$r"

mkdir "$work/not-a-repo"
(GIT_CEILING_DIRECTORIES=$work; export GIT_CEILING_DIRECTORIES
 check 'outside a Git worktree: refusal' 2 '' 'ripsecrets-redacted: run this from inside a Git worktree' "$work/not-a-repo")

echo; echo 'ripsecrets.sh: all cases passed'
