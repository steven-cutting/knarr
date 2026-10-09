#!/bin/sh
# Ticket 28 evidence: what ghcr.io and the repository look like before the
# first release, read only. Anonymous registry reads of the knarr package that
# does not exist yet, the pre-push guard's three verdicts against the real
# ghcr.io (a public package as the control), then the repository's settings
# through gh: visibility, environments, rulesets, branch protection, tags,
# releases, and whether the token can list packages at all.
# Nothing here logs in to ghcr.io, pushes, or writes through gh.
# Needs curl, gh (authenticated) and perl.
# Usage: sh ghcr-probe.sh
# The gate runs shellcheck without -x, so it cannot see that probe_tag in lib.sh
# sets verdict, verdict_rc, code and curl_rc.
# shellcheck disable=SC2154
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh disable=SC1091
. "$here/lib.sh"
repo=steven-cutting/knarr
ghcr=https://ghcr.io
control=prefix-dev/pixi # a public package the Dockerfile already pulls
control_tag=0.81.0
printf 'date: %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)"

say() { printf '%s\n' "$*"; }
http() { # prints "<code> <first 160 bytes of the body>"
  body=$(curl -sS --max-time 20 -w '\n%{http_code}' "$@" 2>&1) || true
  printf '%s %s\n' "$(printf '%s\n' "$body" | tail -1)" "$(printf '%s\n' "$body" | sed '$d' | tr -d '\n' | cut -c1-160)"
}

say "-- anonymous reads of $ghcr/v2/$repo"
say "GET /v2/: $(http "$ghcr/v2/")"
say "GET /v2/$repo/tags/list: $(http "$ghcr/v2/$repo/tags/list")"
say "GET /token?scope=repository:$repo:pull: $(http "$ghcr/token?scope=repository:$repo:pull&service=ghcr.io")"
# The anonymous token endpoint answers 403 denied, the same for a package that
# does not exist and for a private one. The guard therefore runs after `docker
# login` in the workflow; anonymously it must say unknown, never absent.
probe_tag "$ghcr" "$repo" 0.1.0
say "guard, anonymous HEAD /v2/$repo/manifests/0.1.0: $verdict (exit $verdict_rc, http $code)"
[ "$verdict" = unknown ] || fail "an anonymous read of an absent-or-private package must be unknown, got $verdict"

say "-- the guard's three verdicts against ghcr.io, with the control package $control"
tok=$(curl -sS --max-time 20 "$ghcr/token?scope=repository:$control:pull&service=ghcr.io" | perl -ne 'print $1 if /"token":"([^"]+)"/')
[ -n "$tok" ] || fail "no anonymous pull token for $control"
probe_tag "$ghcr" "$control" "$control_tag" -H "Authorization: Bearer $tok"
say "HEAD $control:$control_tag: $verdict (exit $verdict_rc, http $code)"
[ "$verdict" = present ] || fail "expected present for $control:$control_tag"
d=$(head_digest "$ghcr" "$control" "$control_tag" -H "Authorization: Bearer $tok") || fail "no digest header for $control:$control_tag"
say "  Docker-Content-Digest: $d"
probe_tag "$ghcr" "$control" no-such-tag-28 -H "Authorization: Bearer $tok"
say "HEAD $control:no-such-tag-28: $verdict (exit $verdict_rc, http $code)"
[ "$verdict" = absent ] || fail "expected absent for $control:no-such-tag-28"
probe_tag "$ghcr" "$control" "$control_tag" -H 'Authorization: Bearer not-a-token'
say "HEAD $control:$control_tag with a bad token: $verdict (exit $verdict_rc, http $code)"
[ "$verdict" = unknown ] || fail "expected unknown with a bad token"
probe_tag http://127.0.0.1:1 "$control" "$control_tag"
say "HEAD against a closed port: $verdict (exit $verdict_rc, curl $curl_rc)"
[ "$verdict" = unknown ] || fail "expected unknown for a closed port"

say "-- repository $repo through gh (read only)"
gh api "repos/$repo" --jq '"visibility: \(.visibility); default branch: \(.default_branch); merge methods: merge=\(.allow_merge_commit) squash=\(.allow_squash_merge) rebase=\(.allow_rebase_merge); delete branch on merge: \(.delete_branch_on_merge)"'
gh api "repos/$repo/environments" --jq '"environments: \(.total_count): \([.environments[].name] | join(", "))"'
say "rulesets: $(gh api "repos/$repo/rulesets" --jq 'if length == 0 then "none" else map(.name) | join(", ") end')"
gh api "repos/$repo/branches/main/protection" --jq '"main protection: required checks \(.required_status_checks.contexts); enforce_admins \(.enforce_admins.enabled); required approving reviews \(.required_pull_request_reviews.required_approving_review_count // 0)"'
say "tags: $(gh api "repos/$repo/tags" --jq length); releases: $(gh api "repos/$repo/releases" --jq length)"
say "token scopes: $(gh api -i user 2> /dev/null | tr -d '\r' | grep -i '^x-oauth-scopes:' | sed 's/^[^:]*: *//')"
pk=$(gh api 'user/packages?package_type=container' 2>&1 | head -1 | cut -c1-120 || true)
say "GET /user/packages?package_type=container: $pk"
say 'gleam.toml version: '"$(toml_version < "$here/../../../../gleam.toml")"
say "CHANGELOG.md: $(test -f "$here/../../../../CHANGELOG.md" && echo present || echo 'absent (ticket 12 creates it)')"
