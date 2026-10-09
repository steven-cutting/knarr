"""Read the S1 probe's log for the token-reload proof (ticket 14).

Usage: python3 s1_logs.py <kubectl logs --timestamps output> <pod start, RFC 3339>

Prints what it found and exits 0 only when every proof is in the log: the
first token hash with its expiry about 600 s after the pod started, a second,
different hash, and a successful LIST and PATCH logged after the first
expiry. Exit 1 while something is still missing, so a caller can poll. Only
hashes and expiry times are printed, never a token.
"""

from __future__ import annotations

import re
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Iterator

LINE = re.compile(r"^(\S+) s1_probe event=(\S+)(.*)$")


def epoch(rfc3339: str) -> float:
    # kubectl prints nanoseconds; Python parses up to microseconds.
    text = re.sub(r"(\.\d{6})\d+", r"\1", rfc3339).replace("Z", "+00:00")
    return datetime.fromisoformat(text).astimezone(UTC).timestamp()


def events(text: str) -> Iterator[tuple[float, str, dict[str, str]]]:
    for line in text.splitlines():
        match = LINE.match(line)
        if match:
            fields = dict(part.split("=", 1) for part in match[3].split() if "=" in part)
            yield epoch(match[1]), match[2], fields


def main(log_path: str, pod_start: str) -> int:
    start = epoch(pod_start)
    found = list(events(Path(log_path).read_text(encoding="utf-8")))
    changes = [(at, f) for at, event, f in found if event == "token_changed"]
    if not changes:
        print("waiting: no token_changed line yet")
        return 1
    _, first = changes[0]
    exp1 = int(first["jwt_exp"])
    print(
        f"first token: sha256 {first['token_sha256']} exp {exp1} (+{exp1 - start:.0f} s after pod start)"
    )
    if 540 <= exp1 - start <= 660:
        print(
            "ok   first token expires about 600 s after the pod started (expirationSeconds honoured)"
        )
    else:
        print("FAIL first token expiry is not about 600 s after the pod started")
        return 2
    rotated = [(at, f) for at, f in changes[1:] if f["token_sha256"] != first["token_sha256"]]
    if not rotated:
        print("waiting: no changed token hash yet")
        return 1
    at, second = rotated[0]
    print(
        f"rotated token: sha256 {second['token_sha256']} exp {second['jwt_exp']} seen at +{at - start:.0f} s"
    )
    print("ok   token file hash changed while the process ran")
    successes = [
        (at, event)
        for at, event, _ in found
        if event in {"list_pods", "patch_annotation"} and at > exp1
    ]
    kinds = {event for _, event in successes}
    if kinds != {"list_pods", "patch_annotation"}:
        print(f"waiting: after exp1 so far {sorted(kinds)}; now +{found[-1][0] - start:.0f} s")
        return 1
    first_after = min(at for at, _ in successes)
    print(
        f"ok   LIST and PATCH succeeded after the first token's expiry (first at exp1 +{first_after - exp1:.0f} s)"
    )
    failures = [(at, event, f) for at, event, f in found if event.endswith("_failed")]
    print(f"failed cycles in the log: {len(failures)}")
    for at, event, fields in failures[:5]:
        print(f"  +{at - start:.0f} s {event} {fields}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
