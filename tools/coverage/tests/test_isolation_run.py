"""The real tree stays byte-identical after `coverage.py instrument` plus a 1-match run (the ticket's isolation
criterion), and the instrumented copy of the real game still loads, lints and passes game tests.

SLOW: it instruments the whole of Forced-Entry and plays one real Watch match, so it runs only with
`FE_SLOW_TESTS=1` (and a Godot binary, found as tools/run_tests.sh finds it: GODOT, `godot`, /Applications/Godot*.app):

    FE_SLOW_TESTS=1 python3 -m unittest tools.coverage.tests.test_isolation_run

Run it with the Bash sandbox disabled, like every Godot launch. It works on THIS checkout (not a fixture): before and
after, it takes `git status --porcelain --untracked-files=all` and its own sha256 over the bytes of `scenes/`,
`tests/`, `addons/` and `project.godot` (support.tree_digest, independent of workspace.tree_hash), and both must be
unchanged. The run folder the match writes under artifacts/coverage/ is removed at the end. All of artifacts/ is
gitignored, the artifacts/.gdignore the tool writes included, so nothing there shows in `git status`. The copy
`instrument` makes is in artifacts/tmp/, kept (the run does not sweep it), and deleted at the end; the run leaves
nothing of its own there. The checks in the copy run with workspace.copy_env, as the run's own processes do.
"""
import shutil
import subprocess
import sys
import unittest
from pathlib import Path

from tools.coverage import workspace
from tools.coverage.tests.support import (ROOT, env_with_godot, git, git_status, needs_godot, read_json, require_tool,
                                          run_folders, slow, tree_digest)

PARTS = ("scenes", "tests", "addons", "project.godot")
# A cheap sample of the game suite for the copy: one domain with one test and a small one, in one process.
SAMPLE = ("--domain=interaction,art", "--jobs=1", "--summary")


def coverage(*args: str, timeout: float) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(ROOT / "tools" / "coverage.py"), *args], cwd=ROOT, env=env_with_godot(),
                          capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)


def in_copy(copy: Path, *cmd: str, timeout: float) -> subprocess.CompletedProcess:
    return subprocess.run(list(cmd), cwd=copy, env=workspace.copy_env(copy, env_with_godot()), capture_output=True,
                          text=True, timeout=timeout, stdin=subprocess.DEVNULL)


def remove_copy(copy: Path) -> None:
    """Delete the instrumented copy (workspace.cleanup refuses anything but a copy in the checkout's artifacts/tmp/)."""
    if copy.is_dir():
        workspace.cleanup(ROOT, copy)


@slow
@needs_godot
class RealTreeIsolationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        require_tool()
        cls.status_before = git_status(ROOT)
        cls.digest_before = tree_digest(ROOT, PARTS)
        cls.runs_before = set(run_folders(ROOT, "matches"))

        cls.instrument = coverage("instrument", timeout=600)
        if cls.instrument.returncode != 0:
            raise AssertionError(f"coverage.py instrument failed:\n{cls.instrument.stdout}\n{cls.instrument.stderr}")
        cls.copy = Path(cls.instrument.stdout.strip().splitlines()[-1])
        cls.addClassCleanup(remove_copy, cls.copy)
        cls.status_after_instrument = git_status(ROOT)
        cls.digest_after_instrument = tree_digest(ROOT, PARTS)

        cls.run_result = coverage("run", "--matches=1", "--jobs=1", timeout=1800)
        tmp = ROOT / "artifacts" / "tmp"
        cls.tmp_after_run = sorted(p.name for p in tmp.iterdir()) if tmp.is_dir() else []
        cls.new_runs = sorted(set(run_folders(ROOT, "matches")) - cls.runs_before)
        for folder in cls.new_runs:
            cls.addClassCleanup(shutil.rmtree, folder, True)
        cls.status_after_run = git_status(ROOT)
        cls.digest_after_run = tree_digest(ROOT, PARTS)

    def test_instrument_leaves_the_real_tree_byte_identical(self):
        self.assertEqual(self.status_after_instrument, self.status_before)
        self.assertEqual(self.digest_after_instrument, self.digest_before)

    def test_the_copy_is_directly_in_the_checkouts_artifacts_tmp(self):
        self.assertTrue(self.copy.is_dir(), self.copy)
        self.assertEqual(self.copy.resolve().parent, (ROOT / "artifacts" / "tmp").resolve())

    def test_the_run_kept_the_instrument_copy_and_left_nothing_of_its_own(self):
        self.assertEqual(self.tmp_after_run, [self.copy.name])

    def test_a_one_match_run_leaves_the_real_tree_byte_identical(self):
        self.assertEqual(self.run_result.returncode, 0, self.run_result.stdout + self.run_result.stderr)
        self.assertEqual(self.status_after_run, self.status_before)
        self.assertEqual(self.digest_after_run, self.digest_before)

    def test_the_run_wrote_one_folder_of_this_commit_under_ignored_artifacts(self):
        self.assertEqual(len(self.new_runs), 1, self.new_runs)
        folder = self.new_runs[0]
        meta = read_json(folder / "meta.json")
        self.assertEqual(meta["commit"], git(ROOT, "rev-parse", "HEAD").strip())
        self.assertEqual(len(meta["matches"]), 1)
        for name in ("hits.json", "map.json", "meta.json", "report.md", "report.json"):
            self.assertTrue((folder / name).is_file(), name)
        self.assertTrue((ROOT / "artifacts" / ".gdignore").is_file(), "artifacts/ carries a .gdignore")
        ignored = subprocess.run(["git", "check-ignore", "-q", str(folder / "hits.json")], cwd=ROOT)
        self.assertEqual(ignored.returncode, 0, "artifacts/ is gitignored")

    def test_the_copy_passes_the_load_check(self):
        r = in_copy(self.copy, "tools/load_check.sh", timeout=300)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_the_copy_passes_lint_but_for_the_isolation_rule_it_breaks_on_purpose(self):
        r = in_copy(self.copy, "tools/lint.sh", "--skip-rule=coverage_isolation", timeout=300)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_the_copy_passes_a_sample_of_the_game_tests_with_the_probe_idle(self):
        # The copy has no .git, so the wrapper's clean-lint fingerprint cannot be taken: --no-lint (lint is above).
        r = in_copy(self.copy, "tools/run_tests.sh", "--no-lint", *SAMPLE, timeout=900)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)


if __name__ == "__main__":
    unittest.main()
