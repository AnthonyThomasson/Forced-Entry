"""tools/run_tests.sh forwards only the flags in its BATCH_FLAGS list and refuses every other `--` argument, so each
flag the batch reads (scenes/testing/: `option`, `list_option` and `flag` of TestBatch) must be in that list or in the
wrapper's own WRAPPER_FLAGS (the ones it gives the batch itself), or the batch could never be given it. The in-game test
runner (test_runner.gd) reads its command line through TestBatch too, but tools/play_tests.sh starts it, not
run_tests.sh, so its flags (`--queue`) are left out. Both are read as text: nothing runs. (How the wrapper refuses an unknown flag is tools/test_log_gate.py's WrapperTests.)
"""
import re
import unittest
from pathlib import Path

from tools.tests.fake_tree import FakeTree

ROOT = Path(__file__).resolve().parents[2]
RUN = ROOT / "tools" / "run_tests.sh"
BATCH = ROOT / "scenes" / "testing"
# The in-game runner's script: started by tools/play_tests.sh, never by run_tests.sh.
RUNNER = BATCH / "test_runner.gd"


class FlagListTests(unittest.TestCase):
    @staticmethod
    def wrapper_list(name):
        m = re.search(rf"^{name}=\(([^)]*)\)", RUN.read_text(), re.M)
        assert m, f"run_tests.sh has no {name}=(...) list"
        return m.group(1).split()

    def test_every_flag_the_batch_reads_is_one_the_wrapper_knows(self):
        known = {f.rstrip("=") for f in self.wrapper_list("BATCH_FLAGS") + self.wrapper_list("WRAPPER_FLAGS")}
        read = set()
        for gd in sorted(p for p in BATCH.glob("*.gd") if p != RUNNER):
            read |= set(re.findall(r'\b(?:option|list_option|flag)\("(--[a-z-]+)"', gd.read_text()))
        self.assertIn("--domain", read, "premise: the batch's options are found")
        self.assertEqual(sorted(read - known), [], "flags the batch reads that run_tests.sh would refuse")

    def test_the_flags_the_wrapper_gives_itself_are_not_forwarded(self):
        self.assertEqual(set(self.wrapper_list("BATCH_FLAGS")) & set(self.wrapper_list("WRAPPER_FLAGS")), set())


class WrapperFlagTests(unittest.TestCase):
    """The flags the wrapper handles itself (its argument loop's case labels) are in the usage it prints for an unknown flag."""

    @staticmethod
    def handled():
        loop = RUN.read_text().split('for a in "$@"; do\n  case "$a" in\n', 1)[1].split("\n  esac\ndone", 1)[0]
        flags = set()
        for line in loop.splitlines():
            m = re.match(r"^    (--[a-z-]+(?:=\*)?(?:\|--[a-z-]+(?:=\*)?)*)\)", line)
            if m:
                flags |= {f.rstrip("=*") for f in m.group(1).split("|")}
        return flags

    @staticmethod
    def usage():
        text = RUN.read_text()
        return text[text.index("# Selecting tests"):text.index("# Not here:")]

    def test_the_loop_is_found_with_the_wrapper_flags(self):
        handled = self.handled()
        self.assertTrue({"--base", "--quiet", "--jobs", "--changed", "--staged"} <= handled, sorted(handled))

    def test_every_flag_the_wrapper_handles_is_in_its_usage(self):
        usage = self.usage()
        self.assertEqual(sorted(f for f in self.handled() - {"--play"} if f not in usage), [], "flags the usage lines leave out")


class NumberFlagTests(FakeTree):
    """A number given with a leading zero is the decimal it reads as (bash takes `08` for a bad octal), in a throwaway tree."""

    def test_repeat_with_a_leading_zero_reruns_the_native_suites_as_often_as_the_batch_repeats(self):
        code, out = self.run_tests("--repeat=08", "--id=general/m_suite", suite="general/m_suite")
        self.assertEqual(code, 0, out)
        self.assertEqual(len(self.started()), 8, "the run and seven reruns of its native suite\n" + out)

    def test_jobs_with_a_leading_zero_is_a_number(self):
        code, out = self.run_tests("--jobs=08", "--skip-domain=perf", suite="general/m_suite")
        self.assertEqual(code, 0, out)
        self.assertNotIn("wants a number", out)
        self.assertEqual(len(self.started()), 8, "eight shards\n" + out)

    def test_a_game_test_jobs_with_a_leading_zero_caps_the_jobs(self):
        code, out = self.run_tests("--jobs=12", "--skip-domain=perf", suite="general/m_suite", GAME_TEST_JOBS="09")
        self.assertEqual(code, 0, out)
        self.assertNotIn("wants a number", out)
        self.assertEqual(len(self.started()), 9, "twelve jobs asked, nine allowed\n" + out)


class StagedFlagTests(FakeTree):
    """`--staged` is the flag of `--changed`: given alone it is refused."""

    def test_staged_alone_is_refused_and_runs_nothing(self):
        code, out = self.run_tests("--staged")
        self.assertEqual(code, 2, out)
        self.assertIn("--staged goes with --changed", out)
        self.assertEqual(self.started(), [], "no engine process was started")


if __name__ == "__main__":
    unittest.main()
