"""tools/lint_engine.py: the engine pass of tools/lint.sh runs bounded. A script with a parse error puts a `--debug`
Godot 4.4.1 on Windows at its `debug>` prompt, where it answers the closed stdin by breaking again and again (a log of
561,000 lines and 26 MB in three minutes) and never exits, so lint.sh waited forever and left the engine running."""
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import lint_engine  # noqa: E402  (the tool's own functions)
import proctree  # noqa: E402

# A fake engine: `MODE` picks what it does. It writes its pid to $PIDFILE; `child` also starts a child that sleeps.
ENGINE = r'''
import os, subprocess, sys, time
mode = os.environ["MODE"]
open(os.environ["PIDFILE"], "w").write(str(os.getpid()))
if mode == "child":
    kid = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(600)"])
    open(os.environ["PIDFILE"] + ".kid", "w").write(str(kid.pid))
if mode == "clean":
    print("LINT-PASS2"); print("LINT-DONE 3"); sys.exit(0)
if mode == "fails":
    print("some output"); sys.exit(7)
if mode == "spin":
    print("Godot Engine v4")
    while True:
        print("Debugger Break, Reason: 'Parser Error: Expected expression as the function argument.'")
        print("*Frame 0 - res://a.gd:4 in function ''")
        print('Enter "help" for assistance.')
        print("debug> ", flush=True)
        time.sleep(0.001)
if mode == "spin_noisy":  # the real log's lines (CRLF), and a stray line or two between the breaks
    out = sys.stdout.buffer
    while True:
        out.write(b"Debugger Break, Reason: 'Parser Error: Expected expression as the function argument.'\r\n")
        out.write(b"*Frame 0 - res://a.gd:4 in function ''\r\n")
        out.write(b"\r\n")
        out.write(b"   At: res://a.gd:4\r\n")
        out.write(b'Enter "help" for assistance.\r\n')
        out.write(b"debug> \r\n")
        out.flush()
        time.sleep(0.001)
if mode == "breaks_then_goes_on":
    for i in range(150):
        print("Debugger Break, Reason: 'Parser Error: script %d'" % i)
        print("debug> ", flush=True)
    print("LINT-DONE 150"); sys.exit(0)
time.sleep(600)  # "child" and "silent": nothing more, until killed
'''


class LintEngineRunTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.engine = self.dir / "engine.py"
        self.engine.write_text(ENGINE)
        self.pidfile = self.dir / "pid"
        self.log = self.dir / "lint.log"

    def run_engine(self, mode, timeout=60, stuck_after=100):
        os.environ["MODE"], os.environ["PIDFILE"] = mode, str(self.pidfile)
        self.addCleanup(os.environ.pop, "MODE", None)
        self.addCleanup(os.environ.pop, "PIDFILE", None)
        started = time.monotonic()
        code = lint_engine.run([sys.executable, str(self.engine)], self.log, timeout=timeout, stuck_after=stuck_after)
        return code, time.monotonic() - started

    def pid_gone(self, pid_file):
        pid = int(Path(pid_file).read_text())
        return pid not in proctree.snapshot()

    def test_a_clean_run_gives_the_engines_exit_code_and_its_whole_output_in_the_log(self):
        self.assertEqual(self.run_engine("clean")[0], 0)
        self.assertEqual(self.log.read_text().split(), ["LINT-PASS2", "LINT-DONE", "3"])

    def test_a_failing_engine_gives_its_own_exit_code(self):
        self.assertEqual(self.run_engine("fails")[0], 7)
        self.assertIn("some output", self.log.read_text())

    def test_an_engine_that_never_ends_is_stopped_at_the_deadline_with_its_children(self):
        code, took = self.run_engine("child", timeout=3)
        self.assertEqual(code, lint_engine.TIMED_OUT)
        self.assertLess(took, 300, "it waited the deadline, not the engine's ten minutes")
        self.assertTrue(self.pid_gone(self.pidfile), "the engine is gone")
        self.assertTrue(self.pid_gone(str(self.pidfile) + ".kid"), "and what it started")

    def test_an_engine_stuck_breaking_at_the_same_error_is_stopped_at_once_and_the_log_stays_small(self):
        code, took = self.run_engine("spin", timeout=60)
        self.assertEqual(code, lint_engine.TIMED_OUT)
        self.assertLess(took, 30, "stopped when it began to repeat itself, not at the deadline")
        self.assertTrue(self.pid_gone(self.pidfile))
        text = self.log.read_text()
        self.assertIn("Parser Error: Expected expression", text, "the reason of the break is in the log")
        self.assertLess(text.count("Debugger Break"), 400, "the endless repeat is not written down")

    def test_a_stray_line_between_the_breaks_does_not_hide_the_loop(self):
        code, took = self.run_engine("spin_noisy", timeout=120)
        self.assertEqual(code, lint_engine.TIMED_OUT)
        self.assertLess(took, 100, "stopped when it began to repeat itself, not at the deadline")
        self.assertTrue(self.pid_gone(self.pidfile))

    def test_a_missing_engine_is_exit_127(self):
        code = lint_engine.run([str(self.dir / "no-such-engine")], self.log)
        self.assertEqual(code, 127)

    def test_distinct_breaks_that_go_on_are_no_loop(self):
        self.assertEqual(self.run_engine("breaks_then_goes_on")[0], 0)
        self.assertIn("LINT-DONE 150", self.log.read_text())

    def test_the_command_line_runs_the_engine_and_says_why_it_stopped(self):
        env = dict(os.environ, MODE="silent", PIDFILE=str(self.pidfile))
        r = subprocess.run([sys.executable, "-I", str(ROOT / "tools" / "lint_engine.py"), str(self.log), "--timeout", "2",
                            "--", sys.executable, str(self.engine)], capture_output=True, text=True, env=env, timeout=120)
        self.assertEqual(r.returncode, lint_engine.TIMED_OUT, r.stdout + r.stderr)
        self.assertIn("did not finish within 2 s", r.stderr)
        self.assertTrue(self.pid_gone(self.pidfile))

    def test_a_bad_command_line_is_exit_2(self):
        r = subprocess.run([sys.executable, "-I", str(ROOT / "tools" / "lint_engine.py"), str(self.log)],
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 2)
        self.assertIn("usage", r.stderr)


if __name__ == "__main__":
    unittest.main()
