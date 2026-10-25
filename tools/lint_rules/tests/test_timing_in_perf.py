"""Tests for the `timing_in_perf` lint rule (tools/lint_rules/rules/timing_in_perf.py): a wall-clock time budget is a
performance guard, so `Time.get_ticks_usec()` under tests/ appears only in tests/perf/ and tests/_perf/, which the
pre-commit hook leaves out (a budget fails on a loaded machine).

It fails on the call in code anywhere else under tests/ (a test, a helper folder, a native suite), with its line; it
passes on the call in tests/perf/ and tests/_perf/, on a comment naming it, on `Time.get_ticks_msec()` (the real-time
pacing of the Von and wall-clock waits), and on scenes/ (the game's own timing). The rule is read the way the runner
reads it, called on temp trees, then run through the runner's CLI.
"""
import unittest

from tools.lint_rules import runner
from tools.lint_rules.tests.support import RULES, ROOT, TempTree, run_runner, write

CALL = "\tvar started := Time.get_ticks_usec()\n"


def the_rule():
    rules = [r for r in runner.load_rules(RULES) if r.NAME == "timing_in_perf"]
    if not rules:
        raise AssertionError("no rule named timing_in_perf in tools/lint_rules/rules/")
    return rules[0]


def script(body: str) -> str:
    """A script whose line 5 is `body`."""
    return f"extends GameTest\n\n\nfunc run(t: TestContext) -> void:\n{body}\tt.check(true, \"x\")\n"


class FindsTests(unittest.TestCase):
    def test_the_call_outside_the_perf_folders_is_found_with_its_line(self):
        rule = the_rule()
        for rel in ("tests/audio/bank_test.gd", "tests/ai/entry/x_test.gd", "tests/_ai/probe.gd",
                    "tests/general/y_suite.gd"):
            with self.subTest(rel=rel), TempTree() as root:
                write(root, rel, script(CALL))
                found = [(f.path, f.line) for f in rule.check(root, None)]
                self.assertEqual(found, [(rel, 5)])
                self.assertIn("tests/perf", rule.check(root, None)[0].message, "the message says where it belongs")

    def test_every_call_is_listed(self):
        with TempTree() as root:
            write(root, "tests/audio/a_test.gd", script(CALL + "\tvar spent := Time.get_ticks_usec() - started\n"))
            self.assertEqual([f.line for f in the_rule().check(root, None)], [5, 6])

    def test_paths_limit_the_check(self):
        with TempTree() as root:
            write(root, "tests/audio/a_test.gd", script(CALL))
            write(root, "tests/ui/b_test.gd", script(CALL))
            self.assertEqual([f.path for f in the_rule().check(root, ["tests/ui"])], ["tests/ui/b_test.gd"])


class PassesTests(unittest.TestCase):
    def test_the_perf_folders_comments_ticks_msec_and_the_game_pass(self):
        with TempTree() as root:
            write(root, "tests/perf/audio_bank_render_test.gd", script(CALL))
            write(root, "tests/_perf/perf_probe.gd", script(CALL))
            write(root, "tests/_ai/door_view_probe.gd", script("\t# since_ms (`Time.get_ticks_usec`) and\n"))
            write(root, "tests/_ai/order_probe.gd", script("\tvar since := Time.get_ticks_msec()\n"))
            write(root, "scenes/audio/sound_bank.gd", script(CALL))
            self.assertEqual(the_rule().check(root, None), [])

    def test_the_real_tree_passes(self):
        self.assertEqual(the_rule().check(ROOT, None), [])


class ThroughTheRunnerTests(unittest.TestCase):
    def test_the_runner_fails_on_the_call_and_passes_without_it(self):
        with TempTree() as root:
            write(root, "tests/audio/a_test.gd", script(""))
            ok = run_runner(root, "--rule=timing_in_perf")
            write(root, "tests/audio/a_test.gd", script(CALL))
            bad = run_runner(root, "--rule=timing_in_perf")
        self.assertEqual(ok.returncode, 0, ok.stdout + ok.stderr)
        self.assertEqual(bad.returncode, 1, bad.stdout + bad.stderr)
        self.assertIn("tests/audio/a_test.gd:5", bad.stdout)


if __name__ == "__main__":
    unittest.main()
