"""Tests for tools/lint.sh with the project lint rules: its flags, exit codes, per-rule output and the stale-cache hint.

lint.sh runs the engine analyzer pass (tools/lint_scripts.tscn, read by tools/lint_report.py), then every rule in
tools/lint_rules/rules/, and exits 1 if any part fails:
  --list-rules        list the rules (name and description); no engine pass
  --rule=a,b          only those rules, and no engine pass
  --skip-rule=a,b     every rule but those, after the engine pass
  PATH...             restrict every pass (the engine pass gets `--only=res://PATH`, a folder's `*.gd` files for
                      a folder; the rules and gdstyle get the paths)
  --quiet             print nothing when everything is clean
and last the gdstyle pass (tools/lint_gdstyle.py: `gdstyle fmt --check` and `gdstyle check`, one section each; not
with --rule=), which, like the engine pass, leaves out a folder holding a .gdignore. Its findings on real scripts are
tools/test_log_gate.py's GdStyleLintTests.

Each test runs a temp tree's OWN copy of lint.sh, lint_report.py and the lint_rules package, with the toy rules of
fixtures/rules_two as its registered rules and a fake Godot (GODOT=…) that prints a canned engine log from
fixtures/logs/, so no engine runs: clean.log (no warning), parse_error.log (one unrelated parse error),
one_unknown_identifier.log (one "not declared" error: a typo, not a stale cache) and stale_class_cache.log (a real
Godot 4.4 lint log cut down: 157 "Could not find type" / "not declared" / "Could not find base class" parse errors
over 41 scripts, produced by emptying .godot/global_script_class_cache.cfg). With a stale cache the lint must say to
run `godot --headless --path . --import`; tools/lint_report.py (the engine log parser) prints that hint.

The engine pass's own walk (tools/lint_scripts.gd) is tested with the real engine (EngineLintTree, skipped when there
is no Godot): it lints every script of the project except those in a folder holding a `.gdignore`, the folders
Godot itself never imports (artifacts/, where the coverage tool keeps its instrumented copy).
"""
import os
import subprocess
import sys
import unittest

from tools.lint_rules.tests.support import (
    FIXTURES, LOGS, ROOT, EngineLintTree, LintTree, godot_binary, section_of, write,
)

TWO = FIXTURES / "rules_two"
HINT = "godot --headless --path . --import"


class FlagTests(unittest.TestCase):
    def test_list_rules_lists_every_rule_without_the_engine(self):
        with LintTree(TWO) as tree:
            r = tree.lint("--list-rules")
            calls = tree.engine_calls()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("toy_pass", r.stdout)
        self.assertIn("toy_fail", r.stdout)
        self.assertIn("a toy rule that always passes", r.stdout)
        self.assertEqual(calls, [], "--list-rules starts no engine")

    def test_rule_runs_only_that_rule_and_no_engine_pass(self):
        with LintTree(TWO) as tree:
            failing = tree.lint("--rule=toy_fail")
            passing = tree.lint("--rule=toy_pass")
            calls = tree.engine_calls()
        self.assertEqual(failing.returncode, 1, failing.stdout + failing.stderr)
        self.assertIn("scenes/bad.gd:2", failing.stdout)
        self.assertEqual(passing.returncode, 0, passing.stdout + passing.stderr)
        self.assertIsNone(section_of(passing.stdout, "toy_fail"), passing.stdout)
        self.assertEqual(calls, [], "--rule= skips the engine pass")

    def test_by_default_the_engine_pass_runs_then_every_rule_and_one_failing_rule_fails(self):
        with LintTree(TWO) as tree:
            r = tree.lint(log="clean.log")
            calls = tree.engine_calls()
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertEqual(len(calls), 1, calls)
        self.assertIsNotNone(section_of(r.stdout, "toy_pass"), r.stdout)
        self.assertIn("scenes/bad.gd:2", section_of(r.stdout, "toy_fail") or "", r.stdout)

    def test_skip_rule_leaves_a_rule_out_and_a_clean_run_passes(self):
        with LintTree(TWO) as tree:
            r = tree.lint("--skip-rule=toy_fail", log="clean.log")
            calls = tree.engine_calls()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(len(calls), 1, "the engine pass still runs")
        self.assertIsNotNone(section_of(r.stdout, "toy_pass"), "the other rule still runs\n" + r.stdout)
        self.assertIsNone(section_of(r.stdout, "toy_fail"), r.stdout)

    def test_an_engine_failure_fails_the_lint_when_every_rule_passes(self):
        with LintTree(TWO) as tree:
            r = tree.lint("--skip-rule=toy_fail", log="parse_error.log")
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("Expected end of statement", r.stdout)

    def test_quiet_prints_nothing_when_clean(self):
        with LintTree(TWO) as tree:
            r = tree.lint("--quiet", "--skip-rule=toy_fail", log="clean.log")
        self.assertEqual((r.returncode, r.stdout), (0, ""))

    def test_quiet_still_prints_a_failure(self):
        with LintTree(TWO) as tree:
            r = tree.lint("--quiet", log="clean.log")
        self.assertEqual(r.returncode, 1)
        self.assertIn("scenes/bad.gd:2", r.stdout)

    def test_paths_restrict_both_passes(self):
        with LintTree(TWO) as tree:
            clean = tree.lint("scenes/clean.gd", log="clean.log")
            calls = tree.engine_calls()
            bad = tree.lint("scenes/bad.gd", log="clean.log")
        self.assertEqual(clean.returncode, 0, "the rules saw only scenes/clean.gd\n" + clean.stdout + clean.stderr)
        self.assertTrue(any("--only=res://scenes/clean.gd" in c for c in calls), calls)
        self.assertEqual(bad.returncode, 1, bad.stdout + bad.stderr)

    def test_the_gdstyle_pass_runs_last_and_fails_on_an_unformatted_script(self):
        with LintTree(TWO) as tree:
            clean = tree.lint("--skip-rule=toy_fail", log="clean.log")
            write(tree.root, "scenes/ugly.gd", "extends Node\n\n\nfunc f()->int:\n\treturn 1+2\n")
            ugly = tree.lint("--skip-rule=toy_fail", log="clean.log")
            only_rule = tree.lint("--rule=toy_pass")
        self.assertEqual(clean.returncode, 0, clean.stdout + clean.stderr)
        self.assertIn("PASS", section_of(clean.stdout, "gdstyle fmt --check") or "", clean.stdout)
        self.assertIn("PASS", section_of(clean.stdout, "gdstyle check") or "", clean.stdout)
        self.assertEqual(ugly.returncode, 1, ugly.stdout + ugly.stderr)
        self.assertIn("scenes/ugly.gd: would be reformatted", section_of(ugly.stdout, "gdstyle fmt --check") or "",
                      ugly.stdout)
        self.assertEqual(only_rule.returncode, 0, "--rule= runs no gdstyle pass\n" + only_rule.stdout)
        self.assertIsNone(section_of(only_rule.stdout, "gdstyle fmt --check"), only_rule.stdout)

    def test_no_gdstyle_leaves_out_only_the_gdstyle_pass(self):
        with LintTree(TWO) as tree:
            write(tree.root, "scenes/ugly.gd", "extends Node\n\n\nfunc f()->int:\n\treturn 1+2\n")
            r = tree.lint("--no-gdstyle", "--skip-rule=toy_fail", log="clean.log")
            calls = tree.engine_calls()
        self.assertEqual(r.returncode, 0, "an unformatted script passes with --no-gdstyle\n" + r.stdout + r.stderr)
        self.assertIsNone(section_of(r.stdout, "gdstyle fmt --check"), r.stdout)
        self.assertIsNone(section_of(r.stdout, "gdstyle check"), r.stdout)
        self.assertEqual(len(calls), 1, "the engine pass still runs")
        self.assertIn("PASS", section_of(r.stdout, "toy_pass") or "", r.stdout)

    def test_the_gdstyle_pass_leaves_out_a_gdignore_folder(self):
        with LintTree(TWO) as tree:
            write(tree.root, "scenes/deep/.gdignore")
            write(tree.root, "scenes/deep/ugly.gd", "extends Node\n\n\nfunc f()->int:\n\treturn 1+2\n")
            r = tree.lint("--quiet", "--skip-rule=toy_fail", log="clean.log")
        self.assertEqual((r.returncode, r.stdout), (0, ""), r.stdout + r.stderr)

    def test_a_folder_gives_the_engine_its_scripts_and_the_rules_the_folder(self):
        with LintTree(TWO) as tree:
            write(tree.root, "scenes/sub/deep.gd", "extends Node\n# BAD in a folder\n")
            write(tree.root, "scenes/sub/.hidden/skipped.gd", "extends Node\n")
            r = tree.lint("scenes/sub", log="clean.log")
            calls = tree.engine_calls()
        self.assertEqual(r.returncode, 1, "the rules saw the folder\n" + r.stdout + r.stderr)
        self.assertIn("scenes/sub/deep.gd:2", section_of(r.stdout, "toy_fail") or "", r.stdout)
        self.assertEqual(len(calls), 1, calls)
        only = calls[0].split("--only=", 1)[1].split()[0].split(",") if "--only=" in calls[0] else []
        self.assertEqual(only, ["res://scenes/sub/deep.gd"], "the folder's scripts, not the folder: " + calls[0])


BROKEN = "extends Node\nfunc broken(:\n"


@unittest.skipUnless(godot_binary(), "no Godot binary (set GODOT=/path/to/Godot)")
class EngineWalkTests(unittest.TestCase):
    def test_a_broken_script_in_a_plain_folder_fails_the_lint(self):
        with EngineLintTree() as tree:
            write(tree.root, "artifacts/tmp/copy/scenes/broken.gd", BROKEN)
            r = tree.lint("--quiet")
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("res://artifacts/tmp/copy/scenes/broken.gd", r.stdout)

    def test_a_broken_script_under_a_gdignore_folder_is_never_linted(self):
        with EngineLintTree() as tree:
            write(tree.root, "artifacts/.gdignore")
            write(tree.root, "artifacts/tmp/copy/scenes/broken.gd", BROKEN)
            write(tree.root, "scenes/deep/.gdignore")
            write(tree.root, "scenes/deep/broken.gd", BROKEN)
            r = tree.lint("--quiet")
        self.assertEqual((r.returncode, r.stdout), (0, ""), r.stdout + r.stderr)


class StaleCacheHintTests(unittest.TestCase):
    def report(self, log: str):
        env = {k: v for k, v in os.environ.items() if k != "GODOT"}
        return subprocess.run([sys.executable, str(ROOT / "tools" / "lint_report.py"), str(LOGS / log)],
                              capture_output=True, text=True, env=env, cwd=ROOT, timeout=120)

    def test_a_log_full_of_type_not_found_errors_gets_the_import_hint(self):
        r = self.report("stale_class_cache.log")
        self.assertEqual(r.returncode, 1)
        self.assertIn(HINT, r.stdout + r.stderr)

    def test_an_ordinary_failure_gets_no_hint(self):
        for log in ("parse_error.log", "one_unknown_identifier.log"):
            with self.subTest(log=log):
                r = self.report(log)
                self.assertEqual(r.returncode, 1)
                self.assertNotIn(HINT, r.stdout + r.stderr)

    def test_a_clean_log_gets_no_hint(self):
        r = self.report("clean.log")
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertNotIn(HINT, r.stdout + r.stderr)

    def test_lint_sh_prints_the_hint_for_a_stale_cache(self):
        with LintTree(TWO) as tree:
            r = tree.lint("--skip-rule=toy_fail", log="stale_class_cache.log")
        self.assertEqual(r.returncode, 1)
        self.assertIn(HINT, r.stdout + r.stderr)


if __name__ == "__main__":
    unittest.main()
