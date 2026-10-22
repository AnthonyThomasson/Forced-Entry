"""Tests for the `comment_ticket_refs` lint rule (tools/lint_rules/rules/comment_ticket_refs.py): game comments say what
the code is, never which ticket asked for it.

It fails on `ticket #N` or `issue #N` (any case, `tickets` / `issues` too) in a comment (`#` or `##`, whole-line or
trailing) of a script under scenes/, and passes on the same words inside a string, on a bare `#N`, on a folder Godot
ignores (`.gdignore`), and on tests/ and everything else outside scenes/. Every reference is reported with its file and
line.
"""
import unittest

from tools.lint_rules import runner
from tools.lint_rules.tests.support import RULES, ROOT, TempTree, run_runner, write


def the_rule():
    rules = [r for r in runner.load_rules(RULES) if r.NAME == "comment_ticket_refs"]
    if not rules:
        raise AssertionError("no rule named comment_ticket_refs in tools/lint_rules/rules/")
    return rules[0]


class FindTests(unittest.TestCase):
    def test_each_reference_in_a_comment_is_found_with_its_line(self):
        for comment in ("# see ticket #71", "## Ticket #71: the rally.", "# (issue #38, 11b)", "## ISSUE #4",
                        "# tickets #54 and #61"):
            with self.subTest(comment=comment), TempTree() as root:
                write(root, "scenes/ai/brain.gd", f"extends Node\n\n{comment}\nvar x := 1  ## the x\n")
                found = [(f.path, f.line) for f in the_rule().check(root, None)]
                self.assertEqual(found, [("scenes/ai/brain.gd", 3)])

    def test_a_trailing_comment_counts(self):
        with TempTree() as root:
            write(root, "scenes/a.gd", "extends Node\n\nvar x := 1  ## the rally (ticket #71)\n")
            found = the_rule().check(root, None)
            self.assertEqual([(f.path, f.line) for f in found], [("scenes/a.gd", 3)])
            self.assertIn("ticket #71", found[0].message, "the message quotes the reference")

    def test_every_reference_is_listed(self):
        with TempTree() as root:
            write(root, "scenes/a.gd", "extends Node\n# ticket #1\n# ticket #2\n")
            write(root, "scenes/ui/b.gd", "extends Node\n\n\n# issue #3\n")
            found = {(f.path, f.line) for f in the_rule().check(root, None)}
        self.assertEqual(found, {("scenes/a.gd", 2), ("scenes/a.gd", 3), ("scenes/ui/b.gd", 4)})

    def test_paths_limit_the_check(self):
        with TempTree() as root:
            write(root, "scenes/ai/a.gd", "# ticket #1\n")
            write(root, "scenes/ui/b.gd", "# ticket #2\n")
            self.assertEqual([f.path for f in the_rule().check(root, ["scenes/ai"])], ["scenes/ai/a.gd"])


class PassTests(unittest.TestCase):
    def test_the_words_in_a_string_are_not_a_comment(self):
        with TempTree() as root:
            write(root, "scenes/a.gd", 'extends Node\n\nvar s := "ticket #3"  ## a label\nvar t := \'issue #4\'\n')
            self.assertEqual(the_rule().check(root, None), [])

    def test_a_hash_inside_a_string_before_a_comment_is_skipped(self):
        with TempTree() as root:
            write(root, "scenes/a.gd", 'extends Node\n\nvar c := Color("#123456")  ## ticket #9\n')
            self.assertEqual([f.line for f in the_rule().check(root, None)], [3])

    def test_a_bare_number_and_other_words_pass(self):
        with TempTree() as root:
            write(root, "scenes/a.gd", "extends Node\n# slot #2 of the stack; the ticket's rule; issue a go\n")
            self.assertEqual(the_rule().check(root, None), [])

    def test_tests_and_docs_are_not_scanned(self):
        with TempTree() as root:
            write(root, "tests/ui/a_test.gd", "## Desired (ticket #41): the markers.\n")
            write(root, "docs/notes.md", "ticket #41\n")
            write(root, "tools/x.gd", "# ticket #41\n")
            self.assertEqual(the_rule().check(root, None), [])

    def test_a_folder_godot_ignores_is_not_scanned(self):
        with TempTree() as root:
            write(root, "scenes/deep/.gdignore")
            write(root, "scenes/deep/a.gd", "# ticket #41\n")
            self.assertEqual(the_rule().check(root, None), [])

    def test_the_real_tree_passes(self):
        self.assertEqual(the_rule().check(ROOT, None), [])


class ThroughTheLintTests(unittest.TestCase):
    def test_the_runner_fails_on_a_reference_and_passes_without(self):
        with TempTree() as root:
            write(root, "scenes/main.gd", "extends Node\n")
            ok = run_runner(root, "--rule=comment_ticket_refs")
            write(root, "scenes/main.gd", "extends Node\n\n# ticket #71\n")
            bad = run_runner(root, "--rule=comment_ticket_refs")
        self.assertEqual(ok.returncode, 0, ok.stdout + ok.stderr)
        self.assertEqual(bad.returncode, 1, bad.stdout + bad.stderr)
        self.assertIn("scenes/main.gd:3", bad.stdout)


if __name__ == "__main__":
    unittest.main()
