#!/usr/bin/env python3
"""Check the sanitized agent-operations contract against public SQL signatures.

The checker recomputes the SHA-256 digest of ``docs/03-agent-operations.md`` and
reparses the ordered public-schema function signatures in this repository
(name, argument list, result shape). It fails closed when the digest does not
match, or when a recorded signature is removed, added, or changed.

It does not open a database connection and it does not read a private
instruction corpus. ``--corpus`` is an optional local path supplied by the
operator or by a test. The file is a synthetic or operator-provided export,
never a path this program fetches.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path


CONTRACT_ID = "agent-operations-contract/1"
CONTRACT_VERSION = "1.0.0"
CONTRACT_RELATIVE = Path("docs/03-agent-operations.md")
SURFACE_RELATIVE = Path("docs/contracts/agent-operations-surface.json")
VERSION_MARKER = "Contract version: agent-operations-contract/1.0.0"

# Ordered install list from the repository README. Last definition of each
# public function wins. sql/validation is not part of the install list.
ORDERED_SQL = (
    "01_core.sql",
    "02_vault.sql",
    "03_provenance_guards.sql",
    "04_source_import.sql",
    "05_candidate_locators.sql",
    "06_cutover_probe_categories.sql",
    "07_work_lessons.sql",
    "08_attention_events.sql",
    "09_perimeter_refresh.sql",
    "10_security_definer_hardening.sql",
    "11_perimeter_evaluability.sql",
)

MAX_CORPUS_BYTES = 2 * 1024 * 1024

_TYPE_STARTS = {
    "anyarray", "anyelement", "anynonarray", "bigint", "bool", "boolean",
    "bytea", "char", "character", "cstring", "date", "decimal", "double",
    "float4", "float8", "int", "int2", "int4", "int8", "integer", "internal",
    "interval", "json", "jsonb", "money", "name", "numeric", "oid", "real",
    "record", "regclass", "regprocedure", "regproc", "regrole", "regtype",
    "smallint", "text", "time", "timestamp", "timestamptz", "trigger",
    "uuid", "void", "xml",
}
_ARG_MODES = {"in", "out", "inout", "variadic"}
_STOP_CLAUSES = {
    "language", "window", "immutable", "stable", "volatile", "leakproof",
    "called", "strict", "security", "parallel", "cost", "rows", "set", "as",
    "with",
}
_TYPE_ALIASES = {
    "bool": "boolean",
    "boolean": "boolean",
    "char": "character",
    "float4": "real",
    "float8": "double precision",
    "int": "integer",
    "int2": "smallint",
    "int4": "integer",
    "int8": "bigint",
    "timestamptz": "timestamp with time zone",
    "varchar": "character varying",
}
# Builtins that prose mentions with type-like argument lists. They are not
# this repository's public function surface.
_SQL_BUILTINS = {
    "abs", "array_agg", "avg", "btrim", "char_length", "clock_timestamp",
    "coalesce", "count", "current_setting", "digest", "encode", "exists",
    "extract", "floor", "format", "greatest", "jsonb_agg", "jsonb_build_array",
    "jsonb_build_object", "least", "left", "length", "lower", "ltrim", "max",
    "md5", "min", "now", "nullif", "octet_length", "overlay", "position",
    "regexp_replace", "replace", "right", "round", "set_config", "string_agg",
    "substring", "sum", "to_jsonb", "trim", "unnest", "upper",
}

_TYPE_TOKEN = (
    r"(?:double\s+precision|character\s+varying"
    r"|timestamp\s+with\s+time\s+zone|timestamp\s+without\s+time\s+zone"
    r"|time\s+with\s+time\s+zone|time\s+without\s+time\s+zone"
    r"|[A-Za-z_][A-Za-z0-9_]*(?:\s*\[\])*)"
)
_CORPUS_SIGNATURE = re.compile(
    rf"(?<![\w.])([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*({_TYPE_TOKEN}(?:\s*,\s*{_TYPE_TOKEN})*)?\s*\)",
    re.IGNORECASE,
)
_CAST_TAIL = r"(?:::(?:[A-Za-z_][A-Za-z0-9_\[\]]*\s*)+)?"


class ContractCheckError(Exception):
    """The contract, digest, or public signature surface drifted."""


@dataclass(frozen=True)
class Argument:
    name: str | None
    mode: str
    type_name: str
    default: str | None

    def as_json(self) -> dict[str, object]:
        payload: dict[str, object] = {
            "default": self.default,
            "mode": self.mode,
            "name": self.name,
            "type": self.type_name,
        }
        return payload


@dataclass(frozen=True)
class Signature:
    name: str
    arguments: tuple[Argument, ...]
    result: str
    source: str

    @property
    def identity(self) -> str:
        parts: list[str] = []
        for arg in self.arguments:
            if arg.mode == "out":
                continue
            rendered = arg.type_name
            if arg.mode == "variadic":
                rendered = f"variadic {rendered}"
            elif arg.mode == "inout":
                rendered = f"inout {rendered}"
            parts.append(rendered)
        return f"{self.name}({', '.join(parts)})"

    def as_json(self) -> dict[str, object]:
        return {
            "arguments": [arg.as_json() for arg in self.arguments],
            "identity": self.identity,
            "name": self.name,
            "result": self.result,
            "source": self.source,
        }


class _Scanner:
    def __init__(self, text: str, filename: str) -> None:
        self.text = text
        self.n = len(text)
        self.i = 0
        self.filename = filename

    def peek(self, offset: int = 0) -> str:
        index = self.i + offset
        if index < 0 or index >= self.n:
            return ""
        return self.text[index]

    def line(self) -> int:
        return self.text.count("\n", 0, self.i) + 1

    def fail(self, message: str) -> None:
        raise ContractCheckError(f"{self.filename}:{self.line()}: {message}")

    def skip_ws_and_comments(self) -> None:
        while self.i < self.n:
            char = self.text[self.i]
            if char.isspace():
                self.i += 1
                continue
            if char == "-" and self.peek(1) == "-":
                newline = self.text.find("\n", self.i)
                self.i = self.n if newline < 0 else newline + 1
                continue
            if char == "/" and self.peek(1) == "*":
                end = self.text.find("*/", self.i + 2)
                if end < 0:
                    self.fail("unterminated block comment")
                self.i = end + 2
                continue
            return

    def skip_quoted_string(self) -> None:
        if self.peek() != "'":
            self.fail("expected quoted string")
        self.i += 1
        while self.i < self.n:
            char = self.text[self.i]
            if char == "'" and self.peek(1) == "'":
                self.i += 2
                continue
            self.i += 1
            if char == "'":
                return
        self.fail("unterminated string")

    def skip_dollar_quote_if_present(self) -> bool:
        if self.peek() != "$":
            return False
        match = re.match(r"\$([A-Za-z_][A-Za-z0-9_]*)?\$", self.text[self.i:])
        if match is None:
            return False
        tag = match.group(0)
        end = self.text.find(tag, self.i + len(tag))
        if end < 0:
            self.fail(f"unterminated dollar quote {tag}")
        self.i = end + len(tag)
        return True

    def skip_ignorable_literal(self) -> bool:
        self.skip_ws_and_comments()
        if self.skip_dollar_quote_if_present():
            return True
        if self.peek() == "'":
            self.skip_quoted_string()
            return True
        return False

    def read_word(self) -> str | None:
        self.skip_ws_and_comments()
        if self.peek() == '"':
            self.i += 1
            start = self.i
            while self.i < self.n and self.peek() != '"':
                self.i += 1
            if self.peek() != '"':
                self.fail("unterminated quoted identifier")
            word = self.text[start:self.i]
            self.i += 1
            return word
        if not (self.peek().isalpha() or self.peek() == "_"):
            return None
        start = self.i
        self.i += 1
        while self.peek().isalnum() or self.peek() == "_":
            self.i += 1
        word = self.text[start:self.i]
        while self.peek() == "[" and self.peek(1) == "]":
            word += "[]"
            self.i += 2
        return word

    def read_balanced_parens(self) -> str:
        self.skip_ws_and_comments()
        if self.peek() != "(":
            self.fail("expected '('")
        start = self.i + 1
        depth = 0
        while self.i < self.n:
            if self.skip_ignorable_literal():
                continue
            char = self.peek()
            if char == "(":
                depth += 1
                self.i += 1
                continue
            if char == ")":
                depth -= 1
                self.i += 1
                if depth == 0:
                    return self.text[start:self.i - 1]
                continue
            if char == "":
                break
            self.i += 1
        self.fail("unterminated argument or type list")
        return ""


def _collapse(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def normalize_type(type_sql: str) -> str:
    text = _collapse(type_sql).lower()
    text = re.sub(r"\bpublic\.", "", text)
    arrays = 0
    while text.endswith("[]"):
        arrays += 1
        text = text[:-2].rstrip()
    if text == "timestamp with time zone":
        base = text
    elif text == "timestamp without time zone":
        base = text
    elif text == "time with time zone":
        base = text
    elif text == "time without time zone":
        base = text
    elif text == "double precision":
        base = text
    elif text == "character varying":
        base = text
    elif text in _TYPE_ALIASES:
        base = _TYPE_ALIASES[text]
    elif text == "timestamp":
        base = "timestamp without time zone"
    else:
        base = text
    return base + ("[]" * arrays)


def normalize_default(expr: str) -> str:
    text = _collapse(expr)
    text = re.sub(r"\s*::\s*", "::", text)
    if re.fullmatch(rf"(?i)null{_CAST_TAIL}", text):
        return "null"
    matched = re.fullmatch(rf"(?i)(true|false){_CAST_TAIL}", text)
    if matched:
        return matched.group(1).lower()
    matched = re.fullmatch(rf"(-?\d+){_CAST_TAIL}", text)
    if matched:
        return matched.group(1)
    matched = re.fullmatch(rf"('(?:[^']|'')*'){_CAST_TAIL}", text)
    if matched:
        return matched.group(1)
    return text.lower()


def _is_type_start(word: str) -> bool:
    base = word
    while base.endswith("[]"):
        base = base[:-2]
    return base.lower() in _TYPE_STARTS


def _split_top_level_commas(text: str, filename: str) -> list[str]:
    parts: list[str] = []
    start = 0
    depth = 0
    scanner = _Scanner(text, filename)
    while scanner.i < scanner.n:
        if scanner.skip_ignorable_literal():
            continue
        char = scanner.peek()
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
        elif char == "," and depth == 0:
            parts.append(text[start:scanner.i])
            start = scanner.i + 1
        scanner.i += 1
    tail = text[start:]
    if _collapse(tail):
        parts.append(tail)
    return parts


def _split_default(type_and_default: str, filename: str) -> tuple[str, str | None]:
    scanner = _Scanner(type_and_default, filename)
    depth = 0
    while scanner.i < scanner.n:
        if scanner.skip_ignorable_literal():
            continue
        if scanner.peek() == "(":
            depth += 1
            scanner.i += 1
            continue
        if scanner.peek() == ")":
            depth -= 1
            scanner.i += 1
            continue
        if depth == 0:
            mark = scanner.i
            word = scanner.read_word()
            if word is not None and word.lower() == "default":
                type_sql = type_and_default[:mark]
                default_sql = type_and_default[scanner.i:]
                return type_sql, default_sql
            continue
        scanner.i += 1
    return type_and_default, None


def parse_argument(raw: str, filename: str) -> Argument:
    text = raw.strip()
    if not text:
        raise ContractCheckError(f"{filename}: empty function argument")
    scanner = _Scanner(text, filename)
    mode = "in"
    word = scanner.read_word()
    if word is None:
        scanner.fail("expected argument")
    assert word is not None
    if word.lower() in _ARG_MODES:
        mode = word.lower()
        word = scanner.read_word()
        if word is None:
            scanner.fail("expected argument type")
        assert word is not None
    if _is_type_start(word):
        name = None
        remainder = word + text[scanner.i:]
    else:
        name = word.lower()
        remainder = text[scanner.i:]
    type_sql, default_sql = _split_default(remainder, filename)
    if not _collapse(type_sql):
        raise ContractCheckError(f"{filename}: argument is missing a type: {raw.strip()}")
    default = None if default_sql is None else normalize_default(default_sql)
    return Argument(
        name=name,
        mode=mode,
        type_name=normalize_type(type_sql),
        default=default,
    )


def _parse_returns(scanner: _Scanner) -> str:
    scanner.skip_ws_and_comments()
    word = scanner.read_word()
    if word is None or word.lower() != "returns":
        scanner.fail("expected RETURNS")
    chunks: list[str] = []
    depth = 0
    while scanner.i < scanner.n:
        if depth == 0 and scanner.skip_dollar_quote_if_present():
            scanner.fail("function body started before the return type ended")
        if scanner.peek() == "'":
            start = scanner.i
            scanner.skip_quoted_string()
            chunks.append(scanner.text[start:scanner.i])
            continue
        scanner.skip_ws_and_comments()
        if scanner.i >= scanner.n:
            break
        if scanner.peek() == "(":
            depth += 1
            chunks.append("(")
            scanner.i += 1
            continue
        if scanner.peek() == ")":
            if depth == 0:
                scanner.fail("unexpected ')' in return type")
            depth -= 1
            chunks.append(")")
            scanner.i += 1
            continue
        if scanner.peek() == ",":
            chunks.append(",")
            scanner.i += 1
            continue
        if depth == 0:
            mark = scanner.i
            word = scanner.read_word()
            if word is None:
                scanner.fail("unexpected token in return type")
            assert word is not None
            if word.lower() in _STOP_CLAUSES:
                scanner.i = mark
                break
            chunks.append(word)
            continue
        word = scanner.read_word()
        if word is None:
            chunks.append(scanner.peek())
            scanner.i += 1
            continue
        chunks.append(word)
    if depth != 0:
        scanner.fail("unterminated return type")
    rendered = _collapse(" ".join(chunks))
    if not rendered:
        scanner.fail("empty return type")
    return _normalize_result(rendered)


def _normalize_result(result: str) -> str:
    if result.lower().startswith("table"):
        match = re.match(r"(?i)table\s*\((.*)\)\s*$", result, re.DOTALL)
        if match is None:
            raise ContractCheckError(f"unsupported table result shape: {result}")
        columns = []
        for column in _split_top_level_commas(match.group(1), "<result>"):
            collapsed = _collapse(column)
            name, _, type_sql = collapsed.partition(" ")
            if not type_sql:
                raise ContractCheckError(f"table result column is missing a type: {collapsed}")
            columns.append(f"{name.lower()} {normalize_type(type_sql)}")
        return "table(" + ", ".join(columns) + ")"
    return normalize_type(result)


def _parse_qualified_name(scanner: _Scanner) -> tuple[str | None, str]:
    word = scanner.read_word()
    if word is None:
        scanner.fail("expected function name")
    assert word is not None
    scanner.skip_ws_and_comments()
    if scanner.peek() == ".":
        scanner.i += 1
        schema = word
        word = scanner.read_word()
        if word is None:
            scanner.fail("expected function name after schema")
        assert word is not None
        return schema.lower(), word.lower()
    return None, word.lower()


def _drop_identity(schema: str | None, name: str, arguments_sql: str, filename: str) -> str | None:
    if schema not in {None, "public"}:
        return None
    arguments = tuple(
        parse_argument(part, filename)
        for part in _split_top_level_commas(arguments_sql, filename)
    )
    return Signature(name=name, arguments=arguments, result="", source=filename).identity


def parse_sql_events(text: str, filename: str) -> list[tuple[str, Signature | str]]:
    """Ordered public-signature events: ``(\"create\", Signature)`` or ``(\"drop\", identity)``."""

    scanner = _Scanner(text, filename)
    events: list[tuple[str, Signature | str]] = []
    while scanner.i < scanner.n:
        if scanner.skip_ignorable_literal():
            continue
        word = scanner.read_word()
        if word is None:
            if scanner.i < scanner.n:
                scanner.i += 1
            continue
        lowered = word.lower()
        if lowered == "create":
            signature = _parse_create_function(scanner, filename)
            if signature is not None:
                events.append(("create", signature))
            continue
        if lowered == "drop":
            identity = _parse_drop_function_at(scanner, filename)
            if identity is not None:
                events.append(("drop", identity))
            continue
    return events


def _parse_create_function(scanner: _Scanner, filename: str) -> Signature | None:
    saved = scanner.i
    word = scanner.read_word()
    if word is not None and word.lower() == "or":
        replace = scanner.read_word()
        if replace is None or replace.lower() != "replace":
            scanner.i = saved
            return None
        word = scanner.read_word()
    if word is None or word.lower() != "function":
        scanner.i = saved
        return None
    schema, name = _parse_qualified_name(scanner)
    arguments_sql = scanner.read_balanced_parens()
    result = _parse_returns(scanner)
    if schema not in {None, "public"}:
        return None
    arguments = tuple(
        parse_argument(part, filename)
        for part in _split_top_level_commas(arguments_sql, filename)
    )
    return Signature(name=name, arguments=arguments, result=result, source=filename)


def _parse_drop_function_at(scanner: _Scanner, filename: str) -> str | None:
    saved = scanner.i
    word = scanner.read_word()
    if word is None or word.lower() != "function":
        scanner.i = saved
        return None
    lookahead = scanner.i
    maybe_if = scanner.read_word()
    if maybe_if is not None and maybe_if.lower() == "if":
        exists = scanner.read_word()
        if exists is None or exists.lower() != "exists":
            scanner.fail("expected EXISTS after DROP FUNCTION IF")
    else:
        scanner.i = lookahead
    schema, name = _parse_qualified_name(scanner)
    arguments_sql = scanner.read_balanced_parens()
    return _drop_identity(schema, name, arguments_sql, filename)


def load_ordered_signatures(sql_dir: Path) -> dict[str, Signature]:
    surface: dict[str, Signature] = {}
    for name in ORDERED_SQL:
        path = sql_dir / name
        if not path.is_file():
            raise ContractCheckError(f"ordered SQL file is missing: {name}")
        text = path.read_text(encoding="utf-8")
        for kind, payload in parse_sql_events(text, name):
            if kind == "drop":
                if not isinstance(payload, str):
                    raise ContractCheckError(f"{name}: drop event is missing an identity")
                surface.pop(payload, None)
                continue
            if not isinstance(payload, Signature):
                raise ContractCheckError(f"{name}: create event is missing a signature")
            surface[payload.identity] = payload
    return surface


def contract_digest(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def canonical_surface_document(
    *,
    source_sha256: str,
    signatures: dict[str, Signature],
) -> dict[str, object]:
    functions = [signatures[key].as_json() for key in sorted(signatures)]
    return {
        "contract": CONTRACT_ID,
        "functions": functions,
        "ordered_sql": list(ORDERED_SQL),
        "signature_fields": ["name", "arguments", "result"],
        "source": CONTRACT_RELATIVE.as_posix(),
        "source_sha256": source_sha256,
        "version": CONTRACT_VERSION,
    }


def canonical_json(payload: dict[str, object]) -> str:
    return json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def _argument_from_json(payload: object, identity: str) -> Argument:
    if not isinstance(payload, dict):
        raise ContractCheckError(f"{identity}: argument record is not an object")
    name = payload.get("name")
    mode = payload.get("mode")
    type_name = payload.get("type")
    default = payload.get("default")
    if name is not None and not isinstance(name, str):
        raise ContractCheckError(f"{identity}: argument name is not a string")
    if not isinstance(mode, str) or not isinstance(type_name, str):
        raise ContractCheckError(f"{identity}: argument mode and type are required")
    if default is not None and not isinstance(default, str):
        raise ContractCheckError(f"{identity}: argument default is not a string")
    return Argument(name=name, mode=mode, type_name=type_name, default=default)


def signatures_from_document(document: dict[str, object]) -> dict[str, Signature]:
    raw_functions = document.get("functions")
    if not isinstance(raw_functions, list):
        raise ContractCheckError("recorded surface is missing a functions array")
    recorded: dict[str, Signature] = {}
    for item in raw_functions:
        if not isinstance(item, dict):
            raise ContractCheckError("recorded function is not an object")
        identity = item.get("identity")
        name = item.get("name")
        result = item.get("result")
        source = item.get("source")
        if not isinstance(identity, str) or not isinstance(name, str) or not isinstance(result, str):
            raise ContractCheckError("recorded function is missing identity, name, or result")
        if not isinstance(source, str):
            raise ContractCheckError(f"{identity}: recorded source is missing")
        raw_arguments = item.get("arguments")
        if not isinstance(raw_arguments, list):
            raise ContractCheckError(f"{identity}: arguments are missing")
        arguments = tuple(_argument_from_json(arg, identity) for arg in raw_arguments)
        signature = Signature(name=name, arguments=arguments, result=result, source=source)
        if signature.identity != identity:
            raise ContractCheckError(
                f"recorded identity {identity} does not match its argument list ({signature.identity})"
            )
        recorded[identity] = signature
    return recorded


def compare_surfaces(
    recorded: dict[str, Signature],
    actual: dict[str, Signature],
) -> list[str]:
    """Fail-closed differences. Removals and result/argument changes are named."""

    failures: list[str] = []
    recorded_names: dict[str, list[str]] = {}
    actual_names: dict[str, list[str]] = {}
    for identity, signature in recorded.items():
        recorded_names.setdefault(signature.name, []).append(identity)
    for identity, signature in actual.items():
        actual_names.setdefault(signature.name, []).append(identity)

    seen_names: set[str] = set()
    for name in sorted(set(recorded_names) | set(actual_names)):
        seen_names.add(name)
        old = set(recorded_names.get(name, []))
        new = set(actual_names.get(name, []))
        if old == new:
            for identity in sorted(old):
                if recorded[identity].arguments != actual[identity].arguments:
                    failures.append(
                        f"changed: {identity} argument list does not match the recorded surface"
                    )
                if recorded[identity].result != actual[identity].result:
                    failures.append(
                        f"changed: {identity} result {recorded[identity].result!r} "
                        f"-> {actual[identity].result!r}"
                    )
            continue
        if old and new:
            failures.append(
                "changed: "
                + name
                + " recorded ["
                + ", ".join(sorted(old))
                + "] actual ["
                + ", ".join(sorted(new))
                + "]"
            )
            continue
        for identity in sorted(old - new):
            failures.append(f"removed: {identity}")
        for identity in sorted(new - old):
            failures.append(f"added: {identity}")
    return failures


def corpus_mismatches(text: str, actual: dict[str, Signature]) -> list[str]:
    known = set(actual)
    failures: list[str] = []
    seen: set[str] = set()
    for match in _CORPUS_SIGNATURE.finditer(text):
        name = match.group(1).lower()
        if name in _SQL_BUILTINS:
            continue
        raw_args = match.group(2) or ""
        arg_types = [
            normalize_type(part)
            for part in _split_top_level_commas(raw_args, "<corpus>")
            if _collapse(part)
        ]
        identity = f"{name}({', '.join(arg_types)})"
        if identity in seen:
            continue
        seen.add(identity)
        if identity in known:
            continue
        # A taught type-only identity that is not on the public surface is a
        # removed or foreign signature. Fail closed. Do not echo corpus text.
        failures.append(
            f"corpus teaches {identity}, which is not on the recorded public surface"
        )
    return failures


def load_surface_document(path: Path) -> dict[str, object]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ContractCheckError(f"recorded surface is missing: {path.name}") from exc
    except json.JSONDecodeError as exc:
        raise ContractCheckError(f"recorded surface is not JSON: {path.name}") from exc
    if not isinstance(payload, dict):
        raise ContractCheckError("recorded surface must be a JSON object")
    return payload


def check_contract(
    *,
    contract_path: Path,
    surface_path: Path,
    sql_dir: Path,
    corpus_path: Path | None = None,
) -> dict[str, object]:
    contract_text = contract_path.read_text(encoding="utf-8")
    if VERSION_MARKER not in contract_text:
        raise ContractCheckError(
            f"sanitized contract is missing the stable marker {VERSION_MARKER!r}"
        )
    digest = contract_digest(contract_text)
    document = load_surface_document(surface_path)
    if document.get("contract") != CONTRACT_ID:
        raise ContractCheckError("recorded surface contract id does not match")
    if document.get("version") != CONTRACT_VERSION:
        raise ContractCheckError("recorded surface version does not match the sanitized contract")
    if document.get("source") != CONTRACT_RELATIVE.as_posix():
        raise ContractCheckError("recorded surface source path does not match the sanitized contract")
    recorded_digest = document.get("source_sha256")
    if not isinstance(recorded_digest, str) or recorded_digest != digest:
        raise ContractCheckError(
            "content digest does not match docs/03-agent-operations.md; "
            "the checker recomputed SHA-256 and failed closed"
        )
    if document.get("ordered_sql") != list(ORDERED_SQL):
        raise ContractCheckError("recorded ordered SQL list does not match the checker")
    recorded = signatures_from_document(document)
    actual = load_ordered_signatures(sql_dir)
    failures = compare_surfaces(recorded, actual)
    if corpus_path is not None:
        data = corpus_path.read_bytes()
        if len(data) > MAX_CORPUS_BYTES:
            raise ContractCheckError(
                "operator corpus exceeds 2 MiB; pass a focused local file, not a live export dump"
            )
        if b"\x00" in data:
            raise ContractCheckError("operator corpus is not a text file")
        failures.extend(corpus_mismatches(data.decode("utf-8"), actual))
    if failures:
        raise ContractCheckError("public function signature drift:\n" + "\n".join(failures))
    return {
        "contract": "agent-operations-contract/1.0.0",
        "digest": digest,
        "signatures": len(actual),
    }


def _default_root() -> Path:
    return Path(__file__).resolve().parents[1]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=None, help="repository root")
    parser.add_argument("--contract", type=Path, default=None, help="sanitized contract markdown")
    parser.add_argument("--surface", type=Path, default=None, help="recorded signature surface JSON")
    parser.add_argument("--sql-dir", type=Path, default=None, help="directory of ordered SQL files")
    parser.add_argument(
        "--corpus",
        type=Path,
        default=None,
        help="optional local instruction corpus to scan; never fetched",
    )
    parser.add_argument(
        "--emit-surface",
        action="store_true",
        help="print the surface JSON for the current contract and SQL, then exit",
    )
    args = parser.parse_args(argv)
    root = (args.root or _default_root()).resolve()
    contract_path = (args.contract or (root / CONTRACT_RELATIVE)).resolve()
    surface_path = (args.surface or (root / SURFACE_RELATIVE)).resolve()
    sql_dir = (args.sql_dir or (root / "sql")).resolve()
    try:
        if args.emit_surface:
            text = contract_path.read_text(encoding="utf-8")
            if VERSION_MARKER not in text:
                raise ContractCheckError(
                    f"sanitized contract is missing the stable marker {VERSION_MARKER!r}"
                )
            payload = canonical_surface_document(
                source_sha256=contract_digest(text),
                signatures=load_ordered_signatures(sql_dir),
            )
            sys.stdout.write(canonical_json(payload))
            return 0
        result = check_contract(
            contract_path=contract_path,
            surface_path=surface_path,
            sql_dir=sql_dir,
            corpus_path=args.corpus,
        )
    except ContractCheckError as exc:
        print(f"agent-operations contract check failed: {exc}", file=sys.stderr)
        return 1
    except FileNotFoundError as exc:
        print(f"agent-operations contract check failed: {exc.filename} not found", file=sys.stderr)
        return 1
    print(
        f"{result['contract']} digest={result['digest']} signatures={result['signatures']} ok"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
