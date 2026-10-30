"""tools/run_tests.sh forwards only the flags in its BATCH_FLAGS list and refuses every other `--` argument, so each
flag the batch reads (scenes/testing/: `option`, `list_option` and `flag` of TestBatch) must be in that list or in the
wrapper's own WRAPPER_FLAGS (the ones it gives the batch itself), or the batch could never be given it. The in-game test
runner (test_runner.gd) reads its command line through TestBatch too, but tools/play_tests.sh starts it, not
run_tests.sh, so its flags (`--queue`) are left out. Both are read as text: nothing runs. (How the wrapper refuses an unknown flag is tools/test_log_gate.py's WrapperTests.)
"""
import re
import unittest
from pathlib import Path

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


if __name__ == "__main__":
    unittest.main()
