#!/usr/bin/env python3
"""Check bold RFC 2119 keywords in SMP Draft 0.3 against the audit map.

Extracts MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY from the custody-layer
spec. Fails when a keyword is missing from the keyword map, or when a mapped
conformance-audit ID is missing from the audit.

Passing this check does not claim SMP Draft 0.3 conformance. It only shows
that the keyword map and the audit ID column still agree.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SPEC = REPO_ROOT / "docs" / "publication" / "smp-custody-layer.md"
DEFAULT_MAP = REPO_ROOT / "docs" / "publication" / "smp-normative-coverage.md"
DEFAULT_AUDIT = REPO_ROOT / "docs" / "publication" / "smp-conformance-gap-audit.md"

KEYWORDS = ("MUST NOT", "SHOULD NOT", "MUST", "SHOULD", "MAY")
KEYWORD_RE = re.compile(
    r"\*\*(MUST NOT|SHOULD NOT|MUST|SHOULD|MAY)\*\*"
)
UNBOLDED_RE = re.compile(r"\b(MUST NOT|SHOULD NOT|MUST|SHOULD|MAY)\b")
BOILERPLATE_RE = re.compile(r"key words.*RFC 2119", re.IGNORECASE)
AUDIT_ID_RE = re.compile(r"^[A-Z]+[0-9]+(?:\.[0-9]+)?$")
MAP_HEADING = "## Keyword map"
AUDIT_HEADING = "## Requirement matrix"
NO_CONFORMANCE_CLAIM = "This check does not claim SMP Draft 0.3 conformance."


@dataclass(frozen=True)
class Hit:
    index: int
    keyword: str
    line: int
    text: str


@dataclass(frozen=True)
class MapRow:
    anchor: str
    keyword: str
    audit_ids: tuple[str, ...]
    line: int


@dataclass(frozen=True)
class Report:
    problems: tuple[str, ...]
    keyword_count: int
    map_row_count: int
    mapped_id_count: int


def _line_bounds(text: str, index: int) -> tuple[int, int]:
    start = text.rfind("\n", 0, index) + 1
    end = text.find("\n", index)
    if end < 0:
        end = len(text)
    return start, end


def _line_number(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def _excerpt(line: str) -> str:
    compact = " ".join(line.strip().split())
    if len(compact) <= 160:
        return compact
    return compact[:157] + "..."


def _section_lines(text: str, heading: str) -> tuple[list[tuple[int, str]], str | None]:
    lines = text.splitlines()
    start = None
    for index, line in enumerate(lines):
        if line.strip() == heading:
            start = index + 1
            break
    if start is None:
        return [], f"missing heading {heading!r}"
    body: list[tuple[int, str]] = []
    for offset, line in enumerate(lines[start:], start + 1):
        if line.startswith("## "):
            break
        body.append((offset, line))
    return body, None


def _table_cells(line: str) -> list[str] | None:
    if not line.startswith("|"):
        return None
    cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
    if not cells or all(set(cell) <= set("-: ") and cell for cell in cells):
        return None
    return cells


def extract_keywords(spec: str) -> tuple[list[Hit], list[Hit]]:
    """Return bold requirement hits, then unbolded uppercase keyword hits.

    The RFC 2119 definition sentence is not a requirement and is omitted.
    """

    bold: list[Hit] = []
    for match in KEYWORD_RE.finditer(spec):
        start, end = _line_bounds(spec, match.start())
        line = spec[start:end]
        if BOILERPLATE_RE.search(line):
            continue
        bold.append(
            Hit(
                index=match.start(),
                keyword=match.group(1),
                line=_line_number(spec, match.start()),
                text=_excerpt(line),
            )
        )

    masked = KEYWORD_RE.sub(lambda match: " " * (match.end() - match.start()), spec)
    unbolded: list[Hit] = []
    for match in UNBOLDED_RE.finditer(masked):
        start, end = _line_bounds(spec, match.start())
        unbolded.append(
            Hit(
                index=match.start(),
                keyword=match.group(1),
                line=_line_number(spec, match.start()),
                text=_excerpt(spec[start:end]),
            )
        )
    return bold, unbolded


def parse_map(map_text: str) -> tuple[list[MapRow], list[str]]:
    body, error = _section_lines(map_text, MAP_HEADING)
    if error:
        return [], [error]
    rows: list[MapRow] = []
    problems: list[str] = []
    for line_no, line in body:
        cells = _table_cells(line)
        if cells is None or cells[0] == "Anchor":
            continue
        if len(cells) != 3:
            problems.append(
                f"map row on line {line_no} has {len(cells)} cells; "
                "expected anchor, keyword, and audit IDs, with no '|' in the anchor"
            )
            continue
        anchor, keyword, id_cell = cells
        if not anchor:
            problems.append(f"map row on line {line_no} has an empty anchor")
            continue
        if keyword not in KEYWORDS:
            problems.append(
                f"map row on line {line_no} has unknown keyword {keyword!r}"
            )
            continue
        audit_ids = tuple(part.strip() for part in id_cell.split(","))
        if not audit_ids or any(not part for part in audit_ids):
            problems.append(f"map row on line {line_no} has no audit ID")
            continue
        bad_ids = [part for part in audit_ids if not AUDIT_ID_RE.fullmatch(part)]
        if bad_ids:
            problems.append(
                f"map row on line {line_no} has malformed audit IDs: {', '.join(bad_ids)}"
            )
            continue
        rows.append(MapRow(anchor, keyword, audit_ids, line_no))
    if not rows and not problems:
        problems.append(f"{MAP_HEADING} has no keyword rows")
    return rows, problems


def parse_audit_ids(audit_text: str) -> tuple[set[str], list[str]]:
    body, error = _section_lines(audit_text, AUDIT_HEADING)
    if error:
        return set(), [error]
    found: set[str] = set()
    problems: list[str] = []
    for line_no, line in body:
        cells = _table_cells(line)
        if cells is None or cells[0] == "ID":
            continue
        audit_id = cells[0]
        if not AUDIT_ID_RE.fullmatch(audit_id):
            problems.append(
                f"audit row on line {line_no} has malformed ID {audit_id!r}"
            )
            continue
        if audit_id in found:
            problems.append(f"audit ID {audit_id} is duplicated")
            continue
        found.add(audit_id)
    if not found and not problems:
        problems.append(f"{AUDIT_HEADING} has no requirement IDs")
    return found, problems


def evaluate(spec: str, map_text: str, audit_text: str) -> Report:
    spec = spec.replace("\r\n", "\n")
    problems: list[str] = []
    rows, map_problems = parse_map(map_text)
    problems.extend(map_problems)
    audit_ids, audit_problems = parse_audit_ids(audit_text)
    problems.extend(audit_problems)

    bold, unbolded = extract_keywords(spec)
    covered: dict[int, int] = {}
    mapped_ids: set[str] = set()

    for row in rows:
        mapped_ids.update(row.audit_ids)
        starts = []
        cursor = 0
        while True:
            found = spec.find(row.anchor, cursor)
            if found < 0:
                break
            starts.append(found)
            cursor = found + 1
        if not starts:
            problems.append(
                f"map anchor on line {row.line} was not found in the spec"
            )
            continue
        if len(starts) != 1:
            problems.append(
                f"map anchor on line {row.line} occurs {len(starts)} times in the spec"
            )
            continue
        span_start = starts[0]
        span_end = span_start + len(row.anchor)
        markers = list(KEYWORD_RE.finditer(spec, span_start, span_end))
        if len(markers) != 1:
            problems.append(
                f"map anchor on line {row.line} contains "
                f"{len(markers)} bold RFC 2119 keywords; expected 1"
            )
            continue
        marker = markers[0]
        if marker.group(1) != row.keyword:
            problems.append(
                f"map row on line {row.line} declares {row.keyword} "
                f"but the anchor contains {marker.group(1)}"
            )
            continue
        line_start, line_end = _line_bounds(spec, marker.start())
        if BOILERPLATE_RE.search(spec[line_start:line_end]):
            problems.append(
                f"map row on line {row.line} points at the RFC 2119 boilerplate"
            )
            continue
        previous = covered.get(marker.start())
        if previous is not None:
            problems.append(
                f"map row on line {row.line} covers the same keyword as line {previous}"
            )
            continue
        covered[marker.start()] = row.line
        for audit_id in row.audit_ids:
            if audit_id not in audit_ids:
                problems.append(
                    f"mapped audit ID {audit_id} from map line {row.line} "
                    "is missing from the conformance audit"
                )

    for hit in bold:
        if hit.index not in covered:
            problems.append(
                f"unmapped keyword {hit.keyword} on line {hit.line}: {hit.text}"
            )
    for hit in unbolded:
        problems.append(
            f"unbolded keyword {hit.keyword} on line {hit.line}: {hit.text}"
        )

    return Report(
        problems=tuple(problems),
        keyword_count=len(bold),
        map_row_count=len(rows),
        mapped_id_count=len(mapped_ids),
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spec", type=Path, default=DEFAULT_SPEC)
    parser.add_argument("--map", type=Path, default=DEFAULT_MAP)
    parser.add_argument("--audit", type=Path, default=DEFAULT_AUDIT)
    args = parser.parse_args(argv)

    report = evaluate(
        args.spec.read_text(encoding="utf-8"),
        args.map.read_text(encoding="utf-8"),
        args.audit.read_text(encoding="utf-8"),
    )
    print(NO_CONFORMANCE_CLAIM)
    if report.problems:
        for problem in report.problems:
            print(problem, file=sys.stderr)
        return 1
    print(
        f"{report.keyword_count} RFC 2119 keywords mapped; "
        f"every mapped audit ID is present."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
