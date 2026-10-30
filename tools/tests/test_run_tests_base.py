"""tools/run_tests.sh --base=<rev>: the working tree's tests run against the code of an old revision, in a temporary git
worktree, and the working tree is never written. A throwaway repo holds a copy of the wrapper and a fake Godot that
records what the run it was started in looks like; the refusals and the interrupt are checked on the same repo."""
import os
import shutil
import signal
import stat
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# Stands in for Godot: `--import` does nothing; any other start records where it runs and what that checkout holds
# (the production file, the tests, the helper folders), writes the report $FAKE_VERDICT says (pass or fail), and with
# FAKE_HANG=1 stays alive after writing $FAKE_STARTED until it is killed.
FAKE_GODOT = r"""#!/usr/bin/env bash
for a in "$@"; do [ "$a" = "--import" ] && exit 0; done
log=""; out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --log-file) log="$2"; shift ;;
    --out=*) out="${1#--out=}" ;;
  esac
  shift
done
{
  echo "pwd:$(pwd -P)"
  echo "scene:$(cat scenes/a.gd)"
  echo "tests:$(cd tests && find . -type f | sort | tr '\n' ' ')"
  echo "x:$(cat tests/ai/x_test.gd)"
} >> "$FAKE_OBSERVED"
echo "Godot Engine v4.4" > "$log"
status=PASS; [ "$FAKE_VERDICT" = "fail" ] && status=FAIL
printf '{"results": [{"id": "ai/x", "status": "%s"}], "stray_logs": [], "log_end": %s}' "$status" \
  "$(wc -c < "$log" | tr -d ' ')" > "$out/report.json"
echo "0 passed, 0 failed, 0 timed out, 0 skipped, 0 gap"
if [ -n "$FAKE_HANG" ]; then touch "$FAKE_STARTED"; sleep 60; fi
exit 0
"""


class BaseRunTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="run_tests_base_"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.repo = self.tmp / "repo"
        self.state = self.tmp / "state"
        self.state.mkdir()
        tools = self.repo / "tools"
        tools.mkdir(parents=True)
        for name in ("run_tests.sh", "scan_godot_log.py", "godot_slot.py"):
            shutil.copy2(ROOT / "tools" / name, tools / name)
        self.fake = self.tmp / "fakegodot"
        self.fake.write_text(FAKE_GODOT)
        self.fake.chmod(self.fake.stat().st_mode | stat.S_IEXEC)
        self.observed = self.tmp / "observed.txt"
        # The old revision: the production file as it was, the test as it was, a test since deleted, a helper folder.
        self.write("scenes/a.gd", "old code\n")
        self.write("tests/ai/x_test.gd", "old test\n")
        self.write("tests/ai/gone_test.gd", "deleted since\n")
        self.write("tests/_ai/helper.gd", "old helper\n")
        self.write(".gitignore", ".godot/\n")
        self.git("init", "-q")
        self.git("add", "-A")
        self.git("-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "base")
        self.rev = self.git("rev-parse", "HEAD").strip()
        # The working tree since: fixed code (committed), the test edited, one added (with its .uid), one deleted, a
        # helper edited; and an uncommitted edit of the code, which the base run must not see.
        self.write("scenes/a.gd", "fixed code\n")
        self.git("-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-qam", "fix")
        self.write("tests/ai/x_test.gd", "new test\n")
        self.write("tests/ai/y_test.gd", "added test\n")
        self.write("tests/ai/y_test.gd.uid", "uid://y\n")
        self.write("tests/_ai/helper.gd", "new helper\n")
        (self.repo / "tests/ai/gone_test.gd").unlink()
        self.write("scenes/a.gd", "uncommitted code\n")

    def write(self, rel, text):
        f = self.repo / rel
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(text)

    def git(self, *args):
        env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        return subprocess.run(["git", *args], cwd=self.repo, env=env, check=True, capture_output=True, text=True).stdout

    def env(self, **extra):
        env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_") and k != "GAME_TEST_CHANGED_FILES"}
        return dict(env, GODOT=str(self.fake), TMPDIR=str(self.state), FAKE_OBSERVED=str(self.observed),
                    **{"FAKE_VERDICT": "pass", **extra})

    def run_tests(self, *args, **env):
        r = subprocess.run(["bash", str(self.repo / "tools" / "run_tests.sh"), *args], cwd=self.repo,
                           env=self.env(**env), capture_output=True, text=True, timeout=120)
        return r.returncode, r.stdout + r.stderr

    def tree(self):
        """Everything the repo holds that git or the working tree could differ in: the files and `git worktree list`."""
        files = {p.relative_to(self.repo).as_posix(): p.read_bytes() for p in sorted(self.repo.rglob("*"))
                 if p.is_file() and ".git" not in p.relative_to(self.repo).parts}
        return files, self.git("worktree", "list", "--porcelain"), self.git("status", "--porcelain")

    def test_it_runs_the_working_trees_tests_against_the_old_code_and_leaves_the_working_tree_as_it_was(self):
        before = self.tree()
        code, out = self.run_tests("--base=" + self.rev, "--id=ai/x", "--no-lint")
        self.assertEqual(code, 0, out)
        seen = dict(line.split(":", 1) for line in self.observed.read_text().splitlines())
        self.assertNotEqual(Path(seen["pwd"]), self.repo.resolve(), "it runs in a checkout of its own")
        self.assertEqual(seen["scene"], "old code", "the production code is the revision's")
        self.assertEqual(seen["x"], "new test", "the tests are the working tree's")
        tests = seen["tests"].split()
        self.assertIn("./ai/y_test.gd", tests)
        self.assertIn("./ai/y_test.gd.uid", tests, "the .uid files come with the tests")
        self.assertIn("./_ai/helper.gd", tests, "so do the helper folders")
        self.assertNotIn("./ai/gone_test.gd", tests, "tests/ is replaced whole: a test deleted since is gone too")
        self.assertEqual(self.tree(), before, "the working tree and `git worktree list` are as they were")
        self.assertFalse(Path(seen["pwd"]).exists(), "the temporary worktree is removed")

    def test_it_prints_the_lines_of_the_run_under_a_header_naming_the_revision(self):
        code, out = self.run_tests("--base=HEAD~1", "--id=ai/x", "--no-lint")
        self.assertEqual(code, 0, out)
        short = self.git("rev-parse", "--short", "HEAD~1").strip()
        lines = out.splitlines()
        self.assertIn(f"== on base HEAD~1 ({short}) ==", lines)
        self.assertIn("0 passed, 0 failed, 0 timed out, 0 skipped, 0 gap", lines[lines.index(f"== on base HEAD~1 ({short}) ==") + 1:])

    def test_its_exit_code_is_that_runs_verdict(self):
        self.assertEqual(self.run_tests("--base=" + self.rev, "--id=ai/x", "--no-lint", FAKE_VERDICT="fail")[0], 1)
        self.assertEqual(self.run_tests("--base=" + self.rev, "--id=ai/x", "--no-lint")[0], 0)

    def test_it_does_not_replace_the_report_of_the_working_tree_runs(self):
        # --failed reads the last report of this checkout: a run on the base is another checkout's.
        self.assertEqual(self.run_tests("--id=ai/x", "--no-lint")[0], 0)
        last = sorted(self.state.glob("example_godot_last_report_*.json"))
        content = [f.read_bytes() for f in last]
        self.assertEqual(self.run_tests("--base=" + self.rev, "--id=ai/x", "--no-lint", FAKE_VERDICT="fail")[0], 1)
        self.assertEqual([f.read_bytes() for f in last], content)

    def test_the_refusals_exit_2_with_a_reason_and_run_nothing(self):
        before = self.tree()
        cases = (
            (["--base=" + self.rev, "--changed"], "--changed"),
            (["--base=" + self.rev, "--changed", "--staged"], "--staged"),
            (["--base=" + self.rev, "--jobs=2"], "--jobs"),
            (["--base=" + self.rev, "--jobs=auto"], "--jobs"),
            (["--base=no-such-rev-zz"], "no-such-rev-zz"),
        )
        for args, reason in cases:
            with self.subTest(args=args):
                code, out = self.run_tests(*args, "--no-lint")
                self.assertEqual(code, 2, out)
                self.assertIn(reason, out)
                self.assertIn("--base", out)
                self.assertNotIn("unknown flag", out, "a flag the wrapper knows, refused for a reason")
                self.assertNotIn("passed,", out)
        self.assertFalse(self.observed.exists(), "no engine process was started")
        self.assertEqual(self.tree(), before)

    def test_an_interrupted_run_still_removes_its_worktree(self):
        before = self.tree()
        started = self.tmp / "started"
        proc = subprocess.Popen(["bash", str(self.repo / "tools" / "run_tests.sh"), "--base=" + self.rev, "--id=ai/x",
                                 "--no-lint"], cwd=self.repo, env=self.env(FAKE_HANG="1", FAKE_STARTED=str(started)),
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        self.addCleanup(lambda: proc.poll() is None and os.killpg(proc.pid, signal.SIGKILL))
        deadline = time.monotonic() + 60
        while not started.exists() and time.monotonic() < deadline:
            time.sleep(0.1)
        self.assertTrue(started.exists(), "the run started")
        self.assertIn("worktree", self.git("worktree", "list", "--porcelain") + "worktree", "premise")
        self.assertNotEqual(self.git("worktree", "list", "--porcelain"), before[1], "premise: the worktree exists meanwhile")
        os.killpg(proc.pid, signal.SIGINT)
        proc.wait(timeout=60)
        self.assertEqual(self.tree(), before)


if __name__ == "__main__":
    unittest.main()
