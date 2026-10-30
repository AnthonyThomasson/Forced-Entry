"""tools/run_tests.sh --base=<rev>: the working tree's tests run against the code of an old revision, in a temporary git
worktree, and the working tree is never written. A throwaway repo holds a copy of the wrapper and a fake Godot that
records what the run it was started in looks like; the refusals and the interrupt are checked on the same repo."""
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

from tools.tests.test_godot_slot import HOLDER

ROOT = Path(__file__).resolve().parents[2]

# Stands in for Godot: `--import` does nothing; any other start records where it runs and what that checkout holds
# (the production file, the tests, the helper folders), writes the report $FAKE_VERDICT says (pass or fail), and with
# FAKE_HANG=1 stays alive after writing its pid to $FAKE_STARTED until it is killed. Each `--import` is noted in $FAKE_IMPORTS.
FAKE_GODOT = r"""#!/usr/bin/env bash
for a in "$@"; do [ "$a" = "--import" ] && { echo import >> "$FAKE_IMPORTS"; exit 0; }; done
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
if [ -n "$FAKE_HANG" ]; then echo $$ > "$FAKE_STARTED.tmp"; mv "$FAKE_STARTED.tmp" "$FAKE_STARTED"; exec sleep 600; fi
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
        self.imports = self.tmp / "imports.txt"
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
                    FAKE_IMPORTS=str(self.imports), GAME_TEST_SLOT_DIR=str(self.state / "slots"), GAME_TEST_SLOT_POLL="0.05",
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
        after = lines[lines.index(f"== on base HEAD~1 ({short}) ==") + 1:]
        self.assertTrue(any(re.fullmatch(r"0 passed, 0 failed, 0 timed out, 0 skipped, 0 gap  load [0-9.]+", l) for l in after), after)

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
            (["--base=" + self.rev, "--changed"], "(given --changed)"),
            (["--base=" + self.rev, "--staged"], "(given --staged)"),
            (["--base=" + self.rev, "--changed", "--staged"], "(given --changed)"),
            (["--base=" + self.rev, "--staged", "--changed"], "(given --staged)"),
            (["--base=" + self.rev, "--jobs=2"], "--jobs=2 is refused"),
            (["--base=no-such-rev-zz"], "no-such-rev-zz"),
            (["--base="], "unknown revision"),
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

    def git_shim(self):
        """A `git` ahead of the real one on PATH that notes every call in the returned log (the calls a run makes, as text)."""
        shim = self.tmp / "shim"
        shim.mkdir(exist_ok=True)
        log = self.tmp / "git_calls.txt"
        (shim / "git").write_text(f'#!/bin/sh\necho "$@" >> {log}\nexec {shutil.which("git")} "$@"\n')
        (shim / "git").chmod(0o755)
        return log, f"{shim}:{os.environ['PATH']}"

    def test_a_bad_flag_is_refused_before_a_worktree_is_made_or_an_import_run(self):
        log, path = self.git_shim()
        for args, reason in ((["--bogus"], "unknown flag: --bogus"), (["--jobs=abc"], "--jobs wants a number")):
            with self.subTest(args=args):
                code, out = self.run_tests("--base=" + self.rev, *args, "--no-lint", PATH=path)
                self.assertEqual(code, 2, out)
                self.assertIn(reason, out)
                self.assertNotIn("worktree add", log.read_text() if log.exists() else "", "no worktree was made")
                self.assertFalse(self.imports.exists(), "no import ran (it takes minutes)")
                self.assertFalse(self.observed.exists(), "no engine process was started")

    def test_the_usage_of_an_unknown_flag_is_the_wrappers_own_when_the_revision_predates_it(self):
        empty = self.git("hash-object", "-t", "tree", "/dev/null").strip()
        old = self.git("-c", "user.name=t", "-c", "user.email=t@example.com", "commit-tree", empty, "-m", "before the wrapper").strip()
        code, out = self.run_tests("--base=" + old, "--bogus", "--no-lint")
        self.assertEqual(code, 2, out)
        self.assertIn("unknown flag: --bogus", out)
        self.assertIn("Selecting tests", out, "the usage lines come from the running wrapper, not from the revision")

    def start_hanging(self):
        """A --base run whose fake engine stays alive; returns (the wrapper process, the engine's pid) once it runs."""
        started = self.tmp / "started"
        output = self.wrapper_output.open("w")
        self.addCleanup(output.close)
        # Ctrl-C is the default disposition in the wrapper, whatever this test run was started with (a background job of a
        # non-interactive shell ignores it, and a signal ignored on entry can be neither trapped nor delivered).
        proc = subprocess.Popen(["bash", str(self.repo / "tools" / "run_tests.sh"), "--base=" + self.rev, "--id=ai/x",
                                 "--no-lint"], cwd=self.repo, env=self.env(FAKE_HANG="1", FAKE_STARTED=str(started)),
                                stdout=output, stderr=subprocess.STDOUT, start_new_session=True,
                                preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL))
        self.addCleanup(lambda: proc.poll() is None and os.killpg(proc.pid, signal.SIGKILL))
        self.addCleanup(self.kill_engine, started)
        self.assertTrue(self.wait_for(started.exists), "the run started")
        return proc, int(started.read_text())

    @property
    def wrapper_output(self) -> Path:
        """Where the hanging run's output goes."""
        return self.tmp / "wrapper_output.txt"

    def wrapper_said(self):
        """What the hanging run printed so far, for a failure message."""
        return self.wrapper_output.read_text() if self.wrapper_output.exists() else ""

    @staticmethod
    def kill_engine(started):
        try:
            os.kill(int(started.read_text()), signal.SIGKILL)
        except (OSError, ValueError):
            pass

    @staticmethod
    def wait_for(condition, seconds=180):
        """Whether `condition` holds within `seconds`: a deadline that holds on a loaded box."""
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if condition():
                return True
            time.sleep(0.1)
        return condition()

    @staticmethod
    def alive(pid):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return False
        return True

    def test_jobs_auto_and_one_are_one_process_and_not_refused(self):
        # auto would be the free slots; on the base it is one process, whichever side of --base it is given.
        for jobs in (["--base=" + self.rev, "--jobs=auto"], ["--jobs=auto", "--base=" + self.rev], ["--base=" + self.rev, "--jobs=1"]):
            with self.subTest(args=jobs):
                self.observed.unlink(missing_ok=True)
                code, out = self.run_tests(*jobs, "--id=ai/x,ai/y,ai/z", "--no-lint")
                self.assertEqual(code, 0, out)
                self.assertEqual(self.observed.read_text().count("pwd:"), 1, "one engine process\n" + out)

    def test_an_interrupted_run_still_removes_its_worktree(self):
        before = self.tree()
        proc, _ = self.start_hanging()
        self.assertNotEqual(self.git("worktree", "list", "--porcelain"), before[1], "premise: the worktree exists meanwhile")
        os.killpg(proc.pid, signal.SIGINT)
        self.assertTrue(self.wait_for(lambda: proc.poll() is not None), "the run ended\n" + self.wrapper_said())
        self.assertTrue(self.wait_for(lambda: self.tree() == before), "its worktree is gone\n" + self.wrapper_said())

    def test_a_terminated_wrapper_stops_its_engine_and_removes_the_worktree(self):
        # The signal reaches the wrapper's pid alone, not its process group (a kill from another terminal, a parent).
        before = self.tree()
        proc, engine = self.start_hanging()
        os.kill(proc.pid, signal.SIGTERM)
        self.assertTrue(self.wait_for(lambda: proc.poll() is not None), "the wrapper ended without waiting for the engine\n" + self.wrapper_said())
        self.assertEqual(proc.returncode, 143, self.wrapper_said())
        self.assertTrue(self.wait_for(lambda: not self.alive(engine)), "no engine is left running\n" + self.wrapper_said())
        self.assertEqual(self.tree(), before, "the worktree is removed\n" + self.wrapper_said())

    def test_it_leaves_the_stale_worktree_records_of_the_repo_alone(self):
        # Another worktree whose directory was deleted: `git worktree prune` would drop its record, and it is not this run's.
        stale = self.tmp / "stale_worktree"
        self.git("worktree", "add", "--detach", "-q", str(stale))
        shutil.rmtree(stale)
        before = self.git("worktree", "list", "--porcelain")
        self.assertIn("prunable", before, "premise: git calls the record stale")
        self.assertEqual(self.run_tests("--base=" + self.rev, "--id=ai/x", "--no-lint")[0], 0)
        self.assertEqual(self.git("worktree", "list", "--porcelain"), before)

    def test_the_first_run_import_waits_for_a_slot_like_every_engine_process(self):
        # A --base worktree has no import cache, so its run imports first. Every slot is held: nothing starts.
        slots = self.state / "slots"
        slots.mkdir()
        size = max(1, (os.cpu_count() or 2) // 2)
        holders = [subprocess.Popen([sys.executable, "-c", HOLDER, str(slots / f"slot{i}.lock"), str(os.getpid())],
                                    stdout=subprocess.PIPE, text=True) for i in range(size)]
        self.addCleanup(lambda: [(h.kill(), h.wait()) for h in holders])
        for h in holders:
            self.assertEqual(h.stdout.readline().strip(), "held")
        proc = subprocess.Popen(["bash", str(self.repo / "tools" / "run_tests.sh"), "--base=" + self.rev, "--id=ai/x", "--no-lint"],
                                cwd=self.repo, env=self.env(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        self.addCleanup(lambda: proc.poll() is None and proc.kill())
        time.sleep(1.5)
        self.assertIsNone(proc.poll(), "it waits for a slot")
        self.assertFalse(self.imports.exists(), "the import has not started")
        for h in holders:
            h.kill()
            h.wait()
        out = proc.communicate(timeout=120)[0]
        self.assertEqual(proc.returncode, 0, out)
        self.assertEqual(self.imports.read_text().split(), ["import"], "imported once, after the slot freed")
        self.assertIn("waiting for a Godot slot", out)

if __name__ == "__main__":
    unittest.main()
