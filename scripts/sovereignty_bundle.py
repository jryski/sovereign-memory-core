"""Deterministic, safe primitives for sovereignty export bundles."""

from __future__ import annotations

import base64
import datetime as dt
from dataclasses import dataclass
from decimal import Decimal
import hashlib
import io
import json
from pathlib import PurePosixPath
import tarfile
from typing import Any, Iterable
from uuid import UUID


def _reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key!r}")
        result[key] = value
    return result


def _reject_constant(value: str) -> None:
    raise ValueError(f"non-finite JSON number: {value}")


def _parse_int(value: str) -> int:
    if value == "-0":
        raise ValueError("negative zero is not canonical")
    parsed = int(value)
    _validate_jcs_integer(parsed)
    return parsed


def _reject_float(value: str) -> None:
    raise ValueError(f"floating-point JSON numbers are outside the canonical subset: {value}")


def parse_canonical_json_bytes(raw: bytes) -> Any:
    """Decode exactly one canonical UTF-8 JSON value terminated by LF."""
    if not raw.endswith(b"\n") or raw.endswith(b"\r\n") or b"\n" in raw[:-1]:
        raise ValueError("canonical JSON must contain exactly one LF terminator")
    try:
        value = json.loads(
            raw[:-1].decode("utf-8", errors="strict"),
            object_pairs_hook=_reject_duplicate_keys,
            parse_constant=_reject_constant,
            parse_int=_parse_int,
            parse_float=_reject_float,
        )
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise ValueError("invalid canonical JSON") from exc
    if canonical_json_bytes(value) != raw:
        raise ValueError("JSON input is not in canonical form")
    return value


def _validate_string(value: str) -> None:
    try:
        value.encode("utf-8", errors="strict")
    except UnicodeEncodeError as exc:
        raise ValueError("canonical JSON strings must not contain unpaired surrogates") from exc


def _validate_jcs_integer(value: int) -> None:
    if not (-(2**53) + 1 <= value <= (2**53) - 1):
        raise ValueError("canonical JSON integer exceeds the lossless JCS range")


def _validate_json_value(value: Any) -> None:
    if value is None or isinstance(value, bool):
        return
    if isinstance(value, int):
        _validate_jcs_integer(value)
        return
    if isinstance(value, str):
        _validate_string(value)
    elif isinstance(value, dict):
        if any(not isinstance(key, str) for key in value):
            raise TypeError("canonical JSON object keys must be strings")
        for key, child in value.items():
            _validate_string(key)
            _validate_json_value(child)
    elif isinstance(value, list):
        for child in value:
            _validate_json_value(child)
    else:
        raise TypeError(f"value type is outside the canonical JSON subset: {type(value).__name__}")


def _utf16_sort_key(value: str) -> bytes:
    return value.encode("utf-16-be")


def _encode_canonical_json(value: Any) -> str:
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return "[" + ",".join(_encode_canonical_json(child) for child in value) + "]"
    keys = sorted(value, key=_utf16_sort_key)
    return "{" + ",".join(
        f"{json.dumps(key, ensure_ascii=False)}:{_encode_canonical_json(value[key])}"
        for key in keys
    ) + "}"


def canonical_json_bytes(value: Any) -> bytes:
    """Encode the supported fail-closed RFC 8785 subset as UTF-8 plus LF.

    This stdlib-only slice supports null, booleans, lossless I-JSON-range
    integers, strings, arrays, and objects with RFC 8785 UTF-16 member
    ordering. Floats and Decimal are rejected because Python's stdlib does not
    provide ECMAScript number formatting; this function therefore does not
    claim full float-capable JCS.
    """
    _validate_json_value(value)
    return (_encode_canonical_json(value) + "\n").encode("utf-8")


_PG_TYPE_TAGS = {
    "text": "text", "varchar": "text", "character varying": "text",
    "char": "text", "character": "text", "bpchar": "text",
    "uuid": "uuid",
    "timestamptz": "timestamptz", "timestamp with time zone": "timestamptz",
    "timestamp": "timestamp", "timestamp without time zone": "timestamp",
    "date": "date", "time": "time", "time without time zone": "time",
    "smallint": "int", "int2": "int", "integer": "int", "int4": "int",
    "bigint": "int", "int8": "int",
    "numeric": "numeric", "decimal": "numeric",
    "boolean": "bool", "bool": "bool", "text[]": "text[]", "bytea": "bytea",
    "json": "json", "jsonb": "json",
}


@dataclass(frozen=True)
class PgTextArray:
    """A PostgreSQL text array with catalog-derived shape metadata."""

    values: Iterable[Any]
    dimensions: int = 1
    lower_bound: int = 1

    def __post_init__(self) -> None:
        object.__setattr__(self, "values", tuple(self.values))


@dataclass(frozen=True)
class PgEnumCatalog:
    """Catalog-derived identity and ordered labels for one PostgreSQL enum."""

    type_name: str
    labels: Iterable[str]

    def __post_init__(self) -> None:
        if not isinstance(self.type_name, str) or not self.type_name.strip():
            raise TypeError("enum catalog type identity must be a nonempty string")
        labels = tuple(self.labels)
        if not labels or any(not isinstance(label, str) for label in labels):
            raise TypeError("enum catalog labels must be nonempty strings")
        if len(set(labels)) != len(labels):
            raise ValueError("enum catalog labels must be unique")
        for label in labels:
            _validate_string(label)
        object.__setattr__(self, "labels", labels)


@dataclass(frozen=True)
class PgJsonText:
    """An explicitly textual, already-canonical PostgreSQL JSON value."""

    raw: bytes


@dataclass(frozen=True)
class PgJsonValue:
    """An explicitly decoded PostgreSQL JSON value."""

    value: Any


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise TypeError(message)


def encode_pg_scalar(
    pg_type: str,
    value: Any,
    *,
    enum_catalog: Iterable[PgEnumCatalog] = (),
) -> Any:
    """Encode a supported PostgreSQL scalar in the normative bundle shape."""
    if not isinstance(pg_type, str):
        raise TypeError("PostgreSQL type name must be str")
    normalized_type = pg_type.strip().lower()
    catalog_by_type: dict[str, PgEnumCatalog] = {}
    for entry in enum_catalog:
        _require(isinstance(entry, PgEnumCatalog), "enum catalog entries require PgEnumCatalog")
        identity = entry.type_name.strip().lower()
        if identity in catalog_by_type:
            raise ValueError(f"duplicate enum catalog identity: {entry.type_name!r}")
        catalog_by_type[identity] = entry
    if normalized_type == "enum":
        raise TypeError("generic enum claims are unsupported; use a catalog type identity")
    if normalized_type in catalog_by_type:
        tag = "enum"
    else:
        try:
            tag = _PG_TYPE_TAGS[normalized_type]
        except KeyError as exc:
            raise TypeError(f"unsupported PostgreSQL type: {pg_type!r}") from exc
    if value is None:
        return None

    if tag == "text":
        _require(isinstance(value, str), "text requires str")
        _validate_string(value)
        encoded: Any = value
    elif tag == "uuid":
        _require(isinstance(value, UUID), "uuid requires UUID")
        encoded = str(value)
    elif tag == "timestamptz":
        _require(isinstance(value, dt.datetime), "timestamptz requires datetime")
        _require(value.tzinfo is not None and value.utcoffset() is not None, "timestamptz requires an aware datetime")
        encoded = value.astimezone(dt.timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")
    elif tag == "timestamp":
        _require(isinstance(value, dt.datetime), "timestamp requires datetime")
        _require(value.tzinfo is None or value.utcoffset() is None, "timestamp requires a naive datetime")
        encoded = value.isoformat(timespec="microseconds")
    elif tag == "date":
        _require(isinstance(value, dt.date) and not isinstance(value, dt.datetime), "date requires date")
        encoded = value.isoformat()
    elif tag == "time":
        _require(isinstance(value, dt.time), "time requires time")
        _require(value.tzinfo is None or value.utcoffset() is None, "time requires a naive time")
        encoded = value.isoformat(timespec="microseconds")
    elif tag == "int":
        _require(isinstance(value, int) and not isinstance(value, bool), "integer type requires int")
        encoded = str(value)
    elif tag == "numeric":
        _require(isinstance(value, Decimal), "numeric requires Decimal")
        _require(value.is_finite(), "numeric must be finite")
        _require(not (value.is_zero() and value.is_signed()), "numeric must not be negative zero")
        encoded = format(value, "f")
        if "." in encoded:
            encoded = encoded.rstrip("0").rstrip(".")
        if value.is_zero():
            encoded = "0"
    elif tag == "bool":
        _require(isinstance(value, bool), "boolean requires bool")
        encoded = value
    elif tag == "enum":
        _require(isinstance(value, str), "enum requires str")
        _validate_string(value)
        _require(value in catalog_by_type[normalized_type].labels, "enum label is absent from catalog metadata")
        encoded = value
    elif tag == "json":
        if isinstance(value, PgJsonText):
            _require(isinstance(value.raw, bytes), "JSON text requires bytes")
            if b"\n" in value.raw or b"\r" in value.raw:
                raise ValueError("JSON text must be one canonical value without a line terminator")
            encoded = parse_canonical_json_bytes(value.raw + b"\n")
        elif isinstance(value, PgJsonValue):
            _validate_json_value(value.value)
            encoded = value.value
        else:
            raise TypeError("json/jsonb requires PgJsonText or PgJsonValue to disambiguate strings")
    elif tag == "text[]":
        _require(isinstance(value, PgTextArray), "text[] requires validated array metadata")
        _require(
            isinstance(value.dimensions, int)
            and not isinstance(value.dimensions, bool)
            and value.dimensions == 1,
            "text[] must be one-dimensional",
        )
        _require(
            isinstance(value.lower_bound, int)
            and not isinstance(value.lower_bound, bool)
            and value.lower_bound == 1,
            "text[] must have lower bound 1",
        )
        _require(
            all(item is None or isinstance(item, str) for item in value.values),
            "text[] elements must be str or null",
        )
        for item in value.values:
            if item is not None:
                _validate_string(item)
        encoded = list(value.values)
    else:
        _require(isinstance(value, (bytes, bytearray, memoryview)), "bytea requires bytes-like data")
        return {"$bytea": base64.b64encode(bytes(value)).decode("ascii")}
    return encoded


def _validate_jsonl_row(row: Any) -> None:
    if not isinstance(row, dict):
        raise TypeError("JSONL row must be an object")
    if set(row) != {"pk", "row"}:
        raise ValueError("JSONL row must contain exactly 'pk' and 'row'")
    if not isinstance(row["pk"], list):
        raise TypeError("JSONL row 'pk' must be an array")
    if not isinstance(row["row"], dict):
        raise TypeError("JSONL row 'row' must be an object")


def canonical_jsonl_bytes(rows: Any) -> bytes:
    """Encode normative ``pk``/``row`` objects as canonical JSON Lines."""
    output = bytearray()
    for row in rows:
        _validate_jsonl_row(row)
        output.extend(canonical_json_bytes(row))
    return bytes(output)


def jsonl_row_digest(raw_row: bytes) -> str:
    """Return the SHA-256 hex digest of one already-canonical raw JSONL row."""
    if not isinstance(raw_row, bytes):
        raise TypeError("raw JSONL row must be bytes")
    row = parse_canonical_json_bytes(raw_row)
    _validate_jsonl_row(row)
    return hashlib.sha256(raw_row).hexdigest()


def _validate_bundle_path(path: str) -> None:
    if not isinstance(path, str):
        raise TypeError("bundle path must be str")
    if not path or "\x00" in path or "\\" in path or path.startswith("/"):
        raise ValueError(f"unsafe bundle path: {path!r}")
    parts = path.split("/")
    if any(part in ("", ".", "..") for part in parts):
        raise ValueError(f"unsafe bundle path: {path!r}")
    if PurePosixPath(path).as_posix() != path:
        raise ValueError(f"non-canonical bundle path: {path!r}")
    try:
        path.encode("utf-8", errors="strict")
    except UnicodeEncodeError as exc:
        raise ValueError("bundle path is not valid UTF-8") from exc


_USTAR_PATH_PROFILE_MAX_BYTES = 255
MAX_ARCHIVE_SIZE = 1 << 30


def write_ustar(entries: Iterable[tuple[str, bytes]]) -> bytes:
    """Build a deterministic uncompressed POSIX ustar archive of regular files."""
    checked: list[tuple[str, bytes]] = []
    exact: set[str] = set()
    folded: set[str] = set()
    for path, content in entries:
        _validate_bundle_path(path)
        if len(path.encode("utf-8")) > _USTAR_PATH_PROFILE_MAX_BYTES:
            raise ValueError(f"bundle path exceeds the 255-byte profile: {path!r}")
        if path in exact:
            raise ValueError(f"duplicate bundle path: {path!r}")
        folded_path = path.casefold()
        if folded_path in folded:
            raise ValueError(f"case-colliding bundle path: {path!r}")
        if not isinstance(content, bytes):
            raise TypeError(f"bundle content for {path!r} must be bytes")
        exact.add(path)
        folded.add(folded_path)
        checked.append((path, content))

    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w:", format=tarfile.USTAR_FORMAT, encoding="utf-8") as archive:
        for path, content in sorted(checked, key=lambda item: item[0].encode("utf-8")):
            info = tarfile.TarInfo(path)
            info.size = len(content)
            info.mode = 0o644
            info.mtime = 0
            info.uid = 0
            info.gid = 0
            info.uname = ""
            info.gname = ""
            info.type = tarfile.REGTYPE
            try:
                archive.addfile(info, io.BytesIO(content))
            except (ValueError, UnicodeError) as exc:
                raise ValueError(f"path cannot be represented in POSIX ustar: {path!r}") from exc
    return output.getvalue()


@dataclass(frozen=True)
class ArchiveMember:
    """A regular-file member approved by archive preflight."""

    path: str
    size: int
    data_offset: int


def _canonical_ustar_header(path: str, size: int) -> bytes:
    info = tarfile.TarInfo(path)
    info.size = size
    info.mode = 0o644
    info.mtime = 0
    info.uid = 0
    info.gid = 0
    info.uname = ""
    info.gname = ""
    info.type = tarfile.REGTYPE
    try:
        return info.tobuf(
            format=tarfile.USTAR_FORMAT,
            encoding="utf-8",
            errors="strict",
        )
    except (ValueError, UnicodeError) as exc:
        raise ValueError(f"path cannot be represented in POSIX ustar: {path!r}") from exc


def _tar_string(field: bytes, label: str) -> str:
    value, separator, remainder = field.partition(b"\0")
    if separator and any(remainder):
        raise ValueError(f"non-zero bytes after {label} terminator")
    try:
        return value.decode("utf-8", errors="strict")
    except UnicodeDecodeError as exc:
        raise ValueError(f"{label} is not valid UTF-8") from exc


def _tar_octal(field: bytes, label: str) -> int:
    stripped = field.rstrip(b"\0 ").lstrip(b" ")
    if not stripped or any(byte not in b"01234567" for byte in stripped):
        raise ValueError(f"invalid POSIX octal {label}")
    return int(stripped, 8)


def _checked_limit(name: str, value: int) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise ValueError(f"{name} must be a non-negative integer")
    return value


def validate_ustar(
    raw: bytes,
    *,
    max_archive_size: int = MAX_ARCHIVE_SIZE,
    max_members: int = 10_000,
    max_path_bytes: int = 255,
    max_member_size: int = 1 << 29,
    max_total_size: int = 1 << 30,
) -> tuple[ArchiveMember, ...]:
    """Preflight a bounded canonical ustar archive without extracting anything."""
    if not isinstance(raw, bytes):
        raise TypeError("archive must be bytes")
    limits = {
        "max_archive_size": _checked_limit("max_archive_size", max_archive_size),
        "max_members": _checked_limit("max_members", max_members),
        "max_path_bytes": min(
            _USTAR_PATH_PROFILE_MAX_BYTES,
            _checked_limit("max_path_bytes", max_path_bytes),
        ),
        "max_member_size": _checked_limit("max_member_size", max_member_size),
        "max_total_size": _checked_limit("max_total_size", max_total_size),
    }
    if len(raw) > limits["max_archive_size"]:
        raise ValueError("archive exceeds size limit")
    if len(raw) < 1024 or len(raw) % 512:
        raise ValueError("archive is not complete 512-byte POSIX records")

    members: list[ArchiveMember] = []
    seen: set[str] = set()
    folded: set[str] = set()
    total_size = 0
    offset = 0
    zero = b"\0" * 512
    while offset + 512 <= len(raw) and raw[offset : offset + 512] != zero:
        header = raw[offset : offset + 512]
        stored_checksum = _tar_octal(header[148:156], "checksum")
        checksum_header = header[:148] + b" " * 8 + header[156:]
        if sum(checksum_header) != stored_checksum:
            raise ValueError("invalid ustar header checksum")
        if header[257:263] != b"ustar\0" or header[263:265] != b"00":
            raise ValueError("archive is not POSIX ustar")
        if header[156:157] not in (b"0", b"\0"):
            raise ValueError("archive contains a non-regular or extension member")
        if any(header[157:257]) or any(header[329:345]):
            raise ValueError("regular ustar member contains link or device metadata")

        name = _tar_string(header[0:100], "name")
        prefix = _tar_string(header[345:500], "prefix")
        path = f"{prefix}/{name}" if prefix else name
        _validate_bundle_path(path)
        path_bytes = path.encode("utf-8")
        if len(path_bytes) > limits["max_path_bytes"]:
            raise ValueError("archive member path exceeds limit")
        if path in seen:
            raise ValueError(f"duplicate archive path: {path!r}")
        folded_path = path.casefold()
        if folded_path in folded:
            raise ValueError(f"case-colliding archive path: {path!r}")
        if members and path_bytes <= members[-1].path.encode("utf-8"):
            raise ValueError("archive member paths are not in canonical sorted order")

        size = _tar_octal(header[124:136], "size")
        if size > limits["max_member_size"]:
            raise ValueError("archive member exceeds size limit")
        total_size += size
        if total_size > limits["max_total_size"]:
            raise ValueError("archive contents exceed total size limit")
        if len(members) + 1 > limits["max_members"]:
            raise ValueError("archive contains too many members")
        if _tar_octal(header[100:108], "mode") != 0o644:
            raise ValueError("archive member mode is not canonical")
        if any(_tar_octal(header[start:end], label) for start, end, label in (
            (108, 116, "uid"), (116, 124, "gid"), (136, 148, "mtime")
        )):
            raise ValueError("archive member ownership or timestamp is not canonical")
        if _tar_string(header[265:297], "uname") or _tar_string(header[297:329], "gname"):
            raise ValueError("archive member owner names are not empty")
        if header != _canonical_ustar_header(path, size):
            raise ValueError("archive member header is not the exact canonical encoding")

        data_offset = offset + 512
        padded_size = (size + 511) // 512 * 512
        next_offset = data_offset + padded_size
        if next_offset > len(raw):
            raise ValueError("archive member data is truncated")
        if any(memoryview(raw)[data_offset + size : next_offset]):
            raise ValueError("archive member padding is not zero-filled")
        members.append(ArchiveMember(path, size, data_offset))
        seen.add(path)
        folded.add(folded_path)
        offset = next_offset

    if offset + 1024 > len(raw) or raw[offset : offset + 1024] != zero + zero:
        raise ValueError("archive lacks two zero end-of-archive records")
    canonical_size = (
        (offset + 1024 + tarfile.RECORDSIZE - 1) // tarfile.RECORDSIZE
    ) * tarfile.RECORDSIZE
    if len(raw) != canonical_size:
        raise ValueError("archive has a noncanonical trailing record count")
    if any(memoryview(raw)[offset:]):
        raise ValueError("archive contains non-zero trailing records")
    return tuple(members)
