#!/bin/sh
# Run a command with the Justfile's PATH. Git runs hooks without it, so every
# prek hook entry goes through this script to reach the pixi environment and
# .tools/bin. markdownlint-cli2 is a `#!/usr/bin/env node` script, so even a
# tool called by its path needs the environment's bin directory on PATH.
# Usage: sh scripts/with-env.sh <command> [argument...]
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
# Without the environment every tool would resolve to whatever unpinned copy
# the system has, and a hook would check different rules from the gate.
[ -x "$root/.pixi/envs/default/bin/python3" ] ||
  { printf '%s\n' "the pixi environment is missing in $root; run just initialize" >&2; exit 2; }
PATH="$root/.pixi/envs/default/bin:$root/.pixi/envs/cluster/bin:$root/.tools/bin:$PATH"
PYTHONDONTWRITEBYTECODE=1
export PATH PYTHONDONTWRITEBYTECODE
exec "$@"
