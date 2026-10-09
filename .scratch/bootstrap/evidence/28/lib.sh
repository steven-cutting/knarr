# Ticket 28 evidence: helpers sourced by every script, so all of them use one
# set of rules. Not run on its own. The pure helpers are tested in lib_test.sh;
# the two that reach the network (probe_tag, head_digest) are
# exercised live in registry.sh and ghcr-probe.sh. Ticket 36 moves the guards
# to scripts/release/ for the real workflow.
#
#   version_of_tag <tag>       v0.1.0 -> 0.1.0; a non-SemVer tag fails (1)
#   tags_for <tag> <sha>       the image tags one release pushes, one per line:
#                              X.Y.Z, X.Y, X (major > 0 only), sha-<7>; a
#                              prerelease gets only X.Y.Z-pre and sha-<7>;
#                              never latest
#   toml_version               gleam.toml on stdin: its one top-level version
#   tag_matches_version <tag> <version>
#                              0 match, 1 mismatch, 2 malformed
#   changelog_has_version <version>
#                              CHANGELOG.md on stdin: a "## [<version>]" heading
#   digest_of_headers          `curl -sI` output on stdin: Docker-Content-Digest
#   digest_of_metadata         buildx --metadata-file JSON on stdin
#   digest_of_inspect          `buildx imagetools inspect` output on stdin
#   tag_exists_verdict <curl status> <http code>
#                              absent (0) only on 404; present (1) on 200;
#                              unknown (2) for anything else: fail closed
#   probe_tag <base url> <repo> <tag> [curl args...]
#                              the HEAD request, then tag_exists_verdict; sets
#                              verdict, verdict_rc, code and curl_rc in the
#                              caller (no subshell, so the caller can show them)
#   head_digest <base url> <repo> <ref> [curl args...]
#                              the HEAD request, then digest_of_headers
#   tag_moved_verdict <old digest> <new digest> <old-pull status>
#                              moved or unchanged (0), unclear (1)
#   ancestor_verdict <ref> <base>
#                              ancestor (0), not-ancestor (1), unknown (2)
#   iso_seconds <ISO 8601 Z>   epoch seconds; step_seconds <from> <to> (fails
#                              on a non-timestamp, such as a null completedAt)
#   work_dir <path>            creates it, refuses a non-empty one, prints the
#                              absolute path
#   sha256_of                  stdin, the hex digest
#   median                     numbers on stdin, one per line
#   fail <message>             FAIL: <message> to stderr, exit 1

# This file is sourced, so it has no shebang. shellcheck 0.11.0 misreads a
# function called inside a pipeline or an arithmetic expansion as defined later
# (SC2218, as in 15); every function here is defined before its use.
# shellcheck shell=sh disable=SC2218

digest_re='sha256:[0-9a-f]{64}'
# Without an Accept header that lists the modern media types, registry:2
# answers a HEAD with a schema1 digest that matches nothing buildx reports.
manifest_accept='Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
work_dir() { # path: the scripts' one work-directory rule
  mkdir -p "$1"
  wd=$(cd "$1" && pwd)
  [ -z "$(ls -A "$wd")" ] || { echo "work dir $wd is not empty" >&2; exit 2; }
  printf '%s\n' "$wd"
}
sha256_of() { if command -v sha256sum > /dev/null; then sha256sum; else shasum -a 256; fi | cut -d' ' -f1; }

version_of_tag() { # tag
  printf '%s\n' "${1:-}" | grep -qE '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?$' || return 1
  printf '%s\n' "${1#v}"
}

tags_for() { # tag, commit sha (7 to 40 hex)
  v=$(version_of_tag "$1") || return 1
  printf '%s\n' "${2:-}" | grep -qE '^[0-9a-f]{7,40}$' || return 1
  printf '%s\n' "$v"
  case $v in
    *-*) ;; # a prerelease gets no floating tag
    *)
      major=${v%%.*}; rest=${v#*.}; minor=${rest%%.*}
      printf '%s.%s\n' "$major" "$minor"
      [ "$major" = 0 ] || printf '%s\n' "$major" ;;
  esac
  printf 'sha-%s\n' "$(printf '%s' "$2" | cut -c1-7)"
}

toml_version() { # gleam.toml on stdin
  tv=$(grep -E '^version = "[^"]+"$' | sed -E 's/^version = "([^"]+)"$/\1/')
  [ -n "$tv" ] || { echo 'toml_version: no top-level version line' >&2; return 1; }
  [ "$(printf '%s\n' "$tv" | wc -l | tr -d ' ')" -eq 1 ] || { echo 'toml_version: more than one version line' >&2; return 1; }
  printf '%s\n' "$tv"
}

tag_matches_version() { # tag, version
  tmv=$(version_of_tag "$1") || return 2
  [ -n "${2:-}" ] || return 2
  [ "$tmv" = "$2" ]
}

changelog_has_version() { # version; CHANGELOG.md on stdin
  awk -v v="$1" 'index($0, "## [" v "]") == 1 { found = 1 } END { exit !found }'
}

digest_of_headers() { # `curl -sI` output on stdin
  d=$(tr -d '\r' | grep -iE "^docker-content-digest: *$digest_re *$" | head -1 | sed -E 's/^[^:]*: *//; s/ *$//')
  [ -n "$d" ] && printf '%s\n' "$d"
}
digest_of_metadata() { # buildx --metadata-file JSON on stdin
  perl -0777 -ne 'if (/"containerimage\.digest"\s*:\s*"(sha256:[0-9a-f]{64})"/) { print "$1\n"; exit 0 } exit 1'
}
digest_of_inspect() { # `docker buildx imagetools inspect` output on stdin
  d=$(grep -E "^Digest: *$digest_re *$" | head -1 | sed -E 's/^Digest: *//; s/ *$//')
  [ -n "$d" ] && printf '%s\n' "$d"
}

tag_exists_verdict() { # curl exit status, http code
  if [ "${1:-}" = 0 ]; then
    case ${2:-} in
      404) echo absent; return 0 ;;
      200) echo present; return 1 ;;
    esac
  fi
  echo unknown; return 2
}
# The HEAD request behind the two helpers below. Prints the headers; the
# status code goes to $code and curl's status to $curl_rc, never to set -e.
registry_head() { # base url, repo, ref, [curl args...]
  rh_base=$1; rh_repo=$2; rh_ref=$3; shift 3
  curl_rc=0; code=''
  out=$(curl -sS -I --max-time 20 -w '\n%{http_code}' -H "$manifest_accept" "$@" "$rh_base/v2/$rh_repo/manifests/$rh_ref" 2> /dev/null) || curl_rc=$?
  code=$(printf '%s\n' "$out" | tail -1)
  printf '%s\n' "$out" | sed '$d'
}
probe_tag() { # base url, repo, tag, [curl args...]
  registry_head "$@" > /dev/null
  # shellcheck disable=SC2034  # both are read by the caller
  verdict_rc=0
  # shellcheck disable=SC2034
  verdict=$(tag_exists_verdict "$curl_rc" "$code") || verdict_rc=$?
}
head_digest() { # base url, repo, ref, [curl args...]
  registry_head "$@" | digest_of_headers
}

tag_moved_verdict() { # old digest, new digest, exit status of pulling the old digest
  if printf '%s\n' "${1:-}" | grep -qE "^$digest_re$" && printf '%s\n' "${2:-}" | grep -qE "^$digest_re$" && [ "${3:-}" = 0 ]; then
    if [ "$1" = "$2" ]; then echo unchanged; else echo moved; fi
    return 0
  fi
  echo unclear; return 1
}

ancestor_verdict() { # ref, base
  c=$(git rev-parse --verify --quiet "$1^{commit}" 2> /dev/null) || { echo unknown; return 2; }
  b=$(git rev-parse --verify --quiet "$2^{commit}" 2> /dev/null) || { echo unknown; return 2; }
  av=0; git merge-base --is-ancestor "$c" "$b" 2> /dev/null || av=$?
  case $av in
    0) echo ancestor; return 0 ;;
    1) echo not-ancestor; return 1 ;;
    *) echo unknown; return 2 ;;
  esac
}

iso_seconds() { # 2026-10-09T04:17:58Z
  perl -MTime::Local=timegm -e 'if ($ARGV[0] =~ /^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)Z$/) { print timegm($6, $5, $4, $3, $2 - 1, $1), "\n"; exit 0 } exit 1' "$1"
}
step_seconds() { # from, to: fails on anything that is not a timestamp
  ss_a=$(iso_seconds "$1") || return 1
  ss_b=$(iso_seconds "$2") || return 1
  echo $((ss_b - ss_a))
}
median() { # numbers on stdin
  perl -e 'my @v = sort { $a <=> $b } grep { /\S/ } map { chomp; $_ } <STDIN>; exit 1 unless @v; print((@v % 2 ? $v[$#v / 2] : ($v[@v / 2 - 1] + $v[@v / 2]) / 2), "\n")'
}
