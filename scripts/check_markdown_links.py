#!/usr/bin/env python3
"""Check Markdown links that point at files inside this repository.

External URLs are ignored and never fetched. Same-file heading fragments are
ignored. A destination that starts with ``/`` is resolved from the repository
root. Fenced code blocks, inline code spans, and HTML comments are not scanned.

There is no exception list. From the repository root:

    python3 scripts/check_markdown_links.py
    python3 scripts/check_markdown_links.py README.md docs/roadmap.md
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import unquote, urlsplit


_MARKDOWN_SUFFIXES = {".md", ".markdown"}
_FENCE_MARKERS = ("`", "~")


class UsageError(Exception):
    """The command was invoked with paths this checker will not scan."""


@dataclass(frozen=True)
class LinkProblem:
    source: str
    line: int
    detail: str

    def format(self) -> str:
        return f"{self.source}:{self.line}: {self.detail}"


@dataclass(frozen=True)
class CheckResult:
    files: int
    local_links: int
    external_skipped: int
    fragments_skipped: int
    problems: tuple[LinkProblem, ...]


def format_summary(result: CheckResult) -> str:
    return (
        f"checked {_counted(result.files, 'markdown file')}, "
        f"{_counted(result.local_links, 'repo-relative link')}, "
        f"{_counted(result.external_skipped, 'external link')} skipped, "
        f"{_counted(result.fragments_skipped, 'same-file fragment')} skipped, "
        f"{_counted(len(result.problems), 'broken link')}"
    )


def check_repository(root: Path) -> CheckResult:
    """Check every tracked Markdown file, plus untracked files git does not ignore."""
    root = root.resolve()
    return check_paths(root, list_markdown_files(root))


def check_paths(root: Path, paths: list[Path]) -> CheckResult:
    root = root.resolve()
    files = _unique_paths(paths)
    local_links = 0
    external_skipped = 0
    fragments_skipped = 0
    problems: list[LinkProblem] = []
    for path in files:
        source = _relative_posix(root, path)
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            problems.append(LinkProblem(source, 1, "markdown file is not valid UTF-8"))
            continue
        except OSError:
            problems.append(LinkProblem(source, 1, "markdown file could not be read"))
            continue
        for line, destination in extract_destinations(text):
            kind = link_kind(destination)
            if kind == "external":
                external_skipped += 1
                continue
            if kind != "local":
                fragments_skipped += 1
                continue
            local_links += 1
            problem = _problem_for(root, path, source, line, destination)
            if problem is not None:
                problems.append(problem)
    problems.sort(key=lambda item: (item.source, item.line, item.detail))
    return CheckResult(
        files=len(files),
        local_links=local_links,
        external_skipped=external_skipped,
        fragments_skipped=fragments_skipped,
        problems=tuple(problems),
    )


def list_markdown_files(root: Path) -> list[Path]:
    """Return Markdown files for ``root``.

    Git listings are used only when ``root`` is the work tree root. A directory
    inside a larger checkout is walked directly so scratch trees are not mixed
    with the parent repository.
    """
    root = root.resolve()
    if _git_toplevel(root) == root:
        listed = _git_markdown(root)
        if listed is not None:
            return listed
    return _walk_markdown(root)


def extract_destinations(text: str) -> list[tuple[int, str]]:
    """Return ``(line, destination)`` pairs for inline links, images, and reference definitions."""
    masked = _mask_inline_code(_mask_html_comments(_mask_fenced_code(text)))
    found = _inline_destinations(masked)
    found.extend(_reference_destinations(masked))
    return found


def link_kind(destination: str) -> str:
    """Classify a destination as ``external``, ``local``, or ``fragment``."""
    dest = destination.strip()
    if not dest:
        return "fragment"
    parts = urlsplit(dest)
    if parts.scheme or parts.netloc:
        return "external"
    if unquote(parts.path).strip() == "":
        return "fragment"
    return "local"


def repo_root_from_script() -> Path:
    return Path(__file__).resolve().parent.parent


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Check Markdown links that point at files or directories inside "
            "this repository. External URLs are not fetched. Same-file heading "
            "fragments are not validated."
        )
    )
    parser.add_argument(
        "paths",
        nargs="*",
        help=(
            "Markdown files to check, relative to the current directory. "
            "Default: every tracked *.md file and every untracked, non-ignored *.md file."
        ),
    )
    args = parser.parse_args(argv)
    root = repo_root_from_script()
    try:
        if args.paths:
            files = resolve_user_paths(root, args.paths)
            result = check_paths(root, files)
        else:
            result = check_repository(root)
    except UsageError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    for problem in result.problems:
        print(problem.format())
    print(format_summary(result))
    return 1 if result.problems else 0


def resolve_user_paths(root: Path, raw_paths: list[str]) -> list[Path]:
    root = root.resolve()
    resolved: list[Path] = []
    for raw in raw_paths:
        requested = Path(raw)
        path = requested if requested.is_absolute() else Path.cwd() / requested
        path = path.resolve()
        if not path.is_file():
            raise UsageError(f"not a file: {raw}")
        if path.suffix.lower() not in _MARKDOWN_SUFFIXES:
            raise UsageError(f"not a markdown file: {raw}")
        try:
            path.relative_to(root)
        except ValueError as exc:
            raise UsageError(f"outside the repository: {raw}") from exc
        resolved.append(path)
    return resolved


def _problem_for(
    root: Path,
    source_file: Path,
    source: str,
    line: int,
    destination: str,
) -> LinkProblem | None:
    path = unquote(urlsplit(destination.strip()).path)
    if path.startswith("/"):
        candidate = root.joinpath(*_parts(path))
    else:
        candidate = source_file.parent.joinpath(*_parts(path))
    try:
        relative = candidate.resolve().relative_to(root)
    except ValueError:
        return LinkProblem(
            source,
            line,
            f"local target escapes the repository: `{destination}`",
        )
    if candidate.resolve().exists():
        return None
    return LinkProblem(
        source,
        line,
        f"missing local target `{destination}` (resolved to `{relative.as_posix()}`)",
    )


def _parts(path: str) -> tuple[str, ...]:
    stripped = path.strip().replace("\\", "/")
    pieces = [piece for piece in stripped.split("/") if piece not in {"", "."}]
    return tuple(pieces)


def _inline_destinations(text: str) -> list[tuple[int, str]]:
    found: list[tuple[int, str]] = []
    start = 0
    while True:
        closer = text.find("](", start)
        if closer < 0:
            break
        if _is_escaped(text, closer):
            start = closer + 2
            continue
        label = _label_start(text, closer)
        parsed = None if label is None else _parse_inline_destination(text, closer + 2)
        if label is None or parsed is None:
            start = closer + 2
            continue
        destination, end = parsed
        found.append((text.count("\n", 0, closer) + 1, destination))
        start = end if end > closer else closer + 2
    return found


def _reference_destinations(text: str) -> list[tuple[int, str]]:
    found: list[tuple[int, str]] = []
    for line_number, line in enumerate(text.split("\n"), start=1):
        label, rest = _reference_definition(line)
        if label is None or rest is None:
            continue
        # GitHub footnote definitions use the same colon syntax and are prose.
        if label.startswith("^"):
            continue
        destination = _parse_reference_destination(rest)
        if destination is None:
            continue
        found.append((line_number, destination))
    return found


def _reference_definition(line: str) -> tuple[str, str] | tuple[None, None]:
    indent = len(line) - len(line.lstrip(" "))
    if indent > 3 or not line.lstrip(" ").startswith("["):
        return None, None
    body = line[indent:]
    if len(body) < 4 or body[0] != "[":
        return None, None
    end = body.find("]:")
    if end <= 1 or "]" in body[1:end]:
        return None, None
    return body[1:end], body[end + 2 :]


def _parse_reference_destination(rest: str) -> str | None:
    text = rest.strip()
    if not text:
        return None
    if text[0] == "<":
        parsed = _parse_angle_destination(text, 0)
        if parsed is None:
            return None
        return parsed[0]
    return _parse_raw_destination(text, 0, stop_at_paren=False)[0]


def _parse_inline_destination(text: str, start: int) -> tuple[str, int] | None:
    index = _skip_inline_space(text, start)
    if index >= len(text):
        return None
    if text[index] == "<":
        parsed = _parse_angle_destination(text, index)
    else:
        parsed = _parse_raw_destination(text, index, stop_at_paren=True)
    if parsed is None:
        return None
    destination, index = parsed
    index = _skip_optional_title(text, index)
    if index is None or index >= len(text) or text[index] != ")":
        return None
    return destination, index + 1


def _parse_angle_destination(text: str, start: int) -> tuple[str, int] | None:
    if start >= len(text) or text[start] != "<":
        return None
    chars: list[str] = []
    index = start + 1
    while index < len(text):
        char = text[index]
        if char == "\n":
            return None
        if char == "\\" and index + 1 < len(text) and text[index + 1] != "\n":
            chars.append(text[index + 1])
            index += 2
            continue
        if char == ">":
            return "".join(chars), index + 1
        chars.append(char)
        index += 1
    return None


def _parse_raw_destination(
    text: str,
    start: int,
    *,
    stop_at_paren: bool,
) -> tuple[str, int] | None:
    chars: list[str] = []
    depth = 0
    index = start
    while index < len(text):
        char = text[index]
        if char == "\\" and index + 1 < len(text) and text[index + 1] != "\n":
            chars.append(text[index + 1])
            index += 2
            continue
        if char.isspace() or ord(char) < 32:
            break
        if stop_at_paren and char == "(":
            depth += 1
        elif stop_at_paren and char == ")":
            if depth == 0:
                break
            depth -= 1
        chars.append(char)
        index += 1
    if not chars:
        return None
    return "".join(chars), index


def _skip_optional_title(text: str, start: int) -> int | None:
    index = _skip_inline_space(text, start)
    if index >= len(text) or text[index] not in {'"', "'", "("}:
        return index
    closing = ")" if text[index] == "(" else text[index]
    index += 1
    while index < len(text):
        char = text[index]
        if char == "\\" and index + 1 < len(text):
            index += 2
            continue
        if char == "\n":
            return None
        if char == closing:
            return _skip_inline_space(text, index + 1)
        index += 1
    return None


def _skip_inline_space(text: str, start: int) -> int:
    index = start
    while index < len(text) and text[index] in " \t":
        index += 1
    if index < len(text) and text[index] == "\n":
        index += 1
        while index < len(text) and text[index] in " \t":
            index += 1
    return index


def _label_start(text: str, closer: int) -> int | None:
    depth = 1
    index = closer - 1
    while index >= 0:
        if _is_escaped(text, index):
            index -= 1
            continue
        char = text[index]
        if char == "]":
            depth += 1
        elif char == "[":
            depth -= 1
            if depth == 0:
                return index
        index -= 1
    return None


def _is_escaped(text: str, index: int) -> bool:
    slashes = 0
    cursor = index - 1
    while cursor >= 0 and text[cursor] == "\\":
        slashes += 1
        cursor -= 1
    return slashes % 2 == 1


def _mask_fenced_code(text: str) -> str:
    lines = text.split("\n")
    masked = [False] * len(lines)
    index = 0
    while index < len(lines):
        opener = _fence(lines[index])
        if opener is None or (opener[0] == "`" and "`" in opener[2]):
            index += 1
            continue
        char, length, _info = opener
        masked[index] = True
        index += 1
        while index < len(lines):
            masked[index] = True
            closer = _fence(lines[index])
            closing = (
                closer is not None
                and closer[0] == char
                and closer[1] >= length
                and closer[2].strip() == ""
            )
            index += 1
            if closing:
                break
    return "\n".join(" " * len(line) if hide else line for hide, line in zip(masked, lines))


def _fence(line: str) -> tuple[str, int, str] | None:
    stripped = line.rstrip("\r")
    indent = len(stripped) - len(stripped.lstrip(" "))
    if indent > 3:
        return None
    body = stripped[indent:]
    if not body or body[0] not in _FENCE_MARKERS:
        return None
    char = body[0]
    length = 0
    while length < len(body) and body[length] == char:
        length += 1
    if length < 3:
        return None
    return char, length, body[length:]


def _mask_html_comments(text: str) -> str:
    chars = list(text)
    start = 0
    while True:
        opened = text.find("<!--", start)
        if opened < 0:
            break
        closed = text.find("-->", opened + 4)
        if closed < 0:
            break
        for index in range(opened, closed + 3):
            if chars[index] != "\n":
                chars[index] = " "
        start = closed + 3
    return "".join(chars)


def _mask_inline_code(text: str) -> str:
    chars = list(text)
    index = 0
    length = len(text)
    while index < length:
        if text[index] != "`":
            index += 1
            continue
        run = index
        while run < length and text[run] == "`":
            run += 1
        opener = run - index
        cursor = run
        closing: tuple[int, int] | None = None
        while cursor < length:
            if text[cursor] != "`":
                cursor += 1
                continue
            end = cursor
            while end < length and text[end] == "`":
                end += 1
            if end - cursor == opener:
                closing = (cursor, end)
                break
            cursor = end
        if closing is None:
            index = run
            continue
        for position in range(index, closing[1]):
            if chars[position] != "\n":
                chars[position] = " "
        index = closing[1]
    return "".join(chars)


def _git_toplevel(root: Path) -> Path | None:
    proc = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        return None
    return Path(proc.stdout.strip()).resolve()


def _git_markdown(root: Path) -> list[Path] | None:
    proc = subprocess.run(
        [
            "git",
            "-C",
            str(root),
            "ls-files",
            "-z",
            "--cached",
            "--others",
            "--exclude-standard",
            "--",
            "*.md",
        ],
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        return None
    names = [name.decode("utf-8") for name in proc.stdout.split(b"\0") if name]
    return sorted(root.joinpath(*name.split("/")).resolve() for name in names)


def _walk_markdown(root: Path) -> list[Path]:
    found = [
        path.resolve()
        for path in root.rglob("*.md")
        if path.is_file() and ".git" not in path.relative_to(root).parts
    ]
    return sorted(found)


def _unique_paths(paths: list[Path]) -> list[Path]:
    unique: list[Path] = []
    seen: set[Path] = set()
    for path in paths:
        resolved = path.resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        unique.append(resolved)
    return unique


def _relative_posix(root: Path, path: Path) -> str:
    return path.resolve().relative_to(root.resolve()).as_posix()


def _counted(count: int, singular: str) -> str:
    word = singular if count == 1 else f"{singular}s"
    return f"{count} {word}"


if __name__ == "__main__":
    sys.exit(main())
