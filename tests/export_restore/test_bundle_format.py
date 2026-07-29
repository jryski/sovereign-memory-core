import datetime as dt
from decimal import Decimal
import io
import tarfile
import unittest
from unittest import mock
from uuid import UUID

from scripts import sovereignty_bundle as bundle


class CanonicalJsonTests(unittest.TestCase):
    def test_canonical_json_is_utf8_lf_sorted_and_compact(self):
        value = {"z": "snowman ☃", "a": [2, 1]}
        self.assertEqual(
            bundle.canonical_json_bytes(value),
            b'{"a":[2,1],"z":"snowman \xe2\x98\x83"}\n',
        )

    def test_strict_json_rejects_ambiguous_or_noncanonical_input(self):
        rejected = (
            b'{"a":1,"a":2}\n',
            b'{"a":NaN}\n',
            b'{"a":Infinity}\n',
            b'{"a":-0}\n',
            b'{"a":-0.0}\n',
            b'{"a":1}\r\n',
            b'{"a":1}\r \n',
            b'{"a":1}',
            b'\xef\xbb\xbf{"a":1}\n',
            b'{ "a":1}\n',
            b'\xff\n',
        )
        for raw in rejected:
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                bundle.parse_canonical_json_bytes(raw)
        self.assertEqual(bundle.parse_canonical_json_bytes(b'{"a":1}\n'), {"a": 1})

    def test_canonical_json_encoder_rejects_nonfinite_negative_zero_and_bad_keys(self):
        for value in (
            float("nan"), float("inf"), 1.5, -0.0, Decimal("1.5"),
            {"nested": [-0.0]}, {1: "bad"},
        ):
            with self.subTest(value=value), self.assertRaises((TypeError, ValueError)):
                bundle.canonical_json_bytes(value)

    def test_canonical_json_orders_object_keys_by_utf16_code_units(self):
        # U+1F600 sorts before U+E000 by UTF-16 code units, unlike code-point order.
        value = {"\ue000": "bmp", "\U0001f600": "astral"}
        self.assertEqual(
            bundle.canonical_json_bytes(value),
            '{"😀":"astral","":"bmp"}\n'.encode(),
        )

    def test_canonical_json_integers_are_limited_to_lossless_jcs_range(self):
        safe = (-(2**53) + 1, (2**53) - 1)
        for value in safe:
            with self.subTest(value=value):
                self.assertEqual(bundle.parse_canonical_json_bytes(bundle.canonical_json_bytes(value)), value)
        for value in (-(2**53), 2**53):
            with self.subTest(value=value), self.assertRaises(ValueError):
                bundle.canonical_json_bytes(value)
            with self.subTest(value=value), self.assertRaises(ValueError):
                bundle.parse_canonical_json_bytes(f"{value}\n".encode("ascii"))

    def test_canonical_json_rejects_unpaired_surrogates_with_stable_value_error(self):
        for value in ({"bad\ud800": "key"}, {"bad": "value\udfff"}):
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, "surrogate"):
                bundle.canonical_json_bytes(value)
        for raw in (b'{"\\ud800":"key"}\n', b'{"bad":"\\udfff"}\n'):
            with self.subTest(raw=raw), self.assertRaisesRegex(ValueError, "surrogate"):
                bundle.parse_canonical_json_bytes(raw)


class PostgreSqlScalarTests(unittest.TestCase):
    def test_supported_scalars_have_exact_normative_shapes(self):
        utc_plus_two = dt.timezone(dt.timedelta(hours=2))
        cases = (
            ("text", None, None),
            ("text", "hello", "hello"),
            ("char", "x", "x"),
            ("character", "y", "y"),
            ("bpchar", "z", "z"),
            ("uuid", UUID("12345678-1234-5678-9234-567812345678"), "12345678-1234-5678-9234-567812345678"),
            ("timestamptz", dt.datetime(2025, 1, 2, 3, 4, 5, 6000, utc_plus_two), "2025-01-02T01:04:05.006000Z"),
            ("timestamp", dt.datetime(2025, 1, 2, 3, 4, 5, 6000), "2025-01-02T03:04:05.006000"),
            ("date", dt.date(2025, 1, 2), "2025-01-02"),
            ("time", dt.time(3, 4, 5, 6000), "03:04:05.006000"),
            ("int8", 42, "42"),
            ("numeric", Decimal("12.340"), "12.34"),
            ("numeric", Decimal("0.00"), "0"),
            ("numeric", Decimal("1.2300E+3"), "1230"),
            ("numeric", Decimal("1E-7"), "0.0000001"),
            ("bool", True, True),
            ("text[]", bundle.PgTextArray(["a", None, "☃"]), ["a", None, "☃"]),
            ("bytea", b"\x00\xff", {"$bytea": "AP8="}),
        )
        for pg_type, value, expected in cases:
            with self.subTest(pg_type=pg_type):
                self.assertEqual(bundle.encode_pg_scalar(pg_type, value), expected)

    def test_unsupported_or_mismatched_postgresql_values_fail_closed(self):
        rejected = (
            ("enum", "not catalog mapped"),
            ("example_status", "not catalog mapped"),
            ("jsonb", {}),
            ("jsonb", None),
            ("int8", True),
            ("numeric", Decimal("NaN")),
            ("numeric", Decimal("-0.00")),
            ("timestamp", dt.datetime(2025, 1, 1, tzinfo=dt.timezone.utc)),
            ("timestamptz", dt.datetime(2025, 1, 1)),
            ("text", "bad\ud800"),
            ("text[]", bundle.PgTextArray(["bad\udfff"])),
            ("text[]", bundle.PgTextArray([["nested"]])),
            ("text[]", bundle.PgTextArray(["ok"], dimensions=2)),
            ("text[]", bundle.PgTextArray(["ok"], lower_bound=0)),
            ("text[]", ["missing array metadata"]),
            ("bytea", "not bytes"),
            (None, "not a type name"),
        )
        for pg_type, value in rejected:
            with self.subTest(pg_type=pg_type, value=value), self.assertRaises((TypeError, ValueError)):
                bundle.encode_pg_scalar(pg_type, value)


class JsonLinesTests(unittest.TestCase):
    def test_jsonl_and_raw_row_digest_are_byte_deterministic(self):
        self.assertEqual(
            bundle.canonical_jsonl_bytes(({"b": 2}, {"a": 1})),
            b'{"b":2}\n{"a":1}\n',
        )
        raw_row = b'{"a":1}\n'
        self.assertEqual(
            bundle.jsonl_row_digest(raw_row),
            "e346432021b04179518d9614f3560ccd71354a4ee101ddcb893d6959a9d6301c",
        )
        with self.assertRaises(ValueError):
            bundle.jsonl_row_digest(b'{ "a": 1 }\n')


class UstarWriterTests(unittest.TestCase):
    def test_writer_is_sorted_uncompressed_posix_ustar_with_fixed_metadata(self):
        first = bundle.write_ustar((("z.txt", b"z"), ("a/data.json", b"{}\n")))
        second = bundle.write_ustar((("a/data.json", b"{}\n"), ("z.txt", b"z")))
        self.assertEqual(first, second)
        self.assertFalse(first.startswith(b"\x1f\x8b"))
        with tarfile.open(fileobj=io.BytesIO(first), mode="r:") as archive:
            members = archive.getmembers()
            self.assertEqual([member.name for member in members], ["a/data.json", "z.txt"])
            for member in members:
                self.assertTrue(member.isfile())
                self.assertEqual(member.mode, 0o644)
                self.assertEqual((member.mtime, member.uid, member.gid), (0, 0, 0))
                self.assertEqual((member.uname, member.gname), ("", ""))
                self.assertEqual(member.pax_headers, {})
        self.assertEqual(first[257:265], b"ustar\x0000")
        invalid_sets = (
            (("../escape", b"x"),), (("/absolute", b"x"),), (("a//b", b"x"),),
            (("a/./b", b"x"),), (("a\\b", b"x"),), (("", b"x"),),
            (("same", b"1"), ("same", b"2")),
            (("Data/x", b"1"), ("data/X", b"2")),
            (("ok", "not bytes"),),
        )
        for entries in invalid_sets:
            with self.subTest(entries=entries), self.assertRaises((TypeError, ValueError)):
                bundle.write_ustar(entries)


class ArchiveValidationTests(unittest.TestCase):
    @staticmethod
    def _archive_with(*members, tar_format=tarfile.USTAR_FORMAT):
        output = io.BytesIO()
        with tarfile.open(fileobj=output, mode="w:", format=tar_format) as archive:
            for member, data in members:
                archive.addfile(member, io.BytesIO(data) if member.isfile() else None)
        return output.getvalue()

    @staticmethod
    def _mutate_header(raw, start, replacement):
        mutated = bytearray(raw)
        mutated[start:start + len(replacement)] = replacement
        mutated[148:156] = b"        "
        checksum = sum(mutated[:512])
        mutated[148:156] = f"{checksum:06o}\0 ".encode("ascii")
        return bytes(mutated)

    def test_preflight_accepts_only_bounded_safe_regular_ustar_members(self):
        raw = bundle.write_ustar((("a.txt", b"abc"), ("b.txt", b"de")))
        members = bundle.validate_ustar(
            raw, max_archive_size=20_000, max_members=2,
            max_path_bytes=20, max_member_size=3, max_total_size=5,
        )
        self.assertEqual([(m.path, m.size) for m in members], [("a.txt", 3), ("b.txt", 2)])

        limit_cases = (
            {"max_archive_size": len(raw) - 1}, {"max_members": 1},
            {"max_path_bytes": 4}, {"max_member_size": 2}, {"max_total_size": 4},
        )
        for limits in limit_cases:
            with self.subTest(limits=limits), self.assertRaises(ValueError):
                bundle.validate_ustar(raw, **limits)

        unsafe = tarfile.TarInfo("../escape")
        unsafe.size = 1
        symlink = tarfile.TarInfo("link")
        symlink.type = tarfile.SYMTYPE
        symlink.linkname = "a.txt"
        device = tarfile.TarInfo("device")
        device.type = tarfile.CHRTYPE
        hardlink = tarfile.TarInfo("hardlink")
        hardlink.type = tarfile.LNKTYPE
        hardlink.linkname = "target"
        fifo = tarfile.TarInfo("fifo")
        fifo.type = tarfile.FIFOTYPE
        sparse = tarfile.TarInfo("sparse")
        sparse.type = tarfile.GNUTYPE_SPARSE
        duplicate_a = tarfile.TarInfo("same")
        duplicate_a.size = 1
        duplicate_b = tarfile.TarInfo("same")
        duplicate_b.size = 1
        pax = tarfile.TarInfo("pax.txt")
        pax.size = 1
        pax.pax_headers = {"comment": "extension forbidden"}
        hostile_archives = (
            self._archive_with((unsafe, b"x")),
            self._archive_with((symlink, b"")),
            self._archive_with((device, b"")),
            self._archive_with((hardlink, b"")),
            self._archive_with((fifo, b"")),
            self._archive_with((sparse, b""), tar_format=tarfile.GNU_FORMAT),
            self._archive_with((tarfile.TarInfo("g" * 101), b""), tar_format=tarfile.GNU_FORMAT),
            self._archive_with((duplicate_a, b"a"), (duplicate_b, b"b")),
            self._archive_with((pax, b"x"), tar_format=tarfile.PAX_FORMAT),
        )
        for hostile in hostile_archives:
            with self.subTest(prefix=hostile[:16]), self.assertRaises(ValueError):
                bundle.validate_ustar(hostile)

    def test_preflight_never_calls_tar_extraction_apis(self):
        raw = bundle.write_ustar((("a.txt", b"abc"),))
        with (
            mock.patch.object(tarfile.TarFile, "extract", side_effect=AssertionError("extracted")),
            mock.patch.object(tarfile.TarFile, "extractall", side_effect=AssertionError("extracted")),
        ):
            self.assertEqual(bundle.validate_ustar(raw)[0].path, "a.txt")

    def test_preflight_rejects_checksum_valid_noncanonical_header_encodings(self):
        raw = bundle.write_ustar((("a.txt", b"abc"),))
        hostile = (
            self._mutate_header(raw, 156, b"\0"),
            self._mutate_header(raw, 100, b"  000644"),
            self._mutate_header(raw, 500, b"X"),
        )
        for archive in hostile:
            with self.subTest(header=archive[:512]), self.assertRaises(ValueError):
                bundle.validate_ustar(archive)

    def test_preflight_rejects_noncanonical_trailing_zero_record_count(self):
        raw = bundle.write_ustar((("a.txt", b"abc"),))
        with self.assertRaises(ValueError):
            bundle.validate_ustar(raw + (b"\0" * 512))


if __name__ == "__main__":
    unittest.main()
