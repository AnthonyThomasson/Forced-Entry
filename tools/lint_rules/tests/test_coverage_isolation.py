"""Tests for the `coverage_isolation` lint rule (tools/lint_rules/rules/coverage_isolation.py): nothing in the game
touches the coverage tool.

It fails when scenes/, tests/, addons/ or project.godot hold
  - the text `tools/coverage`, `CoverageProbe` or `FE_COVERAGE` (in a comment too), or
  - a file or folder named `coverage_probe*` or `coverage_hits*`, or a path `tools/coverage*`;
and passes on the plain word "coverage" (cover_height, docs/cover-and-stance.md, search_coverage.gd), on the tool's own
tools/coverage/ and tools/coverage.py, and on docs/. Every breach is reported with its file (and line, for text).

The rule is read the way the runner reads it (runner.load_rules on the real rules folder), called on temp trees
with breaches planted one at a time, then run through the runner's CLI and through a temp tree's own tools/lint.sh,
which must exit 1 on a breach.
"""
import unittest
from pathlib import Path

from tools.lint_rules import runner
from tools.lint_rules.tests.support import RULES, ROOT, LintTree, TempTree, run_runner, write

TEXTS = ("tools/coverage", "CoverageProbe", "FE_COVERAGE")
PLACES = {"scenes": "scenes/ai/brain.gd", "tests": "tests/ai/brain_test.gd", "addons": "addons/kit/plugin.gd"}
NAMES = ("coverage_probe.gd", "coverage_probe_data/readme.txt", "coverage_hits.json", "coverage_hits/shard.json")


def the_rule():
    rules = [r for r in runner.load_rules(RULES) if r.NAME == "coverage_isolation"]
    if not rules:
        raise AssertionError("no rule named coverage_isolation in tools/lint_rules/rules/")
    return rules[0]


def clean_tree(root: Path) -> None:
    """A tree with the four scanned places and nothing reserved in them."""
    write(root, "project.godot", 'config_version=5\n\n[autoload]\n\nEventBus="*res://scenes/general/event_bus.gd"\n')
    write(root, "scenes/main.gd", "extends Node\n")
    write(root, "tests/ai/brain_test.gd", "extends GameTest\n")
    write(root, "addons/kit/plugin.cfg", "[plugin]\nname=\"kit\"\n")


def planted_line(text: str) -> str:
    """A file whose line 3 holds `text`, in a comment (a comment counts)."""
    return f"extends Node\n\n# {text} planted here\nvar x := 1\n"


class BreachTests(unittest.TestCase):
    def test_each_reserved_text_in_each_place_is_found_with_its_line(self):
        rule = the_rule()
        for text in TEXTS:
            for place, rel in PLACES.items():
                with self.subTest(text=text, place=place), TempTree() as root:
                    clean_tree(root)
                    write(root, rel, planted_line(text))
                    found = [tuple(f) for f in rule.check(root, None)]
                    self.assertEqual([(p, l) for p, l, _m in found], [(rel, 3)], found)
                    self.assertIn(text, found[0][2], "the message names what was found")

    def test_each_reserved_text_in_project_godot_is_found(self):
        rule = the_rule()
        for text in TEXTS:
            with self.subTest(text=text), TempTree() as root:
                clean_tree(root)
                write(root, "project.godot",
                      f'config_version=5\n\n[autoload]\n\nProbe="*res://x.gd" ; {text}\n')
                found = [(f.path, f.line) for f in rule.check(root, None)]
                self.assertEqual(found, [("project.godot", 5)])

    def test_each_reserved_name_in_each_place_is_found(self):
        rule = the_rule()
        for name in NAMES:
            for place in PLACES:
                with self.subTest(name=name, place=place), TempTree() as root:
                    clean_tree(root)
                    rel = f"{place}/deep/{name}"
                    write(root, rel, "nothing reserved inside\n")
                    found = [f.path for f in rule.check(root, None)]
                    reserved = f"{place}/deep/{name.split('/')[0]}"
                    self.assertTrue(found, f"{rel} is reported")
                    self.assertTrue(all(p.startswith(reserved) for p in found), found)

    def test_a_tools_coverage_path_inside_a_scanned_place_is_found(self):
        rule = the_rule()
        for rel in ("addons/tools/coverage/x.gd", "scenes/tools/coverage_helper.gd"):
            with self.subTest(rel=rel), TempTree() as root:
                clean_tree(root)
                write(root, rel, "extends Node\n")
                self.assertTrue([f for f in rule.check(root, None) if f.path.startswith(rel.rsplit("/", 1)[0])], rel)

    def test_every_breach_is_listed_not_just_the_first(self):
        rule = the_rule()
        with TempTree() as root:
            clean_tree(root)
            write(root, "scenes/a.gd", planted_line("CoverageProbe"))
            write(root, "tests/b_test.gd", planted_line("FE_COVERAGE"))
            write(root, "addons/c/coverage_hits.json", "{}\n")
            write(root, "scenes/d.gd", "extends Node\n# tools/coverage once\n# and tools/coverage twice\n")
            found = {(f.path, f.line) for f in rule.check(root, None)}
        self.assertIn(("scenes/a.gd", 3), found)
        self.assertIn(("tests/b_test.gd", 3), found)
        self.assertIn(("scenes/d.gd", 2), found)
        self.assertIn(("scenes/d.gd", 3), found)
        self.assertTrue(any(p.startswith("addons/c/coverage_hits") for p, _l in found), found)

    def test_paths_limit_the_check(self):
        rule = the_rule()
        with TempTree() as root:
            clean_tree(root)
            write(root, "scenes/ai/a.gd", planted_line("CoverageProbe"))
            write(root, "scenes/ui/b.gd", planted_line("CoverageProbe"))
            self.assertEqual([f.path for f in rule.check(root, ["scenes/ai"])], ["scenes/ai/a.gd"])
            self.assertEqual(rule.check(root, ["scenes/main.gd"]), [])


class PassTests(unittest.TestCase):
    def test_a_clean_tree_passes(self):
        with TempTree() as root:
            clean_tree(root)
            self.assertEqual(the_rule().check(root, None), [])

    def test_the_plain_word_coverage_is_not_flagged(self):
        with TempTree() as root:
            clean_tree(root)
            write(root, "scenes/objects/cover.gd",
                  "extends Node\n# cover height: see docs/cover-and-stance.md\nvar cover_height := 40\nvar coverage := 0.5\n"
                  "var coverage_hits_needed := 3\n")
            write(root, "scenes/ai/behavior/search_coverage.gd", "extends RefCounted\n")
            write(root, "tests/ai/coverage/search_coverage_test.gd", "extends GameTest\n")
            write(root, "scenes/objects/coverage.gd", "extends Node\n")
            self.assertEqual(the_rule().check(root, None), [])

    def test_the_tool_itself_and_docs_are_not_scanned(self):
        with TempTree() as root:
            clean_tree(root)
            write(root, "tools/coverage.py", "# reads FE_COVERAGE, writes coverage_hits\n")
            write(root, "tools/coverage/probe.gd", "extends Node\n# registered as CoverageProbe; FE_COVERAGE\n")
            write(root, "tools/coverage/coverage_probe.gd", "extends Node\n")
            write(root, "docs/adr/0001-dev-tools-stay-outside.md", "tools/coverage stays outside the game\n")
            self.assertEqual(the_rule().check(root, None), [])

    def test_the_real_tree_passes(self):
        self.assertEqual(the_rule().check(ROOT, None), [])


class ThroughTheLintTests(unittest.TestCase):
    def test_the_runner_fails_on_a_breach_and_passes_a_clean_tree(self):
        with TempTree() as root:
            clean_tree(root)
            ok = run_runner(root, "--rule=coverage_isolation")
            write(root, "scenes/main.gd", planted_line("CoverageProbe"))
            bad = run_runner(root, "--rule=coverage_isolation")
        self.assertEqual(ok.returncode, 0, ok.stdout + ok.stderr)
        self.assertEqual(bad.returncode, 1, bad.stdout + bad.stderr)
        self.assertIn("scenes/main.gd:3", bad.stdout)

    def test_lint_sh_exits_1_on_a_breach(self):
        with LintTree(RULES) as tree:
            write(tree.root, "scenes/clean.gd", planted_line("FE_COVERAGE"))
            only_rule = tree.lint("--rule=coverage_isolation")
            whole = tree.lint(log="clean.log")
        self.assertEqual(only_rule.returncode, 1, only_rule.stdout + only_rule.stderr)
        self.assertEqual(whole.returncode, 1, "a clean engine pass does not hide the breach\n" + whole.stdout)
        self.assertIn("scenes/clean.gd:3", whole.stdout)

    def test_lint_sh_passes_a_tree_without_breaches(self):
        with LintTree(RULES) as tree:
            (tree.root / "scenes" / "bad.gd").unlink()
            r = tree.lint("--rule=coverage_isolation")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)


if __name__ == "__main__":
    unittest.main()
