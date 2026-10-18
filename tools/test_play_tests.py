#!/usr/bin/env python3
"""Tests for tools/play_tests.sh, which opens a game window that plays the change's tests one after another.

  python3 tools/test_play_tests.py

Two layers:
  1. tools/play_tests.sh, copied into a temporary git repo, around a fake `godot` (GODOT=) that records its argv and
     sleeps like a window left open: which ids it queues (the change's tests, or the ids given), no tests -> exit 2,
     one test window per worktree (the editor and the editor's game untouched), returning at once, and the window's
     own log (`--log-file <dir>/godot.log` + `--out=<dir>`, a dir per worktree emptied each run).
  2. The real engine, headless: the test runner's `-- --queue=<ids>` plays them in the order given, reports an unknown
     id, prints `Queue done:` and keeps the window open afterwards; and a window play_tests.sh launches still fails a
     logged error when another Godot starts on the project mid-queue (which rotates the shared user://logs/godot.log).
Layer 2 is skipped when no Godot binary is found.
"""
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

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))  # run as a script: the repo root, for tools.coverage.tests.support
from tools.coverage.tests.support import clean_env  # noqa: E402
PLAY = ROOT / "tools" / "play_tests.sh"
RUNNER_SCENE = "res://scenes/testing/test_runner.tscn"


def godot_binary():
    for name in ("godot", "godot4"):
        p = shutil.which(name)
        if p:
            return p
    for p in sorted(Path("/Applications").glob("Godot*.app/Contents/MacOS/Godot")):
        return str(p)
    return os.environ.get("GODOT")


def alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def wait_for(cond, timeout: float) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if cond():
            return True
        time.sleep(0.1)
    return cond()


# The fake stays in the foreground like a game window (sleeping FAKE_SLEEP s); its argv stays visible to ps/pgrep, as a
# real Godot's does. It writes its argv, one per line, to $FAKE_RECORD_DIR/<its pid>.args and says it started on stdout
# and, given `--log-file <file>`, in that file too (as the engine's own log holds what it prints).
FAKE_GODOT = r"""#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_RECORD_DIR/$$.args"
echo "fake godot started pid $$"
prev=""
for a in "$@"; do
  [[ "$prev" == --log-file ]] && echo "fake godot started pid $$" >> "$a"
  prev="$a"
done
sleep "${FAKE_SLEEP:-30}" &
child=$!
trap 'kill $child 2>/dev/null; exit 143' TERM INT HUP
wait $child
"""

FAKE_SLEEP = 30

GIT_ENV = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com", "GIT_COMMITTER_NAME": "t",
           "GIT_COMMITTER_EMAIL": "t@example.com", "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"}

# The change's tests in the repo `make_repo(changes=True)` builds, in id order: added or modified since `main`,
# committed (a/modified_committed, ai/entry/deep_added, c/added_committed), staged (c/added_staged), modified in the
# working tree (b/modified_uncommitted) and untracked (z/untracked). Left out: unchanged tests, deleted ones (committed
# and in the working tree), helpers (tests/_x/helper.gd, tests/z/notes.gd) and the sandbox.
CHANGE_IDS = ["a/modified_committed", "ai/entry/deep_added", "b/modified_uncommitted", "c/added_committed",
              "c/added_staged", "z/untracked"]


class ScriptTests(unittest.TestCase):
    """tools/play_tests.sh in a temporary git repo, around a fake Godot."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="play_tests_"))
        self.fake = self.tmp / "fakegodot"
        self.fake.write_text(FAKE_GODOT)
        self.fake.chmod(self.fake.stat().st_mode | stat.S_IEXEC)
        self.records = self.tmp / "records"
        self.records.mkdir()
        self.state = self.tmp / "state"  # the script's $TMPDIR: its pid file and log
        self.state.mkdir()
        self.repo = self.tmp / "repo_feature"
        self.procs = []  # processes the test started itself (the fake editor and the editor's game)

    def tearDown(self):
        for pid in self.launched():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        for p in self.procs:
            p.kill()
            p.wait()
        shutil.rmtree(self.tmp, ignore_errors=True)

    # --- the temporary repo --------------------------------------------------------------------------

    def git(self, *args):
        subprocess.run(["git", "-c", "commit.gpgsign=false", *args], cwd=self.repo, env=clean_env(**GIT_ENV),
                       check=True, capture_output=True, text=True)

    def write(self, rel, text=None):
        """Each file gets its own content, as real tests have, so git never reads an added file as a deleted one renamed."""
        p = self.repo / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text if text is not None else f"extends GameTest\n# {rel}\n")

    def make_repo(self, changes=True):
        """A base commit on `main`; with `changes` a branch on top of it with every kind of change (CHANGE_IDS)."""
        self.repo.mkdir()
        self.git("init", "-q", "-b", "main")
        self.write("project.godot", 'config_version=5\n\n[application]\n\nconfig/name="play tests fixture"\n')
        self.write(".godot/global_script_class_cache.cfg", "list=[]\n")  # an imported checkout: no import is run
        if PLAY.exists():
            (self.repo / "tools").mkdir()
            shutil.copy2(PLAY, self.repo / "tools" / "play_tests.sh")
        for rel in ("tests/a/kept_test.gd", "tests/a/x_test.gd", "tests/b/y_test.gd", "tests/a/modified_committed_test.gd",
                    "tests/b/modified_uncommitted_test.gd", "tests/a/deleted_test.gd",
                    "tests/b/deleted_uncommitted_test.gd", "tests/_x/existing_helper.gd"):
            self.write(rel)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "base")
        if not changes:
            return
        self.git("checkout", "-q", "-b", "feature")
        self.write("tests/a/modified_committed_test.gd", "extends GameTest\n# changed\n")
        self.write("tests/c/added_committed_test.gd")
        self.write("tests/ai/entry/deep_added_test.gd")
        self.write("tests/_x/helper.gd")
        self.write("sandboxes/foo_sandbox.gd")
        (self.repo / "tests/a/deleted_test.gd").unlink()
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "feature")
        self.write("tests/c/added_staged_test.gd")
        self.git("add", "tests/c/added_staged_test.gd")
        self.write("tests/b/modified_uncommitted_test.gd", "extends GameTest\n# changed, not committed\n")
        (self.repo / "tests/b/deleted_uncommitted_test.gd").unlink()
        self.write("tests/_x/existing_helper.gd", "extends RefCounted\n# changed\n")
        self.write("tests/z/untracked_test.gd")
        self.write("tests/z/notes.gd")

    # --- running the script -----------------------------------------------------------------------------

    def play(self, *args, timeout=FAKE_SLEEP / 3):
        """Run the repo's tools/play_tests.sh; returns (exit code, output, seconds it took)."""
        script = self.repo / "tools" / "play_tests.sh"
        self.assertTrue(script.exists(), f"tools/play_tests.sh is missing ({PLAY} does not exist)")
        env = dict(os.environ, GODOT=str(self.fake), FAKE_RECORD_DIR=str(self.records), FAKE_SLEEP=str(FAKE_SLEEP),
                   TMPDIR=str(self.state))
        start = time.monotonic()
        try:
            r = subprocess.run(["bash", str(script), *args], cwd=self.repo, env=env, capture_output=True, text=True,
                               timeout=timeout)
        except subprocess.TimeoutExpired as e:
            self.fail(f"tools/play_tests.sh did not return within {timeout:.0f} s (the window sleeps {FAKE_SLEEP} s)\n"
                      f"{e.stdout or ''}{e.stderr or ''}")
        return r.returncode, r.stdout + r.stderr, time.monotonic() - start

    def launched(self):
        """The pids of the fake Godot windows started so far, oldest first."""
        files = sorted(self.records.glob("*.args"), key=lambda p: p.stat().st_mtime_ns)
        return [int(p.stem) for p in files]

    def argv(self, pid):
        return (self.records / f"{pid}.args").read_text().splitlines()

    def window(self):
        """Wait for exactly one new fake window and return (pid, argv)."""
        self.assertTrue(wait_for(lambda: len(self.launched()) >= 1, 5), "no Godot was launched")
        pids = self.launched()
        self.assertEqual(len(pids), 1, f"one Godot launched, got {len(pids)}")
        return pids[0], self.argv(pids[0])

    def queue_of(self, argv):
        """The --queue ids the runner was given, after checking it was launched on the runner scene of this repo."""
        self.assertIn(RUNNER_SCENE, argv, f"launched on the test runner scene: {argv}")
        self.assertIn("--path", argv, f"launched with --path <repo>: {argv}")
        path = argv[argv.index("--path") + 1]
        self.assertEqual(os.path.realpath(path), os.path.realpath(self.repo), f"--path is the repo: {argv}")
        self.assertIn("--", argv, f"user args after --: {argv}")
        user = argv[argv.index("--") + 1:]
        queues = [a for a in user if a.startswith("--queue=")]
        self.assertEqual(len(queues), 1, f"one --queue= user arg: {argv}")
        return queues[0][len("--queue="):]

    def log_dir_of(self, argv):
        """The window's own log dir: the engine logs to `--log-file <dir>/godot.log` and the runner follows it from
        `--out=<dir>` (the runner derives its log from --out, as a run_tests.sh batch does)."""
        self.assertIn("--", argv, f"user args after --: {argv}")
        engine, user = argv[:argv.index("--")], argv[argv.index("--") + 1:]
        self.assertIn("--log-file", engine, f"launched with an engine log of its own (--log-file): {argv}")
        log = Path(engine[engine.index("--log-file") + 1])
        self.assertEqual(log.name, "godot.log", f"--log-file is <dir>/godot.log: {argv}")
        self.assertEqual([a for a in user if a.startswith("--out=")], [f"--out={log.parent}"],
                         f"the runner is told the same dir (--out=<dir>): {argv}")
        return log.parent

    def start_editor(self):
        """A fake editor on the repo and a fake game the editor started (what the editor's Play runs), both left open."""
        env = dict(os.environ, FAKE_RECORD_DIR=str(self.tmp), FAKE_SLEEP=str(FAKE_SLEEP))  # not counted as windows
        editor = subprocess.Popen([str(self.fake), "--editor", "--path", str(self.repo)], env=env,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        game = subprocess.Popen([str(self.fake), "--path", str(self.repo), "--remote-debug", "tcp://127.0.0.1:6007",
                                 "--editor-pid", str(editor.pid)], env=env,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.procs += [editor, game]
        return editor, game

    # --- the rules ----------------------------------------------------------------------------------------

    def test_no_ids_queues_the_changes_tests_since_the_base(self):
        """Rule 2: added and modified *_test.gd since the base, committed or not, untracked included; by id."""
        self.make_repo()
        code, out, _ = self.play("--base=main")
        self.assertEqual(code, 0, out)
        _, argv = self.window()
        self.assertEqual(self.queue_of(argv), ",".join(CHANGE_IDS), out)

    def test_explicit_ids_are_queued_in_the_order_given(self):
        """Rule 1: the ids given, in that order (not sorted), whatever the change holds."""
        self.make_repo()
        code, out, _ = self.play("b/y", "a/x")
        self.assertEqual(code, 0, out)
        _, argv = self.window()
        self.assertEqual(self.queue_of(argv), "b/y,a/x", out)

    def test_no_change_tests_exits_2_and_launches_nothing(self):
        """Rule 3: a change with only a helper, a sandbox and a deleted test has no tests to play."""
        self.make_repo(changes=False)
        self.write("tests/_x/new_helper.gd")
        self.write("sandboxes/bar_sandbox.gd")
        (self.repo / "tests/a/deleted_test.gd").unlink()
        code, out, _ = self.play("--base=main")
        self.assertEqual(code, 2, out)
        time.sleep(1.0)  # a detached launch would have written its record by now
        self.assertEqual(self.launched(), [], "no Godot is launched when there are no tests\n" + out)

    def test_a_second_run_closes_the_first_window_and_leaves_the_editor(self):
        """Rule 4: one test window per worktree; the editor and the editor's game are never touched."""
        self.make_repo()
        editor, game = self.start_editor()
        code, out, _ = self.play("a/x")
        self.assertEqual(code, 0, out)
        first, _ = self.window()
        code, out, _ = self.play("b/y")
        self.assertEqual(code, 0, out)
        self.assertTrue(wait_for(lambda: len(self.launched()) >= 2, 5), "the second run launched a window\n" + out)
        second = self.launched()[-1]
        self.assertTrue(wait_for(lambda: not alive(first), 5), f"the first test window ({first}) was closed\n" + out)
        self.assertTrue(alive(second), f"the second test window ({second}) is open\n" + out)
        self.assertIsNone(editor.poll(), "the editor is left running")
        self.assertIsNone(game.poll(), "the editor's game is left running")

    def test_returns_at_once_printing_the_ids_pid_and_log(self):
        """Rule 5: fire and forget; the queued ids, the window's pid and its log path are printed."""
        self.make_repo()
        code, out, took = self.play("--base=main")
        self.assertEqual(code, 0, out)
        self.assertLess(took, 5.0, f"returned in {took:.1f} s while the window stays open {FAKE_SLEEP} s")
        pid, _ = self.window()
        self.assertTrue(alive(pid), "the window is still open after the script returned")
        for test_id in CHANGE_IDS:
            self.assertIn(test_id, out)
        self.assertRegex(out, rf"\b{pid}\b", "the window's pid is printed")
        log = self.log_dir_of(self.argv(pid)) / "godot.log"
        self.assertIn(str(log), out, "the window's own log path is printed")
        self.assertTrue(wait_for(lambda: log.exists() and f"fake godot started pid {pid}" in log.read_text(), 5),
                        f"the window's output goes to the printed log {log}")

    def test_the_window_logs_to_a_fresh_dir_of_its_worktree(self):
        """The window owns its engine log, so another Godot start (which rotates the shared user://logs/godot.log)
        cannot hide its errors: a dir under $TMPDIR named after the worktree, emptied each run."""
        self.make_repo()
        code, out, _ = self.play("a/x")
        self.assertEqual(code, 0, out)
        first, argv = self.window()
        log_dir = self.log_dir_of(argv)
        self.assertEqual(log_dir.parent.resolve(), self.state.resolve(), f"the log dir is under $TMPDIR: {argv}")
        self.assertIn(self.repo.name, log_dir.name, f"the log dir is named after the worktree: {argv}")
        stale = log_dir / "stale.txt"
        stale.write_text("ERROR: a line an earlier window logged\n")
        code, out, _ = self.play("b/y")
        self.assertEqual(code, 0, out)
        self.assertTrue(wait_for(lambda: len(self.launched()) >= 2, 5), "the second run launched a window\n" + out)
        second = self.launched()[-1]
        self.assertEqual(self.log_dir_of(self.argv(second)), log_dir, "the worktree keeps one log dir")
        self.assertFalse(stale.exists(), "the log dir is emptied before the window starts\n" + out)


@unittest.skipUnless(godot_binary(), "no Godot binary (set GODOT=/path/to/Godot)")
class EngineTests(unittest.TestCase):
    """The real engine, headless: the test runner's queued run from `-- --queue=<ids>`."""

    # Two quick tests (one of them a harness test, which --queue plays as --play does), given against id order, and an
    # id that names no test.
    FIRST = "general/keybinds_overrides"
    SECOND = "_harness/log_gate_probe"
    UNKNOWN = "general/no_such_test_zz"
    VERDICT = re.compile(r"^(PASS|FAIL|TIMEOUT|SKIPPED|GAP)\s+(\S+)", re.M)

    def test_queue_plays_the_ids_in_order_and_keeps_the_window_open(self):
        """Rules 5 and 6."""
        tmp = Path(tempfile.mkdtemp(prefix="play_tests_engine_"))
        out_path = tmp / "out.txt"
        env = {k: v for k, v in os.environ.items() if k != "GAME_TEST_PROBE"}  # the probe test passes quietly
        cmd = [godot_binary(), "--headless", "--path", str(ROOT), RUNNER_SCENE, "--",
               f"--queue={self.FIRST},{self.SECOND},{self.UNKNOWN}"]
        with open(out_path, "w") as sink:
            proc = subprocess.Popen(cmd, cwd=ROOT, env=env, stdout=sink, stderr=subprocess.STDOUT)
        try:
            read = lambda: out_path.read_text(errors="replace")
            done = wait_for(lambda: "\nQueue done:" in "\n" + read(), 120)
            out = read()
            self.assertTrue(done, "a line starting `Queue done:` is printed\n" + out)
            self.assertEqual([m.group(2) for m in self.VERDICT.finditer(out)], [self.FIRST, self.SECOND],
                             "both tests played, in the order given\n" + out)
            self.assertTrue(any(self.UNKNOWN in ln and not self.VERDICT.match(ln) for ln in out.splitlines()),
                            "the unknown id is reported\n" + out)
            time.sleep(2.0)
            self.assertIsNone(proc.poll(), "the window stays open after the queue is done\n" + read())
        finally:
            proc.kill()
            proc.wait()
            shutil.rmtree(tmp, ignore_errors=True)

    def test_window_still_fails_a_logged_error_when_another_godot_starts(self):
        """A window tools/play_tests.sh launches (its very argv, run headless) fails the probe's logged error even
        though another Godot starts on the project mid-queue, which rotates the shared user://logs/godot.log."""
        tmp = Path(tempfile.mkdtemp(prefix="play_tests_rotate_"))
        wrapper = tmp / "godot_headless"  # play_tests.sh's own launch, with --headless put in front
        wrapper.write_text(f'#!/usr/bin/env bash\nexec "{godot_binary()}" --headless "$@"\n')
        wrapper.chmod(wrapper.stat().st_mode | stat.S_IEXEC)
        state = tmp / "state"  # the script's $TMPDIR: its pid file and log dir
        state.mkdir()
        env = dict(os.environ, GODOT=str(wrapper), TMPDIR=str(state), GAME_TEST_PROBE="error")
        r = subprocess.run(["bash", str(PLAY), self.FIRST, self.SECOND], cwd=ROOT, env=env, capture_output=True,
                           text=True, timeout=120)
        out = r.stdout + r.stderr
        m = re.search(r"^test window pid (\d+) \| log (.+)$", out, re.M)
        pid = int(m.group(1)) if m else 0
        try:
            self.assertEqual(r.returncode, 0, out)
            self.assertIsNotNone(m, "the window's pid and log are printed\n" + out)
            log = Path(m.group(2).strip())
            read = lambda: log.read_text(errors="replace") if log.exists() else ""
            self.assertTrue(wait_for(lambda: self.VERDICT.search(read()), 120), "the first test's verdict\n" + read())
            # Another start of the project, as an editor's game, tools/lint.sh or another worktree's window makes.
            other_env = {k: v for k, v in os.environ.items() if k != "GAME_TEST_PROBE"}
            subprocess.run([godot_binary(), "--headless", "--path", str(ROOT), "--quit-after", "2"], cwd=ROOT,
                           env=other_env, capture_output=True, timeout=120)
            done = wait_for(lambda: "\nQueue done:" in "\n" + read(), 120)
            text = read()
            self.assertTrue(done, "a line starting `Queue done:` is printed\n" + text)
            verdicts = {test_id: status for status, test_id in self.VERDICT.findall(text)}  # an id's last line wins
            self.assertEqual(verdicts.get(self.SECOND), "FAIL",
                             "the probe's logged error fails it although another Godot started mid-queue\n" + text)
            self.assertRegex(text, r"✗ Logged error: gate probe error", "the failed check names the error\n" + text)
        finally:
            if pid and alive(pid):
                os.kill(pid, signal.SIGKILL)
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
