"""tools/proctree.py `matching`: the portable `pgrep -f` the finish skill uses to find the editors and games of a worktree
(Windows has no pgrep, and Git Bash's ps shows no command line)."""
import subprocess
import sys
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import proctree  # noqa: E402  (the tool's own functions)

SLEEPER = "import time; time.sleep(60)  # {tag}"


class MatchingTests(unittest.TestCase):
    def sleeper(self, tag):
        child = subprocess.Popen([sys.executable, "-c", SLEEPER.format(tag=tag)])
        self.addCleanup(child.wait)
        self.addCleanup(child.kill)
        return child

    def find(self, *args):
        r = subprocess.run([sys.executable, "-I", str(ROOT / "tools" / "proctree.py"), "matching", *args],
                           capture_output=True, text=True, timeout=120)
        pids = [int(line.split()[0]) for line in r.stdout.splitlines() if line.strip()]
        return r.returncode, pids

    def test_a_process_is_found_by_its_command_line_and_the_others_are_not(self):
        mine = self.sleeper("matching-test-alpha")
        other = self.sleeper("matching-test-beta")
        time.sleep(0.5)
        code, pids = self.find("matching-test-alpha")
        self.assertEqual((code, pids), (0, [mine.pid]))
        self.assertNotIn(other.pid, pids)

    def test_nothing_matching_is_exit_1(self):
        self.assertEqual(self.find("no-process-has-this-command-line-3f9a1c"), (1, []))

    def test_a_regex_with_a_group_and_an_end_anchor_matches_as_pgrep_f_would(self):
        mine = self.sleeper("--path /tmp/matching-test-tree")
        time.sleep(0.5)
        # the finish skill's pattern: the worktree's folder name, an optional closing quote (Windows quotes an
        # argument that holds a space), then a space or the end of the command line
        self.assertEqual(self.find("""--path [^ ]*matching-test-tree["']?( |$)""", "--name", "python"), (0, [mine.pid]))
        self.assertEqual(self.find("""--path [^ ]*matching-test-tre["']?( |$)""", "--name", "python"), (1, []))

    def test_name_limits_the_search_to_programs_that_match(self):
        self.sleeper("matching-test-gamma")
        time.sleep(0.5)
        self.assertEqual(self.find("matching-test-gamma", "--name", "^godot"), (1, []))

    def test_this_process_and_what_it_runs_under_never_count(self):
        import os
        procs = proctree.snapshot()
        found = proctree.matching(procs, "python", None)
        self.assertNotIn(os.getpid(), [p.pid for p in found])

    def test_bad_usage_is_exit_2(self):
        r = subprocess.run([sys.executable, "-I", str(ROOT / "tools" / "proctree.py"), "matching"], capture_output=True,
                           text=True, timeout=60)
        self.assertEqual(r.returncode, 2)
        self.assertIn("matching REGEX", r.stderr)


if __name__ == "__main__":
    unittest.main()
