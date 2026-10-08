set positional-arguments := true
set shell := ["sh", "-eu", "-c"]

# Recipes reach every tool through PATH, never `pixi run` (Decision 0003): on a
# stale lock `pixi run` re-solves and rewrites pixi.lock. The default
# environment comes first, so gleam and the shared tools always resolve from
# it; the cluster environment's tools resolve only once it is installed; then
# the checksum-pinned downloads from tools.txt.
export PATH := justfile_directory() / ".pixi" / "envs" / "default" / "bin" + ":" + justfile_directory() / ".pixi" / "envs" / "cluster" / "bin" + ":" + justfile_directory() / ".tools" / "bin" + ":" + env("PATH")

# Python would otherwise write __pycache__/ beside the checkers it runs.
export PYTHONDONTWRITEBYTECODE := "1"

# Which recipes write files: only `fix` and `initialize` here (and 08's snapshot
# review and accept recipes when they arrive). Only `fix` touches tracked files.
# Every recipe in the check group is read-only, and `just check` proves it.
[private]
default:
    @just --list

# ------------------------------------------------------------------ setup ---

# The one first-run command; it needs network, as does links-audit: the pixi
# environment, the tools.txt downloads, and Gleam's hex packages. Hooks install
# from the primary checkout only. Never stages, commits or pushes.
[group('setup')]
[doc('First run (needs network): pixi environment, tools.txt downloads, hex packages, hooks')]
initialize:
    sh scripts/initialize.sh

# ---------------------------------------------------------------- develop ---

# Warnings are errors here and in the gate alike. Each gleam recipe compares
# manifest.toml before and after, the backstop for a rewrite manifest-check
# cannot predict (Decision 0003); the snapshot runner also catches it in the
# gate.
[group('develop')]
[group('check')]
[doc('Build with warnings as errors (refuses a drifted manifest.toml)')]
build: manifest-check
    before=$(cksum < manifest.toml); gleam build --warnings-as-errors; [ "$(cksum < manifest.toml)" = "$before" ] || { echo 'gleam rewrote manifest.toml; run just manifest-check' >&2; exit 1; }

[group('develop')]
[group('check')]
[doc('Run the Gleam tests (refuses a drifted manifest.toml)')]
test: manifest-check
    before=$(cksum < manifest.toml); gleam test; [ "$(cksum < manifest.toml)" = "$before" ] || { echo 'gleam rewrote manifest.toml; run just manifest-check' >&2; exit 1; }

# The gate checkers' own tests (scripts/checks/tests/).
[group('develop')]
[group('check')]
[doc("Run the gate checkers' own tests")]
test-checkers:
    python3 -m pytest

# ----------------------------------------------------------------- format ---

# Automatic repairs through the fix config, the only recipe that rewrites
# tracked files. The config runs twice because one fixer's first pass may
# leave what another then repairs.
[group('format')]
[doc('Repair formatting and lint findings in place (the only recipe that edits tracked files)')]
fix:
    -prek run --all-files --config .pre-commit-fix.yaml
    prek run --all-files --config .pre-commit-fix.yaml

# ------------------------------------------------------------------ check ---

# --dry-run, because plain `pixi lock --check` rewrites a stale lock even as it
# fails; --offline, because the gate never fetches (Decision 0003).
[group('check')]
[doc('Fail if pixi.lock disagrees with pixi.toml, without rewriting it')]
lock-check:
    pixi lock --check --offline --dry-run

# lock-check reads pixi.lock and pixi.toml only. After a pull that moves a pin
# the old binaries stay on PATH until `just initialize` reruns, so this fails
# while the installed default environment or .tools/bin differs from the pins.
[group('check')]
[doc('Fail if the installed tools differ from pixi.lock or tools.txt')]
env-check:
    python3 scripts/checks/env_check.py

# gleam rewrites a manifest.toml that disagrees with gleam.toml and exits 0, so
# this compares the two first and fails instead (Decision 0003, Verify 5).
[group('check')]
[doc('Fail if manifest.toml disagrees with gleam.toml, without rewriting it')]
manifest-check:
    python3 scripts/checks/manifest_check.py

[group('check')]
[doc('Validate documentation metadata, registration, links, and reachability')]
docs-check:
    python3 scripts/checks/validate_docs.py

# Online checks stay outside the read-only, offline gate. Include hidden
# bootstrap docs, while excluding Git internals and generated directories.
[group('audit')]
[doc('Check Markdown and HTML links online (separate from the offline gate)')]
links-audit:
    lychee --no-progress --include-fragments --hidden --extensions md,html,htm --exclude-path '(^|/)(\.git|\.pixi|\.tools|build|ai_tmp)/' .

[group('check')]
[doc('Fail on unformatted Gleam')]
format-check:
    gleam format --check src test

[group('check')]
[doc('Fail on unformatted or invalid TOML')]
toml-check:
    taplo fmt --check
    taplo lint

# Every read-only hook over every file: typos, markdownlint, shellcheck,
# editorconfig-checker, ruff, lychee (offline), actionlint, ripsecrets, and
# prek's builtin checks. The gleam-format and taplo hooks are skipped here
# because format-check and toml-check run them as their own gate recipes.
[group('check')]
[doc('Run every read-only hook over every file')]
lint:
    SKIP=gleam-format,taplo prek run --all-files

# The runner calls this last, with the baseline it snapshotted.
[group('check')]
[doc('Fail if the worktree differs from the baseline (or, without one, is not clean)')]
check-clean baseline="":
    python3 scripts/checks/run_project_check.py clean "$1"

# The complete gate. The runner snapshots the worktree, runs each recipe and
# fails on the first change to any tracked or untracked-unignored file, even
# when the recipe passed, then runs check-clean. A lane adds its validator to
# this list.
[group('check')]
[doc('The complete read-only gate')]
check:
    test -x .pixi/envs/default/bin/python3 || { printf '%s\n' 'the pixi environment is missing; run just initialize' >&2; exit 2; }
    python3 scripts/checks/run_project_check.py run lock-check env-check manifest-check docs-check format-check build test test-checkers toml-check lint
