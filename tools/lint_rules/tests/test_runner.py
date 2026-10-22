"""Tests for the project lint-rule runner (tools/lint_rules/runner.py) and its shared helpers (tools/lint_rules/walk.py).

The runner loads one module per rule from a rules directory (`tools/lint_rules/rules/<name>.py`; the toy rules in
fixtures/ here) and runs them. A rule module has:
  NAME          the rule's name, which --rule= and --skip-rule= take
  DESCRIPTION   one line, shown by --list-rules and in the rule's section header
  check(root, paths) -> [Finding(path, line, message)]
                `paths` None = the whole tree, else the repo-relative files or folders to limit it to
  ALLOW         optional [{"path": ..., "reason": ...}]: a finding in an allowed path is shown as allowed, with its
                reason, and does not fail; an entry with no (or a blank) reason is itself an error.

The CLI these tests drive (tools/lint.sh runs the same runner after the engine pass):
  python3 tools/lint_rules/runner.py [--root=DIR] [--rules-dir=DIR] [--list-rules] [--rule=a,b] [--skip-rule=a,b]
                                     [--quiet] [PATH...]
  Exit 0 when every selected rule passes, 1 when any fails (a finding not allowed, a bad allow entry, a rule that
  raised). An unknown rule name is a usage error (non-zero, naming it). Each rule prints a section whose header line
  starts with `== ` and names the rule; a finding prints as `<path>:<line>: <message>` inside its rule's section.
  --quiet prints nothing when every rule passes.

walk.py, the helpers rules share (the toy rules use them):
  Finding(path, line, message)                 a named tuple
  files(root, dirs, paths=None) -> [str]       sorted repo-relative POSIX paths of every file under `dirs` (a name in
                                               `dirs` may be a file, e.g. "project.godot"; a missing one is skipped),
                                               limited to `paths` (files or folders) when given
  lines_matching(root, path, pattern) -> [(line, text)]   the 1-based lines of a text file matching a regex
  names_matching, godot_scripts and gdscript_lines are tested in test_walk.py.
"""
import shutil
import unittest
from pathlib import Path

from tools.lint_rules import runner, walk
from tools.lint_rules.tests.support import FIXTURES, RULES, TempTree, run_runner, section_of, write

TWO = FIXTURES / "rules_two"
ALLOW = FIXTURES / "rules_allow"
BAD_ALLOW = FIXTURES / "rules_bad_allow"
CRASH = FIXTURES / "rules_crash"


def plant(root: Path) -> None:
    """A tree the toy rules look at: scenes/bad.txt holds BAD on line 2, scenes/clean.txt and scenes/sub/ok.txt don't."""
    write(root, "scenes/clean.txt", "nothing to see\n")
    write(root, "scenes/bad.txt", "first line\nthis line is BAD\n")
    write(root, "scenes/sub/ok.txt", "fine\n")


class ListAndSelectTests(unittest.TestCase):
    def test_list_rules_names_each_rule_with_its_description(self):
        with TempTree() as root:
            r = run_runner(root, "--list-rules", rules_dir=TWO)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        lines = r.stdout.splitlines()
        for name, desc in (("toy_pass", "a toy rule that always passes"),
                           ("toy_fail", "a toy rule that flags the word BAD under scenes/")):
            self.assertTrue(any(name in l and desc in l for l in lines), f"{name} and its description on one line:\n{r.stdout}")

    def test_a_failing_rule_fails_the_lint_and_a_passing_one_does_not(self):
        with TempTree() as root:
            plant(root)
            both = run_runner(root, rules_dir=TWO)
            passing = run_runner(root, "--rule=toy_pass", rules_dir=TWO)
        self.assertEqual(both.returncode, 1, both.stdout + both.stderr)
        self.assertEqual(passing.returncode, 0, passing.stdout + passing.stderr)

    def test_each_rule_prints_its_own_section_with_its_findings_inside(self):
        with TempTree() as root:
            plant(root)
            r = run_runner(root, rules_dir=TWO)
        failing = section_of(r.stdout, "toy_fail")
        passing = section_of(r.stdout, "toy_pass")
        self.assertIsNotNone(failing, f"a section for toy_fail:\n{r.stdout}")
        self.assertIsNotNone(passing, f"a section for toy_pass (passing rules print one too):\n{r.stdout}")
        self.assertIn("scenes/bad.txt:2: the word BAD", failing)
        self.assertNotIn("scenes/bad.txt", passing)

    def test_rule_runs_only_the_named_rules(self):
        with TempTree() as root:
            plant(root)
            r = run_runner(root, "--rule=toy_pass", rules_dir=TWO)
        self.assertIsNone(section_of(r.stdout, "toy_fail"), r.stdout)

    def test_rule_takes_a_comma_list(self):
        with TempTree() as root:
            plant(root)
            r = run_runner(root, "--rule=toy_pass,toy_fail", rules_dir=TWO)
        self.assertEqual(r.returncode, 1)
        self.assertIsNotNone(section_of(r.stdout, "toy_pass"), r.stdout)
        self.assertIsNotNone(section_of(r.stdout, "toy_fail"), r.stdout)

    def test_skip_rule_leaves_a_rule_out(self):
        with TempTree() as root:
            plant(root)
            r = run_runner(root, "--skip-rule=toy_fail", rules_dir=TWO)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIsNone(section_of(r.stdout, "toy_fail"), r.stdout)

    def test_an_unknown_rule_name_is_refused_by_name(self):
        with TempTree() as root:
            r = run_runner(root, "--rule=no_such_rule", rules_dir=TWO)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("no_such_rule", r.stdout + r.stderr)

    def test_quiet_prints_nothing_when_every_rule_passes(self):
        with TempTree() as root:
            plant(root)
            r = run_runner(root, "--quiet", "--rule=toy_pass", rules_dir=TWO)
        self.assertEqual((r.returncode, r.stdout), (0, ""))

    def test_quiet_still_reports_a_failure(self):
        with TempTree() as root:
            plant(root)
            r = run_runner(root, "--quiet", rules_dir=TWO)
        self.assertEqual(r.returncode, 1)
        self.assertIn("scenes/bad.txt:2", r.stdout)


class PathTests(unittest.TestCase):
    def test_paths_limit_what_the_rules_check(self):
        with TempTree() as root:
            plant(root)
            clean = run_runner(root, "scenes/clean.txt", rules_dir=TWO)
            bad = run_runner(root, "scenes/bad.txt", rules_dir=TWO)
            folder = run_runner(root, "scenes/sub", rules_dir=TWO)
        self.assertEqual(clean.returncode, 0, clean.stdout)
        self.assertEqual(bad.returncode, 1, bad.stdout)
        self.assertEqual(folder.returncode, 0, folder.stdout)


class AllowTests(unittest.TestCase):
    def test_an_allowed_finding_is_shown_with_its_reason_and_does_not_fail(self):
        with TempTree() as root:
            write(root, "scenes/allowed.txt", "BAD but excused\n")
            r = run_runner(root, rules_dir=ALLOW)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        body = section_of(r.stdout, "toy_allowed") or ""
        self.assertIn("scenes/allowed.txt", body, "the allowed finding stays visible")
        self.assertIn("a fixture exception, kept visible", body, "with its reason")

    def test_allow_does_not_cover_other_paths(self):
        with TempTree() as root:
            write(root, "scenes/allowed.txt", "BAD but excused\n")
            write(root, "scenes/other.txt", "BAD and not excused\n")
            r = run_runner(root, rules_dir=ALLOW)
        self.assertEqual(r.returncode, 1, r.stdout)
        self.assertIn("scenes/other.txt:1", r.stdout)

    def test_an_allow_entry_without_a_reason_fails(self):
        with TempTree() as root:
            write(root, "scenes/allowed.txt", "BAD\n")
            r = run_runner(root, "--rule=toy_no_reason", rules_dir=BAD_ALLOW)
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("scenes/allowed.txt", r.stdout + r.stderr, "the error names the entry")

    def test_an_allow_entry_with_a_blank_reason_fails_even_with_nothing_found(self):
        with TempTree() as root:
            r = run_runner(root, "--rule=toy_blank_reason", rules_dir=BAD_ALLOW)
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)


class RobustnessTests(unittest.TestCase):
    def test_a_rule_that_raises_fails_the_lint_and_says_so(self):
        with TempTree() as root:
            r = run_runner(root, rules_dir=CRASH)
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("toy rule blew up", r.stdout + r.stderr)

    def test_adding_a_rule_is_adding_one_file(self):
        with TempTree() as root:
            rules = root / "rules"
            shutil.copytree(TWO, rules, ignore=shutil.ignore_patterns("__pycache__"))
            write(rules, "toy_new.py",
                  'NAME = "toy_new"\nDESCRIPTION = "a rule added as one file"\n\n\ndef check(root, paths):\n    return []\n')
            listed = run_runner(root, "--list-rules", rules_dir=rules)
            ran = run_runner(root, "--rule=toy_new", rules_dir=rules)
        self.assertIn("toy_new", listed.stdout)
        self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)
        self.assertIsNotNone(section_of(ran.stdout, "toy_new"), ran.stdout)

    def test_the_real_rules_include_coverage_isolation(self):
        with TempTree() as root:
            r = run_runner(root, "--list-rules")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("coverage_isolation", r.stdout)
        self.assertTrue(RULES.joinpath("coverage_isolation.py").is_file())

    def test_load_rules_reads_every_rule_module_of_a_directory(self):
        names = {rule.NAME for rule in runner.load_rules(TWO)}
        self.assertEqual(names, {"toy_pass", "toy_fail"})


class WalkTests(unittest.TestCase):
    def test_files_lists_everything_under_the_given_folders_sorted(self):
        with TempTree() as root:
            plant(root)
            write(root, "project.godot", "config_version=5\n")
            write(root, "docs/notes.md", "elsewhere\n")
            self.assertEqual(walk.files(root, ["scenes"]), ["scenes/bad.txt", "scenes/clean.txt", "scenes/sub/ok.txt"])
            self.assertEqual(walk.files(root, ["scenes", "project.godot", "addons"]),
                             ["project.godot", "scenes/bad.txt", "scenes/clean.txt", "scenes/sub/ok.txt"])

    def test_files_limited_to_paths(self):
        with TempTree() as root:
            plant(root)
            write(root, "docs/notes.md", "elsewhere\n")
            self.assertEqual(walk.files(root, ["scenes"], ["scenes/sub"]), ["scenes/sub/ok.txt"])
            self.assertEqual(walk.files(root, ["scenes"], ["scenes/bad.txt"]), ["scenes/bad.txt"])
            self.assertEqual(walk.files(root, ["scenes"], ["docs/notes.md"]), [], "a path outside the folders adds nothing")

    def test_lines_matching_gives_line_numbers_and_text(self):
        with TempTree() as root:
            plant(root)
            self.assertEqual(walk.lines_matching(root, "scenes/bad.txt", r"\bBAD\b"), [(2, "this line is BAD")])
            self.assertEqual(walk.lines_matching(root, "scenes/clean.txt", r"\bBAD\b"), [])

    def test_finding_is_a_path_line_message_tuple(self):
        f = walk.Finding("scenes/a.gd", 3, "why")
        self.assertEqual((f.path, f.line, f.message), ("scenes/a.gd", 3, "why"))
        self.assertEqual(tuple(f), ("scenes/a.gd", 3, "why"))


if __name__ == "__main__":
    unittest.main()
