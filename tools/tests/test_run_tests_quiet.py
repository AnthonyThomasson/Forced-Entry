"""tools/run_tests.sh --quiet in a throwaway tree of its own (tools/tests/fake_tree.py): a quiet gate that fails for another
reason than its timeout fails the run, and a native suite met in tests/perf is gated when it is run again by --repeat
while one outside it is not. (The gate around the real tree's perf tests is tools/test_log_gate.py's QuietGateTests.)"""
import unittest

from tools.tests.fake_tree import FakeTree


class QuietTreeTests(FakeTree):
    def test_a_gate_that_fails_for_another_reason_than_its_timeout_fails_the_run(self):
        self.conf.write_text("max_load=\ntimeout_min=30\nbusy_cpu=50\nbusy_sample_s=0.05\n")  # the helper cannot read it
        code, out = self.run_tests("--domain=perf", "--quiet")
        self.assertNotEqual(code, 0, out)
        self.assertRegex(out, r"quiet gate failed")
        self.assertFalse(self.starts.exists(), "the perf tests did not run on a gate that could not wait\n" + out)
        self.assertFalse(list(self.state.glob("example_godot_last_report_*.json")), "no result is marked loaded for it")

    def test_a_native_suite_met_in_tests_perf_is_gated_when_it_runs_again(self):
        code, out = self.run_tests("--repeat=2", "--quiet=1")
        self.assertEqual(code, 0, out)
        self.assertEqual(out.count("quiet gate timed out"), 2, "the first process and the rerun both wait\n" + out)
        self.assertEqual([r.get("loaded") for r in self.last_report()], [True, True])

    def test_a_native_suite_outside_tests_perf_is_not_gated_when_it_runs_again(self):
        code, out = self.run_tests("--repeat=2", "--quiet=1", suite="general/m_suite")
        self.assertEqual(code, 0, out)
        self.assertEqual(out.count("quiet gate timed out"), 1, "only the first process holds perf tests\n" + out)
        self.assertEqual([r.get("loaded") for r in self.last_report()], [True, None])


class FilterWordTests(FakeTree):
    """A selection of filter words holds a perf test only if the batch lists one for it (`--list <words> --domain=perf`):
    the quiet gate and the perf phase belong to a process that holds one. The machine is never quiet (the fake `uptime`)."""

    def test_words_that_list_no_perf_test_are_not_gated(self):
        code, out = self.run_tests("projectile", "--quiet=1", suite="general/m_suite", FAKE_LISTED="0")
        self.assertEqual(code, 0, out)
        self.assertNotIn("quiet gate", out, "no perf test in the process: nothing to wait for")
        self.assertEqual(self.started(), ["start projectile"])
        self.assertEqual([r.get("loaded") for r in self.last_report()], [None])
        self.assertEqual(self.listed(), ["list projectile --domain=perf"], "asked the batch for the perf part of the words")

    def test_words_that_list_a_perf_test_are_gated(self):
        code, out = self.run_tests("projectile", "--quiet=1", suite="perf/n_suite", FAKE_LISTED="2")
        self.assertEqual(code, 0, out)
        self.assertEqual(out.count("quiet gate timed out"), 1, out)
        self.assertEqual([r.get("loaded") for r in self.last_report()], [True])

    def test_words_that_list_no_perf_test_start_no_perf_phase_and_wait_for_nothing(self):
        code, out = self.run_tests("projectile", "--jobs=2", "--quiet=1", suite="general/m_suite", FAKE_LISTED="0")
        self.assertEqual(code, 0, out)
        self.assertNotIn("quiet gate", out)
        started = self.started()
        self.assertEqual(len(started), 2, started)
        self.assertEqual([s for s in started if "perf" in s], [], "the shards hold back no perf test and no process runs one")

    def test_words_that_list_a_perf_test_run_it_after_the_shards_behind_one_gate(self):
        code, out = self.run_tests("projectile", "--jobs=2", "--quiet=1", suite="perf/n_suite", FAKE_LISTED="1")
        self.assertEqual(code, 0, out)
        started = self.started()
        self.assertEqual(len(started), 3, started)
        self.assertEqual(sorted(started[:2]), ["start projectile --shard=0/2 --skip-domain=perf", "start projectile --shard=1/2 --skip-domain=perf"])
        self.assertEqual(started[2], "start projectile --domain=perf")
        self.assertEqual(out.count("quiet gate timed out"), 1, out)
        self.assertEqual(len(self.listed()), 1, "one probe answers the phase and its gate")

    def test_an_engine_that_does_not_answer_the_listing_counts_as_listing_a_perf_test(self):
        # Never run a perf test loaded for want of an answer: the gate waits as for a perf test.
        code, out = self.run_tests("projectile", "--quiet=1", suite="perf/n_suite", FAKE_LISTED="no answer")
        self.assertEqual(code, 0, out)
        self.assertEqual(out.count("quiet gate timed out"), 1, out)

    def test_a_selection_without_words_asks_the_batch_nothing(self):
        code, out = self.run_tests("--domain=perf", "--quiet=1")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.listed(), [])


# Added to the throwaway tree's copy of godot_slot.py: every call notes each `--ancestor=PID` it was given and whether that
# pid is one of this process's own ancestors in the machine's process table (the wrapper's own pid, as that table has it).
RECORD_ANCESTORS = r"""
def record_ancestors(argv):
    from tools import proctree
    for a in argv:
        if a.startswith("--ancestor="):
            pid = int(a.split("=", 1)[1])
            with open(os.environ["FAKE_ANCESTORS"], "a") as f:
                f.write("%d %s\n" % (pid, pid in proctree.ancestors(proctree.snapshot(), os.getpid())))


def main(argv: list) -> int:
    record_ancestors(argv)
"""


class AncestorTests(FakeTree):
    def test_the_pid_the_wrapper_hands_the_slot_tool_is_the_wrappers_own_in_the_process_table(self):
        # Git Bash's $$ is an MSYS pid, not the Windows pid the slot tool's process table (and so `stop` and the count of
        # other busy engines) goes by: it must be given the wrapper's Windows pid, or it ends and excludes nothing.
        slot = self.repo / "tools" / "godot_slot.py"
        text = slot.read_text()
        self.assertIn("def main(argv: list) -> int:\n", text)
        slot.write_text(text.replace("def main(argv: list) -> int:\n", RECORD_ANCESTORS.lstrip("\n"), 1))
        noted = self.tmp / "ancestors"
        code, out = self.run_tests("--quiet=1", FAKE_ANCESTORS=str(noted))
        self.assertEqual(code, 0, out)
        lines = noted.read_text().splitlines()
        self.assertTrue(lines, "the slot tool was given an ancestor")
        self.assertEqual([ln for ln in lines if not ln.endswith(" True")], [], "each is a pid above the slot tool")


if __name__ == "__main__":
    unittest.main()
