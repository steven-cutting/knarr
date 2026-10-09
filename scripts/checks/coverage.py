"""Report source-line coverage of the existing Gleam test command, offline.

The Erlang boot hook instruments before application startup. An EUnit reporter
collects before gleeunit calls halt; a fresh completed report is required even
when the test command exits successfully. No percentage is a pass/fail gate.
"""

import json
import os
import shlex
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path


def inventory(root, package):
    entries = []
    for source in sorted((root / "src").rglob("*")):
        if source.suffix not in {".gleam", ".erl"}:
            continue
        relative = source.relative_to(root)
        module = (
            source.relative_to(root / "src").with_suffix("").as_posix().replace("/", "@")
            if source.suffix == ".gleam"
            else source.stem
        )
        entries.append(
            {
                "path": relative.as_posix(),
                "module": module,
                "language": "gleam" if source.suffix == ".gleam" else "erlang",
                "beam": str(root / "build/dev/erlang" / package / "ebin" / f"{module}.beam"),
            },
        )
    if not entries:
        raise ValueError("no production sources found")
    return entries


def render(root, entries, raw):
    files = []
    totals = {language: {"covered": 0, "executable": 0} for language in ("gleam", "erlang")}
    if set(raw) != {entry["module"] for entry in entries}:
        raise ValueError("coverage report does not match the production module inventory")
    for entry in entries:
        covered, uncovered = set(), set()
        line_count = len((root / entry["path"]).read_text().splitlines())
        for line, hits in raw[entry["module"]]:
            if not 1 <= line <= line_count:
                raise ValueError(f"{entry['path']}: coverage line {line} is outside the source")
            (covered if hits else uncovered).add(line)
        uncovered -= covered
        total = len(covered) + len(uncovered)
        files.append(
            {
                "path": entry["path"],
                "language": entry["language"],
                "covered_lines": sorted(covered),
                "uncovered_lines": sorted(uncovered),
                "covered": len(covered),
                "executable": total,
            },
        )
        totals[entry["language"]]["covered"] += len(covered)
        totals[entry["language"]]["executable"] += total
    return {"files": files, "totals": totals}


def picture(report):
    lines = ["Coverage from gleam test (report only; executable source lines)"]
    for entry in report["files"]:
        count = entry["executable"]
        percent = f"{100 * entry['covered'] / count:.1f}%" if count else "n/a"
        missing = ",".join(map(str, entry["uncovered_lines"])) or "none"
        lines.append(
            f"{entry['path']}: {entry['covered']}/{count} ({percent}); uncovered: {missing}",
        )
    for language, total in report["totals"].items():
        lines.append(f"{language}: {total['covered']}/{total['executable']} executable lines")
    return "\n".join(lines) + "\n"


def main():
    root = Path.cwd()
    package = tomllib.loads((root / "gleam.toml").read_text())["name"]
    subprocess.run(["just", "manifest-check"], check=True)
    manifest = tomllib.loads((root / "manifest.toml").read_text())
    index = root / "build/packages/packages.toml"
    if not index.is_file():
        raise ValueError("missing cached package index; initialize with authorization")
    cached = tomllib.loads(index.read_text())["packages"]
    for dependency in manifest["packages"]:
        if not (root / "build/packages" / dependency["name"]).is_dir():
            raise ValueError(
                f"missing cached package: {dependency['name']}; initialize with authorization"
            )
        if cached.get(dependency["name"]) != dependency["version"]:
            raise ValueError(
                f"stale cached package: {dependency['name']}; initialize with authorization"
            )
    subprocess.run(["just", "build"], check=True)
    output = root / "build/coverage"
    output.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix="run-", dir=output))
    entries = inventory(root, package)
    (run / "inventory.json").write_text(json.dumps(entries) + "\n")
    subprocess.run(
        ["erlc", "-Werror", "-o", str(run), str(Path(__file__).with_name("coverage_ffi.erl"))],
        check=True,
    )
    env = {
        **os.environ,
        "KNARR_COVERAGE_DIR": str(run),
        "ERL_AFLAGS": (
            f"-pa {shlex.quote(str(run))} -s coverage_ffi boot " + os.environ.get("ERL_AFLAGS", "")
        ),
    }
    result = subprocess.run(["just", "test"], env=env, check=False)
    raw_path = run / "raw.json"
    if not raw_path.is_file():
        raise ValueError("coverage collection did not complete; no report is valid for this run")
    report = render(root, entries, json.loads(raw_path.read_text()))
    report["test_exit_code"] = result.returncode
    summary = picture(report)
    (run / "coverage.json").write_text(json.dumps(report, indent=2) + "\n")
    (run / "coverage.txt").write_text(summary)
    print(summary, end="")
    print(f"Reports: {run.relative_to(root)}")
    return result.returncode


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"coverage: {error}", file=sys.stderr)
        sys.exit(1)
