#!/bin/sh
# Ticket 28 evidence: the public sources Decision 0011 cites, fetched today.
# Each page is recorded with its HTTP status, size and sha256, and each cited
# phrase is looked for in the page's text (tags stripped, entities decoded,
# whitespace collapsed). A fetch failure stops the run. A phrase that is not
# found prints "not found as of <date>" and counts as a finding, not a failure:
# unlike 15's source.sh, which reads files at a git tag, vendor pages are
# reworded without notice. One phrase is expected not to be found: "immutable"
# on the GHCR page, since GHCR offers no immutable-tag setting.
# Public-source research, not script evidence of behaviour.
# Needs curl and perl.
# Usage: sh sources.sh <empty-work-dir>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh disable=SC1091
. "$here/lib.sh"
work=${1:?usage: sources.sh <empty-work-dir>}
work=$(work_dir "$work")
today=$(date -u +%Y-%m-%d)
printf 'date: %sT%s\n' "$today" "$(date -u +%H:%MZ)"
text() { # html on stdin: visible text, one line
  perl -0777 -pe 's/<script.*?<\/script>//gs; s/<style.*?<\/style>//gs; s/<[^>]*>/ /g; s/&quot;/"/g; s/&#x27;|&rsquo;|&lsquo;/\x27/g; s/&ldquo;|&rdquo;/"/g; s/&amp;/&/g; s/&lt;/</g; s/&gt;/>/g; s/\s+/ /g'
}

# id|url: fetched once each, into $work/<id>.html
pages='ghcr|https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
access|https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility
environments|https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments
manage-environments|https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments
rulesets|https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets
runners|https://docs.github.com/en/actions/reference/runners/github-hosted-runners
attest-action|https://raw.githubusercontent.com/actions/attest-build-provenance/main/action.yml
attestations|https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations
gh-attestation|https://cli.github.com/manual/gh_attestation_verify
buildkit|https://docs.docker.com/build/metadata/attestations/
cosign|https://docs.sigstore.dev/cosign/signing/overview/
keepachangelog|https://keepachangelog.com/en/1.1.0/
semver|https://semver.org/spec/v2.0.0.html
kustomize|https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/images/'

# id|phrase|what it shows (a leading ! marks a phrase expected not to be found)
phrases='ghcr|GITHUB_TOKEN to publish packages associated with the workflow repository|a workflow logs in to ghcr.io with its own token
ghcr|docker login ghcr.io -u USERNAME --password-stdin|the login command the workflow uses
ghcr|the image is not linked to a repository by default|a CLI push is not linked; a workflow push with GITHUB_TOKEN is
ghcr|!immutable|GHCR has no immutable-tag setting: immutability comes from digest pins and the pre-push guard
access|public packages allow anonymous access and can be pulled without authentication|GKE pulls a public package with no pull secret
access|the package automatically inherits the access permissions (but not the visibility) of the linked repository|a new package is not public because the repository is: 37 makes it public by hand
environments|Only one of the required reviewers needs to approve the job for it to proceed|one maintainer approves the release job
environments|required reviewers are only available for public repositories|on GitHub Free, which fits: knarr is public
manage-environments|Prevent self-review|the setting a single maintainer must leave off, or the release deadlocks
rulesets|only users with bypass permissions can push to branches or tags whose name matches the pattern you specify|a tag ruleset can stop a v* tag from moving
rulesets|only users with bypass permissions can delete branches or tags whose name matches the pattern you specify|and from being deleted
runners|ubuntu-24.04-arm|an arm64 runner label exists for a later arm64 build job
runners|Use of the standard GitHub-hosted runners is free and unlimited on public repositories|the arm64 job would cost nothing in minutes
attest-action|push-to-registry|the action can attach the attestation to the image in the registry
attest-action|subject-digest|it takes the digest the build printed
attestations|artifact attestations are only available for public repositories|on GitHub Free, which fits
gh-attestation|oci://|gh attestation verify takes an image URI, as scripts/install-tools.sh already does for rebar3
buildkit|Provenance attestations with the mode=min level are added to images by default|why the workflow sets --provenance=false explicitly
buildkit|opt out of attestations with --provenance=false --sbom=false|the opt-out the workflow uses
cosign|Keyless signing associates identities, rather than keys|what cosign keyless would add; deferred
keepachangelog|Unreleased|the heading the CHANGELOG keeps at the top
semver|Given a version number MAJOR.MINOR.PATCH, increment the|the versioning scheme
kustomize|digest for images|the kustomization images field pins by digest'

printf '%s\n' "$pages" | while IFS='|' read -r id url; do
  code=$(curl -sSL -A 'Mozilla/5.0 (compatible; knarr evidence 28)' --max-time 60 -o "$work/$id.html" -w '%{http_code}' "$url") || code=000
  printf '%-20s http %s  %7s bytes  sha256 %s  %s\n' "$id" "$code" "$(wc -c < "$work/$id.html" | tr -d ' ')" "$(sha256_of < "$work/$id.html" | cut -c1-12)" "$url"
  [ "$code" = 200 ] || { echo "fetch failed: $url" >&2; exit 1; }
  text < "$work/$id.html" > "$work/$id.txt"
done
echo '--'
printf '%s\n' "$phrases" | while IFS='|' read -r id phrase what; do
  case $phrase in
    !*) phrase=${phrase#!}
        if grep -qF -- "$phrase" "$work/$id.txt"; then printf 'UNEXPECTED  %-20s "%s" is on the page now: %s\n' "$id" "$phrase" "$what"
        else printf 'not found   %-20s "%s" (expected; as of %s): %s\n' "$id" "$phrase" "$today" "$what"; fi ;;
    *)  if grep -qF -- "$phrase" "$work/$id.txt"; then printf 'found       %-20s "%s": %s\n' "$id" "$phrase" "$what"
        else printf 'not found   %-20s "%s" (as of %s): %s\n' "$id" "$phrase" "$today" "$what"; fi ;;
  esac
done > "$work/phrases.txt"
cat "$work/phrases.txt"
found=$(grep -c '^found' "$work/phrases.txt" || true)
missing=$(grep -c '^not found .*(as of' "$work/phrases.txt" || true)
expected_missing=$(grep -c '(expected;' "$work/phrases.txt" || true)
unexpected=$(grep -c '^UNEXPECTED' "$work/phrases.txt" || true)
printf -- '-- %s phrases found, %s not found, %s expected not found, %s unexpected\n' "$found" "$missing" "$expected_missing" "$unexpected"
