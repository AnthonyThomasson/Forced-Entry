"""tools/proctree.py `matching`: the portable `pgrep -f` the finish skill uses to find the editors and games of a worktree
(Windows has no pgrep, and Git Bash's ps shows no command line)."""
import os
import re
import subprocess
import sys
import tempfile
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
        self.assertIn("matching (REGEX | --project DIR)", r.stderr)

    def test_a_regex_and_a_project_together_are_bad_usage(self):
        r = subprocess.run([sys.executable, "-I", str(ROOT / "tools" / "proctree.py"), "matching", "x", "--project", "y"],
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 2)


class ProjectTests(unittest.TestCase):
    """`matching --project DIR`: the Godot processes whose `--path` is exactly DIR, the finish skill's way to find the
    editors and games of ONE worktree (a folder name alone also matches another checkout's folder of that name)."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.worktree = str(self.root / "wt")
        (self.root / "wt").mkdir()

    def hits(self, command_line, directory=None):
        return re.search(proctree.project_pattern(directory or self.worktree), command_line) is not None

    def test_the_path_is_found_however_the_engine_was_given_it(self):
        wt = self.worktree
        for given in (wt, wt.replace("\\", "/"), wt.replace("/", "\\"), wt + os.sep, '"' + wt + '"', "'" + wt + "'"):
            with self.subTest(given=given):
                self.assertTrue(self.hits(f"Godot --editor --path {given}"), given)
                self.assertTrue(self.hits(f"Godot --path {given} --editor"), given)

    def test_another_folder_is_not_found_even_with_the_same_name_or_the_same_start(self):
        wt = self.worktree
        other_root = str(self.root / "elsewhere" / "wt")
        for given in (wt + "-main", wt + "2", other_root, str(self.root), str(self.root / "wt" / "sub"), "."):
            with self.subTest(given=given):
                self.assertFalse(self.hits(f"Godot --path {given} --editor"), given)
                self.assertFalse(self.hits(f"Godot --path {given}"), given)

    def test_the_word_path_must_be_the_engines_option(self):
        self.assertFalse(self.hits(f"python tool.py --path-of {self.worktree}"))
        self.assertFalse(self.hits(f"Godot {self.worktree}"))

    @unittest.skipUnless(proctree.WINDOWS, "Windows paths are case-insensitive and a drive letter has both cases")
    def test_the_case_of_a_windows_path_does_not_matter(self):
        self.assertTrue(self.hits(f"Godot --path {self.worktree.upper()}"))
        self.assertTrue(self.hits(f"Godot --path {self.worktree.lower()}"))

    def test_a_regex_special_character_in_the_path_is_literal(self):
        odd = self.root / "a+b (1)"
        odd.mkdir()
        self.assertTrue(self.hits(f"Godot --path {odd}", str(odd)))
        self.assertFalse(self.hits(f"Godot --path {self.root / 'aab (1)'}", str(odd)))

    def test_the_command_line_finds_the_process_and_leaves_a_sibling_alone(self):
        sibling = self.root / "wt-main"
        sibling.mkdir()
        mine = subprocess.Popen([sys.executable, "-c", SLEEPER.format(tag="project-test"), "--path", self.worktree])
        other = subprocess.Popen([sys.executable, "-c", SLEEPER.format(tag="project-test"), "--path", str(sibling)])
        for child in (mine, other):
            self.addCleanup(child.wait)
            self.addCleanup(child.kill)
        time.sleep(0.5)
        r = subprocess.run([sys.executable, "-I", str(ROOT / "tools" / "proctree.py"), "matching", "--project",
                            self.worktree, "--name", "python"], capture_output=True, text=True, timeout=120)
        pids = [int(line.split()[0]) for line in r.stdout.splitlines() if line.strip()]
        self.assertEqual((r.returncode, pids), (0, [mine.pid]), r.stdout + r.stderr)


if __name__ == "__main__":
    unittest.main()
