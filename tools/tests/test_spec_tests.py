"""tools/spec_tests.py: a changed docs/*.md hunk in, the ids of the tests its paragraph names out (and the NOTE lines
for a paragraph that names none or a name with no test file). The mapping runs on a diff text and a doc text, in a
temp dir of test files; the command line runs in a throwaway git repo, on the working tree and on the index."""
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tools import spec_tests

SCRIPT = Path(spec_tests.__file__)

DOC = """# Spec

**E1. First rule.** Prose of the first rule.
More prose.
Tests: `alpha_one`, `alpha_two`.

**E2. Second rule.** Prose that names nothing.
More prose.

**E3. Third rule.** Why: a reason. Tests: `beta_one`,
`beta_two` (and `not_a_test_name` is commentary), `ai/grenade/gamma`.
Tail prose that mentions `some.code_name` and `delta_helper`.

**E4. Fourth rule.** Test: `missing_test` (a paragraph
that goes on).
"""


def hunk(path, start, count):
    """A unified -U0 diff holding one hunk whose new side is `count` lines from `start`."""
    return f"diff --git a/{path} b/{path}\n--- a/{path}\n+++ b/{path}\n@@ -1,0 +{start},{count} @@\n"


class MappingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.tests = Path(self.tmp.name) / "tests"
        for rel in ("physics/alpha_one", "physics/alpha_two", "ai/beta_one", "ai/entry/beta_two", "ai/grenade/gamma",
                    "_ai/delta_helper"):
            (self.tests / (rel + "_test.gd")).parent.mkdir(parents=True, exist_ok=True)
            (self.tests / (rel + "_test.gd")).write_text("")

    def map(self, diff, doc=DOC):
        return spec_tests.map_diff(diff, lambda path: doc, self.tests)

    def test_a_changed_line_gives_the_ids_its_paragraphs_tests_line_names(self):
        # Line 4 is "More prose." of E1.
        self.assertEqual(self.map(hunk("docs/a.md", 4, 1)), (["physics/alpha_one", "physics/alpha_two"], []))

    def test_a_name_resolves_to_its_test_file_in_a_topic_folder_and_a_path_is_taken_as_it_is(self):
        # Line 10 is E3's first line: the Tests: line is mid-line (after "Why:") and goes on while it ends with a comma.
        ids, notes = self.map(hunk("docs/a.md", 10, 1))
        self.assertEqual(ids, ["ai/beta_one", "ai/entry/beta_two", "ai/grenade/gamma"])
        self.assertEqual(notes, [])

    def test_only_the_tests_line_names_tests_not_the_prose_after_it_nor_a_parenthesis_nor_code(self):
        ids, notes = self.map(hunk("docs/a.md", 12, 1))
        self.assertNotIn("_ai/delta_helper", ids)
        self.assertEqual(notes, [], "`not_a_test_name` is in parentheses, `some.code_name` is not a test name")

    def test_a_paragraph_with_no_tests_line_gives_a_note_with_its_first_line(self):
        self.assertEqual(self.map(hunk("docs/a.md", 8, 1)),
                         ([], ["NOTE docs/a.md:7: changed paragraph names no test"]))

    def test_a_name_with_no_test_file_gives_a_note_with_the_line_of_the_name(self):
        self.assertEqual(self.map(hunk("docs/a.md", 14, 1)),
                         ([], ["NOTE unknown test name in docs/a.md:14: missing_test"]))

    def test_a_helper_folder_holds_no_test(self):
        doc = "Tests: `delta_helper`.\n"
        self.assertEqual(spec_tests.map_diff(hunk("docs/a.md", 1, 1), lambda p: doc, self.tests),
                         ([], ["NOTE unknown test name in docs/a.md:1: delta_helper"]))

    def test_a_pure_deletion_changes_the_paragraph_around_where_the_lines_were(self):
        # Lines removed after new line 8 (inside E2): "@@ -8,2 +8,0 @@".
        diff = "diff --git a/docs/a.md b/docs/a.md\n--- a/docs/a.md\n+++ b/docs/a.md\n@@ -9,2 +8,0 @@\n"
        self.assertEqual(self.map(diff), ([], ["NOTE docs/a.md:7: changed paragraph names no test"]))
        # Removed after the blank line 6 that ends E1: the block that follows it, E2.
        diff = diff.replace("+8,0", "+6,0")
        self.assertEqual(self.map(diff), ([], ["NOTE docs/a.md:7: changed paragraph names no test"]))

    def test_a_hunk_across_two_paragraphs_changes_both_and_a_test_is_listed_once(self):
        ids, notes = self.map(hunk("docs/a.md", 5, 6))
        self.assertEqual(ids, ["physics/alpha_one", "physics/alpha_two", "ai/beta_one", "ai/entry/beta_two", "ai/grenade/gamma"])
        self.assertEqual(notes, ["NOTE docs/a.md:7: changed paragraph names no test"])
        self.assertEqual(self.map(hunk("docs/a.md", 3, 1) + "@@ -9,0 +4,1 @@\n")[0], ["physics/alpha_one", "physics/alpha_two"])

    def test_only_the_docs_markdown_files_of_the_diff_count(self):
        for path in ("scenes/ai/x.gd", "docs/adr/0001.txt", "README.md"):
            with self.subTest(path=path):
                self.assertEqual(self.map(hunk(path, 4, 1)), ([], []))
        deleted = "diff --git a/docs/a.md b/docs/a.md\n--- a/docs/a.md\n+++ /dev/null\n@@ -1,3 +0,0 @@\n"
        self.assertEqual(self.map(deleted), ([], []))

    def test_a_changed_blank_line_changes_no_paragraph(self):
        self.assertEqual(self.map(hunk("docs/a.md", 6, 1)), ([], []))


class CommandLineTests(unittest.TestCase):
    """The script in a throwaway repo: `git diff HEAD` (and the untracked docs) or, with --staged, the index."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name)
        (self.repo / "docs").mkdir()
        (self.repo / "docs" / "a.md").write_text(DOC)
        (self.repo / "tests" / "physics").mkdir(parents=True)
        (self.repo / "tests" / "physics" / "alpha_one_test.gd").write_text("")
        (self.repo / "tests" / "physics" / "alpha_two_test.gd").write_text("")
        self.git("init", "-q")
        self.git("add", "-A")
        self.git("-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "base")

    def git(self, *args):
        env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        subprocess.run(["git", *args], cwd=self.repo, env=env, check=True, capture_output=True)

    def spec_tests(self, *args):
        env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        r = subprocess.run([sys.executable, "-I", str(SCRIPT), *args], cwd=self.repo, env=env, capture_output=True,
                           text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout.splitlines()

    def edit(self, old, new):
        doc = self.repo / "docs" / "a.md"
        doc.write_text(doc.read_text().replace(old, new))

    def test_it_reads_the_working_tree_change(self):
        self.assertEqual(self.spec_tests(), [], "nothing changed")
        self.edit("More prose.\nTests: `alpha_one`", "More prose, reworded.\nTests: `alpha_one`")
        self.assertEqual(self.spec_tests(), ["ID physics/alpha_one", "ID physics/alpha_two"])

    def test_staged_reads_the_index_not_the_working_tree(self):
        self.edit("Prose of the first rule.", "Prose of the first rule, reworded.")
        self.git("add", "docs/a.md")
        self.edit("Prose that names nothing.", "Prose that names nothing, reworded.")
        self.assertEqual(self.spec_tests("--staged"), ["ID physics/alpha_one", "ID physics/alpha_two"])
        self.assertEqual(self.spec_tests(), ["ID physics/alpha_one", "ID physics/alpha_two",
                                             "NOTE docs/a.md:7: changed paragraph names no test"])

    def test_an_untracked_doc_is_all_changed(self):
        (self.repo / "docs" / "new.md").write_text("A new rule.\nTests: `alpha_one`.\n\nAnother.\n")
        self.assertEqual(self.spec_tests(), ["ID physics/alpha_one", "NOTE docs/new.md:4: changed paragraph names no test"])


if __name__ == "__main__":
    unittest.main()
