import contextlib
import io
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from scripts.check_markdown_links import (
    check_paths,
    check_repository,
    extract_destinations,
    format_summary,
    link_kind,
    list_markdown_files,
    main,
)


REPO_ROOT = Path(__file__).resolve().parents[2]


class ExtractDestinationTests(unittest.TestCase):
    def test_code_formatted_label_is_still_a_link(self):
        text = "See [`STATUS.md`](STATUS.md).\n"
        self.assertEqual(extract_destinations(text), [(1, "STATUS.md")])

    def test_image_title_angle_destination_and_parentheses(self):
        text = (
            'Go [a](<my file.md> "title") and ![pic](images/fig(1).png).\n'
        )
        self.assertEqual(
            extract_destinations(text),
            [(1, "my file.md"), (1, "images/fig(1).png")],
        )

    def test_fenced_code_inline_code_and_comments_are_ignored(self):
        text = "\n".join(
            [
                "```markdown",
                "[hidden](missing-fenced.md)",
                "```",
                "See `[hidden](missing-inline.md)` and [kept](kept.md).",
                "<!-- [hidden](missing-comment.md) -->",
                "[also](also.md)",
                "",
            ]
        )
        self.assertEqual(
            extract_destinations(text),
            [(4, "kept.md"), (6, "also.md")],
        )

    def test_footnote_prose_is_not_a_path(self):
        text = "\n".join(
            [
                "See [the note][doc].",
                "",
                "[^authority-proof]: SMP specifies distinctions that are not a path.",
                "[doc]: nested/target.md",
                "",
            ]
        )
        self.assertEqual(extract_destinations(text), [(4, "nested/target.md")])

    def test_multiline_html_comment_is_ignored(self):
        text = "<!--\n[hidden](missing.md)\n-->\n[kept](kept.md)\n"
        self.assertEqual(extract_destinations(text), [(4, "kept.md")])


class LinkKindTests(unittest.TestCase):
    def test_kinds(self):
        self.assertEqual(link_kind("https://example.com/missing"), "external")
        self.assertEqual(link_kind("mailto:example-user@example.com"), "external")
        self.assertEqual(link_kind("//example.com/file.md"), "external")
        self.assertEqual(link_kind("#section"), "fragment")
        self.assertEqual(link_kind("docs/file.md#section"), "local")
        self.assertEqual(link_kind("/docs/file.md"), "local")


class CheckPathTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def write(self, relative: str, text: str) -> Path:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def test_missing_target_reports_source_line_and_resolved_path(self):
        source = self.write("docs/guide.md", "Go [there](missing.md).\n")
        result = check_paths(self.root, [source])
        self.assertEqual(len(result.problems), 1)
        rendered = result.problems[0].format()
        self.assertEqual(
            rendered,
            "docs/guide.md:1: missing local target `missing.md` "
            "(resolved to `docs/missing.md`)",
        )
        self.assertIn("1 broken link", format_summary(result))

    def test_existing_relative_directory_fragment_and_external_links(self):
        self.write("docs/adr/0001.md", "# ADR\n")
        source = self.write(
            "docs/guide.md",
            "\n".join(
                [
                    "See [adr](adr/) and [self](#section) and [web](https://example.com/x).",
                    "Also [file](adr/0001.md#missing-heading).",
                    "",
                ]
            ),
        )
        result = check_paths(self.root, [source])
        self.assertEqual(result.problems, ())
        self.assertEqual(result.local_links, 2)
        self.assertEqual(result.external_skipped, 1)
        self.assertEqual(result.fragments_skipped, 1)

    def test_percent_encoded_space_and_repo_root_absolute_link(self):
        self.write("docs/my file.md", "# Note\n")
        source = self.write(
            "README.md",
            "See [note](docs/my%20file.md) and [again](/docs/my%20file.md).\n",
        )
        result = check_paths(self.root, [source])
        self.assertEqual(result.problems, ())
        self.assertEqual(result.local_links, 2)

    def test_unreadable_markdown_is_reported_without_raising(self):
        source = self.write("docs/guide.md", "See [there](missing.md).\n")
        source.unlink()
        result = check_paths(self.root, [source])
        self.assertEqual(
            result.problems[0].format(),
            "docs/guide.md:1: markdown file could not be read",
        )

    def test_link_that_leaves_the_repository_is_broken(self):
        source = self.write("docs/guide.md", "See [out](../../outside.md).\n")
        result = check_paths(self.root, [source])
        self.assertEqual(len(result.problems), 1)
        self.assertIn("escapes the repository", result.problems[0].format())
        self.assertNotIn(str(self.root), result.problems[0].format())

    def test_walk_inside_a_parent_git_checkout_stays_in_that_directory(self):
        kept = self.write("notes/local.md", "See [self](local.md).\n")
        found = list_markdown_files(self.root)
        self.assertEqual(found, [kept.resolve()])
        result = check_repository(self.root)
        self.assertEqual(result.problems, ())
        self.assertEqual(result.files, 1)


class RepositoryTests(unittest.TestCase):
    def test_existing_docs_have_no_broken_local_links(self):
        result = check_repository(REPO_ROOT)
        self.assertGreater(result.files, 0)
        self.assertGreater(result.local_links, 0)
        self.assertEqual(
            [problem.format() for problem in result.problems],
            [],
        )

    def test_cli_on_repository_exits_zero(self):
        proc = subprocess.run(
            [sys.executable, str(REPO_ROOT / "scripts" / "check_markdown_links.py")],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertEqual(proc.stderr, "")
        self.assertIn("0 broken links", proc.stdout)

    def test_cli_checks_a_named_markdown_file(self):
        proc = subprocess.run(
            [
                sys.executable,
                str(REPO_ROOT / "scripts" / "check_markdown_links.py"),
                "README.md",
            ],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertTrue(proc.stdout.startswith("checked 1 markdown file, "))

    def test_cli_rejects_a_non_markdown_path(self):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            status = main(["LICENSE"])
        self.assertEqual(status, 2)
        self.assertEqual(stderr.getvalue().strip(), "error: not a markdown file: LICENSE")


if __name__ == "__main__":
    unittest.main()
