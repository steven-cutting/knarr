#!/bin/sh
# `just initialize`: the one first-run command, and the only step that needs
# network. It writes only ignored paths (.pixi/, .tools/, build/) and, in the
# primary checkout, .git/hooks. It never formats, stages, commits or pushes.
# Rerunning it is safe; with everything already present it needs no network.
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
cd "$root"
git rev-parse --is-inside-work-tree > /dev/null

command -v pixi > /dev/null ||
  { printf '%s\n' 'pixi is not installed; see README.md, Getting started' >&2; exit 2; }

# The compiler, OTP, Python and every gate tool, exactly as pixi.lock pins
# them. --locked refuses a lock that disagrees with pixi.toml rather than
# rewriting it.
pixi install --locked

# What conda-forge lacks (rebar3, ripsecrets, editorconfig-checker), each
# refused unless its sha256 matches tools.txt.
sh scripts/install-tools.sh tools.txt .tools/bin

# Gleam's hex packages into build/, so later builds run offline. The pre-check
# first: `gleam deps download` would silently rewrite a drifted manifest.toml.
python3 scripts/checks/manifest_check.py
gleam deps download
git diff --exit-code manifest.toml

sh scripts/install-hooks.sh

printf '\n%s\n' 'Ready. Next: just check (no network needed).'
printf '%s\n' 'Nothing has been staged, committed or pushed.'
