#!/bin/sh
# Ticket 01 evidence: rerun Verify 1 (TLS) and Verify 3 (rebar3) on linux-64.
# Installs the lock solve.sh produced, inside ghcr.io/prefix-dev/pixi:0.81.0
# forced to linux/amd64 (on an arm64 host docker would otherwise pick
# linux/arm64, which is conda's linux-aarch64, a platform the manifest omits).
# TLS runs twice: with the default environment, and with the runtime
# environment alone, which is what the runtime image carries.
#
# On an Apple-silicon host the amd64 container runs under Rosetta, where the
# BEAM JIT's dual-mapped code memory fails and every node dies at boot in
# prim_tty (official erlang:29 image too, so it is the emulator, not conda).
# The script shows that control, then sets ERL_FLAGS="+JMsingle true" (single
# mapping) only when /proc/cpuinfo names the Rosetta CPU. Production and CI run
# native linux-64 and need no flag.
# Usage: sh linux.sh <solve-work-dir>   (the directory solve.sh was given)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
solve=$(cd "${1:?usage: linux.sh <solve-work-dir>}" && pwd)
image=ghcr.io/prefix-dev/pixi:0.81.0
boot='io:put_chars(erlang:system_info(otp_release)), io:nl(), halt().'
echo '== control: official erlang:29 image, linux/amd64'
set +e
docker run --rm --platform linux/amd64 erlang:29 sh -c "grep -m1 'model name' /proc/cpuinfo; erl -noshell -eval '$boot' >/dev/null 2>&1; echo \"no flag: exit \$?\"; erl +JMsingle true -noshell -eval '$boot' 2>&1 | sed 's/^/+JMsingle true: otp_release /'"
set -e
echo
docker run --rm --platform linux/amd64 \
  -v "$here:/evidence:ro" -v "$solve/pixi.toml:/lock/pixi.toml:ro" -v "$solve/pixi.lock:/lock/pixi.lock:ro" \
  "$image" sh -euc '
    echo "image: '"$image"' ($(uname -m), $(. /etc/os-release && echo "$PRETTY_NAME"), $(pixi --version))"
    # curl for rebar3/fetch.sh; the image ships none. Not part of the pixi env.
    apt-get update -qq >/dev/null && apt-get install -y -qq --no-install-recommends curl ca-certificates >/dev/null
    mkdir -p /work && cp /lock/pixi.toml /lock/pixi.lock /work/ && cd /work
    cmp /evidence/pixi.toml.proposed pixi.toml || { echo "pixi.toml differs from pixi.toml.proposed" >&2; exit 1; }
    echo "pixi.toml is pixi.toml.proposed"
    # Logs, not pipes: a pipe into tail would hide a failure from set -e.
    pixi install --locked --all > install.log 2>&1 || { cat install.log; exit 1; }
    tail -1 install.log
    pixi lock --check --offline --dry-run > check.log 2>&1 || { cat check.log; exit 1; }
    tail -1 check.log
    for env in default runtime; do
      printf "%s: " "$env"; pixi list -e "$env" | awk "\$1==\"erlang\"||\$1==\"openssl\"{printf \"%s %s %s  \", \$1, \$2, \$3}"; echo
    done
    if grep -q VirtualApple /proc/cpuinfo; then
      if /work/.pixi/envs/runtime/bin/erl -noshell -eval "halt()." >/dev/null 2>&1; then echo "Rosetta, but erl boots without a flag"; else echo "Rosetta: erl without a flag fails to boot, as in the control"; fi
      ERL_FLAGS="+JMsingle true"; export ERL_FLAGS; echo "ERL_FLAGS=$ERL_FLAGS (emulation only)"
    fi
    erl() { "/work/.pixi/envs/$1/bin/erl" -noshell -eval "io:put_chars(erlang:system_info(otp_release)), io:nl(), halt()."; }
    want=$(pixi list -e runtime | awk "\$1==\"erlang\"{split(\$2, v, \".\"); print v[1]}")
    d=$(erl default); r=$(erl runtime)
    echo "otp_release default: $d, runtime: $r, pixi.lock erlang major: $want"
    [ -n "$want" ] && [ "$d" = "$want" ] && [ "$r" = "$want" ] || { echo "OTP majors disagree" >&2; exit 1; }
    echo "runtime environment installed size (what the runtime image copies): $(du -sh .pixi/envs/runtime | cut -f1); of which lib/erlang $(du -sh .pixi/envs/runtime/lib/erlang | cut -f1), lib/perl5 $(du -sh .pixi/envs/runtime/lib/perl5 | cut -f1)"
    echo; echo "== Verify 1, TLS, default environment"
    sh /evidence/tls/run.sh /work/.pixi/envs/default /tmp/tls-default
    echo; echo "== Verify 1, TLS, runtime environment (erlang and its dependencies only)"
    sh /evidence/tls/run.sh /work/.pixi/envs/runtime /tmp/tls-runtime
    echo; echo "== Verify 3, rebar3"
    sh /evidence/rebar3/fetch.sh /tmp/bin
    sh /evidence/rebar3/run.sh /work/.pixi/envs/default /tmp/bin /tmp/probe
    echo; echo "linux.sh: all checks passed"
  '
