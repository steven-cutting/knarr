"""The checks.toml loader every copied checker reads through (Decision 0004)."""

from __future__ import annotations

from pathlib import Path

import pytest

import _project


def test_a_missing_checks_toml_is_an_error(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    with pytest.raises(SystemExit) as raised:
        _project.table(tmp_path, "docs")
    assert raised.value.code == 2
    assert "checks.toml" in capsys.readouterr().err


def test_a_missing_table_is_an_error(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    (tmp_path / "checks.toml").write_text('[agents]\nrequired_guidance = ["x"]\n')
    with pytest.raises(SystemExit) as raised:
        _project.table(tmp_path, "docs")
    assert raised.value.code == 2
    assert "[docs]" in capsys.readouterr().err


def test_a_present_table_is_returned(tmp_path: Path) -> None:
    (tmp_path / "checks.toml").write_text('[allium]\nspecs = "docs/specs/"\n')
    assert _project.table(tmp_path, "allium") == {"specs": "docs/specs/"}


def test_a_key_that_is_not_a_table_is_an_error(tmp_path: Path) -> None:
    (tmp_path / "checks.toml").write_text('docs = "not a table"\n')
    with pytest.raises(SystemExit) as raised:
        _project.table(tmp_path, "docs")
    assert raised.value.code == 2


def test_malformed_toml_is_an_error(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    (tmp_path / "checks.toml").write_text("[docs\n")
    with pytest.raises(SystemExit) as raised:
        _project.table(tmp_path, "docs")
    assert raised.value.code == 2
    assert "checks.toml" in capsys.readouterr().err


def test_only_boolean_true_enables_a_predicate(tmp_path: Path) -> None:
    (tmp_path / "checks.toml").write_text(
        "[docs]\n"
        'predicates = { on = true, off = false, quoted_true = "true", quoted_false = "false", one = 1 }\n'
    )
    declared, enabled = _project.predicates(tmp_path)
    assert declared == {"on", "off", "quoted_true", "quoted_false", "one"}
    assert enabled == {"on"}


def test_an_empty_predicate_table_is_valid(tmp_path: Path) -> None:
    (tmp_path / "checks.toml").write_text("[docs]\npredicates = {}\n")
    assert _project.predicates(tmp_path) == (set(), set())


def test_a_docs_table_without_predicates_is_an_error(tmp_path: Path) -> None:
    (tmp_path / "checks.toml").write_text("[docs]\n")
    with pytest.raises(SystemExit) as raised:
        _project.predicates(tmp_path)
    assert raised.value.code == 2


def test_predicates_that_are_not_a_table_are_an_error(tmp_path: Path) -> None:
    (tmp_path / "checks.toml").write_text('[docs]\npredicates = ["on"]\n')
    with pytest.raises(SystemExit) as raised:
        _project.predicates(tmp_path)
    assert raised.value.code == 2
