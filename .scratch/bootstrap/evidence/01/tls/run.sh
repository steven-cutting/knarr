#!/bin/sh
# Ticket 01 evidence, Verify 1. Runs the TLS cases with the OTP and openssl in
# one pixi environment.
# Usage: sh tls/run.sh <pixi-env-dir> <empty-work-dir>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
env=${1:?usage: run.sh <pixi-env-dir> <work-dir>}
work=${2:?usage: run.sh <pixi-env-dir> <work-dir>}
PATH="$env/bin:$PATH"; export PATH
printf 'date: %s\nhost: %s\nenv: %s\nopenssl: %s (%s)\nescript: %s\n' \
  "$(date -u +%Y-%m-%dT%H:%MZ)" "$(uname -sm)" "$env" "$(openssl version)" "$(command -v openssl)" "$(command -v escript)"
sh "$here/gen-certs.sh" "$work"
escript "$here/tls_check.escript" "$work"
