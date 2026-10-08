"""Validate the agent guidance, its adapters, the skills and the skill bridges.

`AGENTS.md` is the single source of truth. Everything under `.agents/` and the
bridge directories exists only so a particular tool can discover it, so this
check fails when a bridge grows content of its own, a managed file appears or
disappears, or a vendored file drifts from `skills-lock.json`.

Copied from github.com/steven-cutting/biscuit_games_tooling at v0.3.0
(6c5c07f6bec86e86b3930dfa41392e4b440e8c85),
src/biscuit_games_tooling/validate_agents.py. Adapted on 2026-10-07 for
checks.toml, vendored skills and skills-lock.json (Decision 0004).

SPDX-License-Identifier: Apache-2.0
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
from contextlib import suppress
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, NoReturn

import _project

CANONICAL_SKILLS = Path(".agents/skills")
LOCK_FILE = "skills-lock.json"
LOCK_SCHEMA = 1
SHA256 = re.compile(r"[0-9a-f]{64}")
COMMIT = re.compile(r"[0-9a-f]{40}")
# The whole of a bridge body. Compared against this rather than measured: a word
# budget lets a bridge carry an instruction of its own as long as it is brief,
# and an instruction surface that says "this bridge adds nothing" has to mean it.
BRIDGE_BODY = (
    "Follow `{prefix}.agents/skills/{name}/SKILL.md`. "
    "That file is canonical and this bridge adds nothing to it."
)
UNRESOLVED = re.compile(r"{" + r"{|{" + r"%|{" + r"#")
# What `lock` mode prints when no lock exists to copy `source` from. The
# commit is not hex on purpose: the gate refuses it until the provenance is
# written by hand, so a fresh lock cannot pass with no provenance at all.
PLACEHOLDER_SOURCE = {
    "repository": "https://example.invalid/replace-me",
    "tag": "replace with the upstream tag",
    "commit": "replace with the upstream commit, 40 hex digits",
    "licence": "replace with the upstream licence",
}


@dataclass(frozen=True)
class Settings:
    """What `[agents]` in checks.toml asks of the surface."""

    required_guidance: tuple[str, ...]
    tolerated: frozenset[Path]
    bridges: dict[str, Path]
    adapters: dict[Path, str]

    @property
    def managed_directories(self) -> frozenset[Path]:
        # A bridge directory's first component is managed whole, as `.claude/`
        # was upstream, so a runtime file that is neither a bridge nor tolerated
        # still fails the gate. `.agents` is managed whatever the bridges say.
        return frozenset(
            {CANONICAL_SKILLS.parent, *(Path(d.parts[0]) for d in self.bridges.values())}
        )

    def bridge_body(self, runtime: str, name: str) -> str:
        prefix = "../" * (len(self.bridges[runtime].parts) + 1)
        return BRIDGE_BODY.format(prefix=prefix, name=name)


def _refuse(message: str) -> NoReturn:
    print(f"agent validation: {message}", file=sys.stderr)
    raise SystemExit(2)


def _relative_directory(value: object, key: str) -> Path:
    if not isinstance(value, str) or not value:
        _refuse(f"checks.toml: [agents] {key} must map to a nonempty relative path")
    path = Path(value)
    if path.is_absolute() or ".." in path.parts or not path.parts:
        _refuse(f"checks.toml: [agents] {key} must be a relative path without '..': {value!r}")
    return path


def _settings(root: Path) -> Settings:
    agents = _project.table(root, "agents")
    for key in ("required_guidance", "tolerated", "bridges", "adapters"):
        if key not in agents:
            _refuse(f"checks.toml: [agents] has no {key} key")

    guidance = agents["required_guidance"]
    if (
        not isinstance(guidance, list)
        or not guidance
        or any(not isinstance(phrase, str) or not phrase.strip() for phrase in guidance)
    ):
        _refuse("checks.toml: [agents] required_guidance must be a nonempty list of phrases")

    tolerated = agents["tolerated"]
    if not isinstance(tolerated, list) or any(not isinstance(item, str) for item in tolerated):
        _refuse("checks.toml: [agents] tolerated must be a list of paths")

    bridges = agents["bridges"]
    if not isinstance(bridges, dict):
        _refuse("checks.toml: [agents] bridges must be a table of runtime = directory")
    directories = {
        runtime: _relative_directory(value, f"bridges.{runtime}")
        for runtime, value in bridges.items()
    }
    for runtime, directory in directories.items():
        if directory.parts[0] == CANONICAL_SKILLS.parts[0]:
            _refuse(f"checks.toml: [agents] bridges.{runtime} must not live under .agents")

    adapters = agents["adapters"]
    if not isinstance(adapters, dict) or any(
        not isinstance(text, str) for text in adapters.values()
    ):
        _refuse("checks.toml: [agents] adapters must be a table of path = content")
    return Settings(
        required_guidance=tuple(guidance),
        tolerated=frozenset(_relative_directory(item, "tolerated") for item in tolerated),
        bridges=directories,
        adapters={
            _relative_directory(relative, "adapters"): text for relative, text in adapters.items()
        },
    )


def _skill_names(root: Path) -> tuple[str, ...]:
    return tuple(
        sorted(path.name for path in (root / CANONICAL_SKILLS).iterdir() if path.is_dir())
    )


def _reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    """Refuse an object that names the same key twice.

    The default decoder keeps the last of two identical keys, which would let
    one entry carry two hashes for a file and pass on whichever survived.
    """
    mapping: dict[str, Any] = {}
    for key, value in pairs:
        if key in mapping:
            message = f"duplicate key: {key}"
            raise ValueError(message)
        mapping[key] = value
    return mapping


def _parse_lock(data: object) -> dict[str, dict[PurePosixPath, str]]:
    if not isinstance(data, dict) or data.get("schema_version") != LOCK_SCHEMA:
        message = f"schema_version must be {LOCK_SCHEMA}"
        raise ValueError(message)
    source = data.get("source")
    if not isinstance(source, dict) or any(
        not isinstance(source.get(field), str) or not source[field]
        for field in ("repository", "tag", "commit")
    ):
        message = "source must name the repository, tag and commit"
        raise ValueError(message)
    if not COMMIT.fullmatch(source["commit"]):
        message = "source.commit must be a 40-digit lowercase hex commit"
        raise ValueError(message)
    skills = data.get("skills")
    if not isinstance(skills, dict):
        message = "skills must be a table"
        raise TypeError(message)

    lock: dict[str, dict[PurePosixPath, str]] = {}
    for name, entry in skills.items():
        if (
            not isinstance(entry, dict)
            or set(entry) != {"files", "upstream_path"}
            or not isinstance(entry["upstream_path"], str)
            or not isinstance(entry["files"], dict)
        ):
            message = f"skills.{name} must be a table of files and upstream_path"
            raise ValueError(message)
        files: dict[PurePosixPath, str] = {}
        for relative, digest in entry["files"].items():
            path = PurePosixPath(relative)
            if (
                not relative
                or path.is_absolute()
                or ".." in path.parts
                or "." in path.parts
                or str(path) != relative
            ):
                message = f"skills.{name}.files: {relative!r} must be a plain relative path"
                raise ValueError(message)
            if not isinstance(digest, str) or not SHA256.fullmatch(digest):
                message = f"skills.{name}.files: {relative} needs a lowercase sha256 hex digest"
                raise ValueError(message)
            files[path] = digest
        if PurePosixPath("SKILL.md") not in files:
            message = f"skills.{name} must list SKILL.md"
            raise ValueError(message)
        lock[name] = files
    return lock


def _load_lock(root: Path, errors: list[str]) -> dict[str, dict[PurePosixPath, str]] | None:
    """The lock's file digests per skill, or None when it cannot be trusted."""
    try:
        data = json.loads(
            (root / LOCK_FILE).read_text(encoding="utf-8"), object_pairs_hook=_reject_duplicates
        )
        return _parse_lock(data)
    except (OSError, TypeError, ValueError) as error:
        errors.append(f"{LOCK_FILE}: {error}")
        return None


def _digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def _expected_files(
    names: tuple[str, ...], settings: Settings, lock: dict[str, dict[PurePosixPath, str]]
) -> set[Path]:
    expected = {Path("AGENTS.md"), *settings.adapters}
    for name in names:
        expected.add(CANONICAL_SKILLS / name / "SKILL.md")
        expected.update(directory / name / "SKILL.md" for directory in settings.bridges.values())
        # Every file the lock lists is expected, so a file under a vendored
        # directory that the lock does not list is unexpected without a second
        # walk. A lock entry with no directory is _check_lock's finding.
        if name in lock:
            expected.update(CANONICAL_SKILLS / name / relative for relative in lock[name])
    return expected


def _versioned_paths(root: Path) -> set[Path]:
    """List every path Git would keep, ignored files excluded.

    Assistants write their own state into these directories -- Claude Code
    creates `.claude/settings.local.json` on the first permission approval --
    and a filesystem walk would report that state as an unexpected managed
    file. Deferring to Git means a `.gitignore` entry is enough to keep local
    tool state out of the inventory, while anything a reviewer would actually
    receive still counts.

    This project's own `.gitignore` is the only rule set consulted, rather than
    `--exclude-standard`. That option also honours `.git/info/exclude` and the
    user's global `core.excludesFile`, and putting `.claude/` in a personal
    global ignore file is a common habit -- it would hide the skills from this
    inventory and report every one of them as missing.
    """
    result = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-from=.gitignore"],
        cwd=root,
        check=False,
        capture_output=True,
        # A read that never refreshes the index, so the gate's snapshot holds.
        env={**os.environ, "GIT_OPTIONAL_LOCKS": "0"},
    )
    if result.returncode != 0:
        detail = result.stderr.decode(errors="backslashreplace").strip()
        raise RuntimeError(detail or "git ls-files failed; run just initialize")
    return {Path(os.fsdecode(item)) for item in result.stdout.split(b"\0") if item}


def _managed_files(root: Path, settings: Settings) -> set[Path]:
    top_level = {Path("AGENTS.md"), *settings.adapters}
    return {
        relative
        for relative in _versioned_paths(root)
        if (
            relative in top_level
            or any(directory in relative.parents for directory in settings.managed_directories)
        )
        # `--cached` still lists a tracked file that was deleted but not yet
        # staged; what is gone from the worktree is missing, not present.
        and ((root / relative).is_symlink() or (root / relative).exists())
    }


def _read(root: Path, relative: Path, errors: list[str]) -> str | None:
    try:
        return (root / relative).read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        errors.append(f"cannot read UTF-8 managed file: {relative}: {error}")
        return None


def _parse_frontmatter(text: str) -> tuple[dict[str, str], str]:
    lines = text.splitlines()
    if not lines or lines[0] != "---":
        message = "missing opening frontmatter"
        raise ValueError(message)
    try:
        end = lines.index("---", 1)
    except ValueError as error:
        message = "missing closing frontmatter"
        raise ValueError(message) from error
    fields: dict[str, str] = {}
    for line in lines[1:end]:
        if ":" not in line:
            message = f"invalid frontmatter line: {line}"
            raise ValueError(message)
        key, value = line.split(":", 1)
        key = key.strip()
        # Last-wins would let a block carrying three lines satisfy a rule about
        # two keys, so the repeat is the error rather than the survivor.
        if key in fields:
            message = f"duplicate frontmatter key: {key}"
            raise ValueError(message)
        fields[key] = value.strip()
    return fields, "\n".join(lines[end + 1 :])


def _check_inventory(
    root: Path,
    names: tuple[str, ...],
    settings: Settings,
    lock: dict[str, dict[PurePosixPath, str]],
    errors: list[str],
) -> None:
    expected = _expected_files(names, settings, lock)
    actual = _managed_files(root, settings)
    errors.extend(f"missing managed file: {relative}" for relative in sorted(expected - actual))
    errors.extend(
        f"unexpected managed file: {relative}"
        for relative in sorted(actual - expected - settings.tolerated)
    )
    vendored = {CANONICAL_SKILLS / name for name in names if name in lock}
    for relative in sorted(expected & actual):
        path = root / relative
        if path.is_symlink() or not path.is_file():
            errors.append(f"managed path must be a regular file: {relative}")
        elif any(directory in relative.parents for directory in vendored):
            # Hash-pinned upstream content; a language reference is exactly
            # where template-like syntax may legitimately appear.
            continue
        elif (text := _read(root, relative, errors)) is not None and UNRESOLVED.search(text):
            errors.append(f"managed file has unresolved template syntax: {relative}")


def _check_canonical(root: Path, settings: Settings, errors: list[str]) -> None:
    relative = Path("AGENTS.md")
    if not (root / relative).is_file():
        return
    text = _read(root, relative, errors)
    if text is None:
        return
    lowered = text.lower()
    errors.extend(
        f"AGENTS.md is missing required guidance: {phrase!r}"
        for phrase in settings.required_guidance
        if phrase.lower() not in lowered
    )
    if len(text.split()) < 300:
        errors.append("AGENTS.md is too short to carry the working agreement")


def _check_adapters(root: Path, settings: Settings, errors: list[str]) -> None:
    # Compared whole rather than stripped. docs/reference/agent-contract.md calls
    # these byte-pinned, and a comparison that forgave surrounding whitespace or a
    # missing final newline would be enforcing something weaker than the word.
    for relative, expected in settings.adapters.items():
        if not (root / relative).is_file():
            continue
        text = _read(root, relative, errors)
        if text is not None and text != expected:
            errors.append(f"{relative} must remain the exact thin adapter")


def _check_lock(
    root: Path,
    names: tuple[str, ...],
    lock: dict[str, dict[PurePosixPath, str]],
    errors: list[str],
) -> None:
    for name, files in lock.items():
        if name not in names:
            errors.append(f"{LOCK_FILE}: {name} names a skill directory that does not exist")
            continue
        for relative, digest in files.items():
            path = CANONICAL_SKILLS / name / relative
            if (root / path).is_symlink() or not (root / path).is_file():
                errors.append(f"listed in {LOCK_FILE} but missing: {path}")
            elif _digest(root / path) != digest:
                errors.append(f"sha256 differs from {LOCK_FILE}: {path}")


def _check_house_skill(name: str, fields: dict[str, str], body: str, errors: list[str]) -> None:
    skill = CANONICAL_SKILLS / name / "SKILL.md"
    if set(fields) != {"name", "description"}:
        errors.append(f"{skill}: frontmatter must be name and description")
    if fields.get("name") != name:
        errors.append(f"{skill}: name must match the directory")
    if len(fields.get("description", "").split()) < 8:
        errors.append(f"{skill}: description must state a real trigger")
    if "just " not in body or "AGENTS.md" not in body:
        errors.append(f"{skill}: a skill must cite AGENTS.md and use just recipes")


def _check_vendored_skill(name: str, fields: dict[str, str], errors: list[str]) -> None:
    # Upstream frontmatter carries its own keys (version, auto_trigger) and the
    # body never cites AGENTS.md; the project fit lives in AGENTS.md instead.
    skill = CANONICAL_SKILLS / name / "SKILL.md"
    if fields.get("name") != name:
        errors.append(f"{skill}: name must match the directory")
    if not fields.get("description", "").strip("\"'").strip():
        errors.append(f"{skill}: description must not be empty")


def _check_bridges(
    root: Path, name: str, fields: dict[str, str], settings: Settings, errors: list[str]
) -> None:
    # A bridge repeats only the two keys every runtime understands, verbatim,
    # so a vendored skill's version and triggers stay in the canonical file.
    expected = {key: fields[key] for key in ("name", "description") if key in fields}
    for runtime, directory in settings.bridges.items():
        bridge = directory / name / "SKILL.md"
        if not (root / bridge).is_file():
            continue
        text = _read(root, bridge, errors)
        if text is None:
            continue
        try:
            bridge_fields, bridge_body = _parse_frontmatter(text)
        except ValueError as error:
            errors.append(f"{bridge}: {error}")
            continue
        if bridge_fields != expected:
            errors.append(f"{bridge}: frontmatter must match the canonical skill")
        if bridge_body.strip() != settings.bridge_body(runtime, name):
            errors.append(f"{bridge}: must stay a thin pointer to the canonical skill")


def _check_skills(
    root: Path,
    names: tuple[str, ...],
    settings: Settings,
    vendored: frozenset[str],
    errors: list[str],
) -> None:
    if not names:
        errors.append(f"{CANONICAL_SKILLS} must define at least one skill")
        return
    for name in names:
        canonical = CANONICAL_SKILLS / name / "SKILL.md"
        if not (root / canonical).is_file():
            continue
        text = _read(root, canonical, errors)
        if text is None:
            continue
        try:
            fields, body = _parse_frontmatter(text)
        except ValueError as error:
            errors.append(f"{canonical}: {error}")
            continue
        if name in vendored:
            _check_vendored_skill(name, fields, errors)
        else:
            _check_house_skill(name, fields, body, errors)
        _check_bridges(root, name, fields, settings, errors)


def _lock_text(root: Path, names: list[str]) -> str:
    """A lock for the named skills, hashed from the files Git would keep."""
    if not names:
        _refuse("lock mode needs the names of the vendored skills")
    source: dict[str, Any] = dict(PLACEHOLDER_SOURCE)
    existing: dict[str, Any] = {}
    with suppress(OSError, ValueError):
        existing = json.loads((root / LOCK_FILE).read_text(encoding="utf-8"))
    if isinstance(existing, dict) and isinstance(existing.get("source"), dict):
        source = existing["source"]
    skills = existing.get("skills") if isinstance(existing, dict) else None
    previous = skills if isinstance(skills, dict) else {}

    versioned = sorted(_versioned_paths(root))
    entries: dict[str, Any] = {}
    for name in names:
        directory = CANONICAL_SKILLS / name
        if not (root / directory).is_dir():
            _refuse(f"lock: {directory} is not a directory")
        files = {}
        for relative in versioned:
            if directory not in relative.parents:
                continue
            path = root / relative
            if path.is_symlink() or not path.is_file():
                _refuse(f"lock: {relative} must be a regular file")
            files[relative.relative_to(directory).as_posix()] = _digest(path)
        upstream = f"skills/{name}"
        entry = previous.get(name)
        if isinstance(entry, dict) and isinstance(entry.get("upstream_path"), str):
            upstream = entry["upstream_path"]
        entries[name] = {"files": files, "upstream_path": upstream}
    lock = {"schema_version": LOCK_SCHEMA, "source": source, "skills": entries}
    return json.dumps(lock, indent=2, sort_keys=True) + "\n"


def main() -> int:
    """Report every inconsistency in the agent surface at once."""
    root = _project.root()
    if sys.argv[1:2] == ["lock"]:
        try:
            sys.stdout.write(_lock_text(root, sys.argv[2:]))
        except RuntimeError as failure:
            print(f"agent validation: {failure}", file=sys.stderr)
            return 1
        return 0

    settings = _settings(root)
    if not (root / CANONICAL_SKILLS).is_dir():
        print(f"agent validation: {CANONICAL_SKILLS} is missing", file=sys.stderr)
        return 1

    names = _skill_names(root)
    errors: list[str] = []
    lock = _load_lock(root, errors)
    _check_canonical(root, settings, errors)
    _check_adapters(root, settings, errors)
    vendored = frozenset(name for name in names if lock is not None and name in lock)
    # Without a trustworthy lock the inventory cannot say which files under a
    # vendored directory are expected, so the lock finding stands alone rather
    # than cascading into one line per upstream file.
    if lock is not None:
        try:
            _check_inventory(root, names, settings, lock, errors)
        except RuntimeError as failure:
            print(f"agent validation: {failure}", file=sys.stderr)
            return 1
        _check_lock(root, names, lock, errors)
        _check_skills(root, names, settings, vendored, errors)

    if errors:
        for error in sorted(set(errors)):
            print(f"agent validation: {error}", file=sys.stderr)
        return 1
    print(
        f"Validated AGENTS.md, {len(settings.adapters)} adapters, "
        f"{len(names) - len(vendored)} house skills, {len(vendored)} vendored skills "
        f"and {len(names) * len(settings.bridges)} bridges."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
