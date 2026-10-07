#!/bin/sh
# Run a command with the Justfile's PATH. Git runs hooks without it, so every
# prek hook entry goes through this script to reach the pixi environment and
# .tools/bin. markdownlint-cli2 is a `#!/usr/bin/env node` script, so even a
# tool called by its path needs the environment's bin directory on PATH.
# Usage: sh scripts/with-env.sh <command> [argument...]
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
PATH="$root/.pixi/envs/default/bin:$root/.pixi/envs/cluster/bin:$root/.tools/bin:$PATH"
PYTHONDONTWRITEBYTECODE=1
export PATH PYTHONDONTWRITEBYTECODE
exec "$@"
