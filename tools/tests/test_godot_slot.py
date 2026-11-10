"""tools/godot_slot.py's own functions on a temporary slot directory (GAME_TEST_SLOT_DIR): taking a slot while other
processes reclaim the same orphaned one or delete its file under it, and probing the pool (`free`, `status`) without
taking a slot. (The pool around a whole run_tests.sh run is tools/test_log_gate.py's SlotPoolTests.)"""
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SLOT_TOOL = ROOT / "tools" / "godot_slot.py"
sys.path.insert(0, str(ROOT / "tools"))
import godot_slot  # noqa: E402  (the tool's own functions, for the tests that need no process of their own)

# A process holding the lock of a slot file, as a Von server a dead engine started does: the file names `argv[2]`.
HOLDER = (
    "import fcntl, os, sys, time\n"
    "fd = os.open(sys.argv[1], os.O_RDWR | os.O_CREAT, 0o644)\n"
    "fcntl.flock(fd, fcntl.LOCK_EX)\n"
    "os.write(fd, sys.argv[2].encode())\n"
    "print('held', flush=True)\n"
    "time.sleep(300)\n"
)

# A pool of one slot: waits until the epoch second argv[2], then takes a slot, says whether it got it and holds it.
TAKER = (
    "import sys, time\n"
    f"sys.path.insert(0, {str(ROOT / 'tools')!r})\n"
    "import godot_slot\n"
    "godot_slot.size = lambda: 1\n"
    "while time.time() < float(sys.argv[1]):\n"
    "    pass\n"
    "fd = godot_slot.take_any()\n"
    "print('got' if fd is not None else 'none', flush=True)\n"
    "time.sleep(3)\n"
)

# Takes and lets go of the pool's only slot over and over for argv[2] seconds.
CHURN = (
    "import sys, time\n"
    f"sys.path.insert(0, {str(ROOT / 'tools')!r})\n"
    "import godot_slot\n"
    "godot_slot.size = lambda: 1\n"
    "end = time.time() + float(sys.argv[1])\n"
    "while time.time() < end:\n"
    "    fd = godot_slot.take_any()\n"
    "    if fd is not None:\n"
    "        import os\n"
    "        os.close(fd)\n"
)

# Deletes the slot file as fast as it can for argv[2] seconds.
DELETER = (
    "import sys, time\n"
    "from pathlib import Path\n"
    "path = Path(sys.argv[1])\n"
    "end = time.time() + float(sys.argv[2])\n"
    "while time.time() < end:\n"
    "    path.unlink(missing_ok=True)\n"
)


def dead_pid() -> int:
    """The pid of a process that has ended."""
    p = subprocess.Popen(["true"])
    p.wait()
    return p.pid


class SlotFixture(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="godot_slot_"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.slots = self.tmp / "slots"
        self.procs = []
        self.addCleanup(self.stop_procs)

    def stop_procs(self):
        for p in self.procs:
            p.kill()
            p.wait()

    def spawn(self, code, *args, **kw):
        p = subprocess.Popen([sys.executable, "-c", code, *map(str, args)], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             text=True, **kw)
        self.procs.append(p)
        return p

    def hold(self, path, pid):
        """A live process holding `path`'s lock whose file names `pid`."""
        p = self.spawn(HOLDER, path, pid)
        self.assertEqual(p.stdout.readline().strip(), "held")
        return p

    def tool(self, *args, **env_extra):
        env = dict(os.environ, GAME_TEST_SLOT_DIR=str(self.slots), **env_extra)
        r = subprocess.run([sys.executable, "-I", str(SLOT_TOOL), *args], env=env, capture_output=True, text=True, timeout=30)
        return r.returncode, r.stdout.strip(), r.stderr


class ReclaimRaceTests(SlotFixture):
    ROUNDS = 12
    TAKERS = 6

    def test_two_reclaimers_of_one_orphaned_slot_never_both_hold_it(self):
        # The orphan outlived its engine (a Von server): its lock is held, its file names a dead pid. Six processes find
        # it at once; exactly one may end up holding the slot, however they interleave.
        for n in range(self.ROUNDS):
            with self.subTest(round=n):
                slots = self.tmp / f"round{n}"
                slots.mkdir()
                orphan = self.hold(slots / "slot0.lock", dead_pid())
                start = time.time() + 0.4
                takers = [self.spawn(TAKER, start, env=dict(os.environ, GAME_TEST_SLOT_DIR=str(slots)))
                          for _ in range(self.TAKERS)]
                said = [t.stdout.readline().strip() for t in takers]
                errors = []
                for t in takers:
                    t.kill()
                    errors.append(t.stderr.read())
                orphan.kill()
                self.assertEqual([e for e in errors if "Traceback" in e], [], "a taker died on the race")
                self.assertEqual(said.count("got"), 1, f"{said}: the orphaned slot is held by exactly one")

    def test_a_slot_file_deleted_under_a_taker_does_not_crash_it(self):
        self.slots.mkdir()
        env = dict(os.environ, GAME_TEST_SLOT_DIR=str(self.slots))
        deleter = self.spawn(DELETER, self.slots / "slot0.lock", 2.0)
        churn = [self.spawn(CHURN, 2.0, env=env) for _ in range(3)]
        for p in churn:
            _, err = p.communicate(timeout=30)
            self.assertEqual(p.returncode, 0, err)
        deleter.communicate(timeout=30)


class ProbeTests(SlotFixture):
    def test_probing_takes_nothing_and_writes_nothing(self):
        self.slots.mkdir()
        free_file = self.slots / "slot0.lock"
        free_file.write_text(str(dead_pid()))  # a slot nobody holds, naming the last holder
        before = (free_file.read_text(), free_file.stat().st_ino, free_file.stat().st_mtime_ns)
        for command in ("free", "status"):
            code, out, err = self.tool(command)
            self.assertEqual(code, 0, err)
        self.assertEqual((free_file.read_text(), free_file.stat().st_ino, free_file.stat().st_mtime_ns), before)

    def test_probing_makes_no_slot_files(self):
        self.tool("free")
        self.tool("status")
        made = sorted(p.name for p in self.slots.iterdir()) if self.slots.exists() else []
        self.assertEqual(made, [], "no slot file")

    def test_probing_an_orphaned_slot_counts_it_free_and_leaves_it_in_place(self):
        self.slots.mkdir()
        orphan = self.hold(self.slots / "slot0.lock", dead_pid())
        inode = (self.slots / "slot0.lock").stat().st_ino
        size = max(1, (os.cpu_count() or 2) // 2)
        self.assertEqual(self.tool("free")[1], str(size))
        self.assertEqual(self.tool("status")[1], f"0 {size}")
        self.assertEqual((self.slots / "slot0.lock").stat().st_ino, inode, "the orphan's file is not replaced by a probe")
        orphan.kill()

    def test_a_slot_held_by_a_live_process_is_counted_taken(self):
        self.slots.mkdir()
        holder = self.hold(self.slots / "slot0.lock", os.getpid())
        size = max(1, (os.cpu_count() or 2) // 2)
        self.assertEqual(self.tool("status")[1], f"1 {size}")
        self.assertEqual(self.tool("free")[1], str(size - 1))
        holder.kill()


# What the wrapper does when it is interrupted: a process that has started argv[1] as its child (none when empty) runs
# `stop` for its own descendants (stop is one of them, as it is under the wrapper) and says what came of it.
INTERRUPTED = (
    "import json, os, subprocess, sys, time\n"
    "child = subprocess.Popen([sys.executable, '-c', sys.argv[1]]) if sys.argv[1] else None\n"
    f"tool = {str(SLOT_TOOL)!r}\n"
    "started = time.monotonic()\n"
    "code = subprocess.run([sys.executable, '-I', tool, 'stop', '--ancestor=%d' % os.getpid()]).returncode\n"
    "took = time.monotonic() - started\n"
    "ended = None\n"
    "if child:\n"
    "    try:\n"
    "        ended = child.wait(timeout=2)\n"
    "    except subprocess.TimeoutExpired:\n"
    "        child.kill()\n"
    "print(json.dumps({'code': code, 'took': took, 'child': ended}))\n"
)

# A child that ends on SIGTERM, and one that survives it.
SLEEPER = "import time; time.sleep(300)"
DEAF_CHILD = "import signal, time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(300)"


class StopTests(SlotFixture):
    def interrupted(self, child_code, window):
        """A run that starts `child_code` and is stopped with a SIGTERM window of `window` seconds: what `stop` made of it."""
        env = dict(os.environ, GAME_TEST_STOP_WAIT=str(window))
        p = self.spawn(INTERRUPTED, child_code, env=env)
        out, err = p.communicate(timeout=60)
        self.assertEqual(p.returncode, 0, err)
        return json.loads(out)

    def test_a_stop_with_nothing_left_of_the_run_returns_at_once(self):
        # Its own ps and the stop process itself are under the run, and are not what it started.
        r = self.interrupted("", 30)
        self.assertEqual(r["code"], 0)
        self.assertLess(r["took"], 3, "nothing is left to end: the stop does not wait out its 30 s window")

    def test_a_child_that_ends_on_sigterm_is_ended_and_the_stop_returns_at_once(self):
        r = self.interrupted(SLEEPER, 30)
        self.assertEqual(r["code"], 0)
        self.assertEqual(r["child"], -signal.SIGTERM, "the child got SIGTERM")
        self.assertLess(r["took"], 3, "it ended on SIGTERM: the stop does not wait out the window")

    def test_a_child_that_ignores_sigterm_is_killed_when_the_window_has_passed(self):
        r = self.interrupted(DEAF_CHILD, 1)
        self.assertEqual(r["code"], 0)
        self.assertEqual(r["child"], -signal.SIGKILL, "the child was killed")
        self.assertGreaterEqual(r["took"], 1, "SIGTERM was given its window first")
        self.assertLess(r["took"], 4, "then SIGKILL, and nothing left ends the stop")


GODOT = "Godot"


class FakeMachine:
    """A process table that is read twice, `sample` seconds apart on a clock of its own: each process is
    (parent pid, cpu seconds burned per second, name), its cpu time the seconds of that clock times its rate. Nothing sleeps."""

    def __init__(self, procs):
        self.procs, self.now = procs, 100.0

    def table(self):
        return {pid: (ppid, rate * self.now, name) for pid, (ppid, rate, name) in self.procs.items()}

    def sleep(self, seconds):
        self.now += seconds

    def clock(self):
        return self.now

    def other_godots(self, ancestor=5, **kw):
        return godot_slot.other_godots(ancestor, snapshot=self.table, sleep=self.sleep, clock=self.clock, **kw)


class BusyGodotTests(unittest.TestCase):
    """The other Godot processes the quiet gate waits for and the PERF lines count: engines that are busy (cpu over a
    threshold across a short sample). A godot-mcp server (a node process) and an idle editor are not."""

    def test_an_idle_editor_and_a_godot_mcp_server_are_not_counted(self):
        machine = FakeMachine({
            10: (1, 0.01, GODOT),                       # an editor nobody is touching
            11: (1, 0.9, "node"),                       # a godot-mcp server, however busy it is: it is not an engine
            12: (1, 0.0, "npm exec @coding-solo/godot-mcp@0.1.1"),
        })
        self.assertEqual(machine.other_godots(busy_cpu=20, sample_s=2), 0)

    def test_another_worktrees_busy_test_run_is_counted(self):
        machine = FakeMachine({10: (1, 1.0, GODOT), 11: (1, 0.01, GODOT), 12: (1, 0.9, "node")})
        self.assertEqual(machine.other_godots(busy_cpu=20, sample_s=2), 1, "the busy engine, not the idle one")

    def test_an_engine_the_ancestor_started_is_not_counted_however_busy(self):
        machine = FakeMachine({5: (1, 0.0, "bash"), 6: (5, 0.0, "python3"), 10: (6, 1.0, GODOT), 11: (1, 1.0, GODOT)})
        self.assertEqual(machine.other_godots(ancestor=5, busy_cpu=20, sample_s=2), 1, "the run's own engine is left out")

    def test_the_threshold_is_a_percent_of_one_core_over_the_sample(self):
        machine = FakeMachine({10: (1, 0.25, GODOT)})
        self.assertEqual(machine.other_godots(busy_cpu=20, sample_s=2), 1, "25 percent is over 20")
        self.assertEqual(machine.other_godots(busy_cpu=40, sample_s=2), 0, "25 percent is under 40")
        self.assertEqual(machine.other_godots(busy_cpu=25, sample_s=2), 0, "at the threshold is not over it")

    def test_a_process_that_started_during_the_sample_burns_from_nothing(self):
        # No first reading of it: its cpu time over the whole sample counts.
        machine = FakeMachine({10: (1, 1.0, GODOT)})
        first = machine.table
        machine.table = lambda: {} if machine.now == 100.0 else first()
        self.assertEqual(machine.other_godots(busy_cpu=20, sample_s=2), 0, "unseen at the start: not judged on a guess")

    def test_the_sample_waits_the_sample_length(self):
        machine = FakeMachine({10: (1, 1.0, GODOT)})
        machine.other_godots(busy_cpu=20, sample_s=3)
        self.assertEqual(machine.now, 103.0)

    def test_a_name_is_an_engines_when_it_starts_with_godot_whatever_its_case(self):
        for name, engine in (("Godot", True), ("godot.macos.editor.arm64", True), ("Godot_v4.4-stabl", True),
                             ("node", False), ("python3", False), ("mygodot", False), ("npm exec x/godot-mcp", False)):
            with self.subTest(name=name):
                self.assertEqual(godot_slot.is_engine(name), engine)

    def test_the_cpu_time_formats_ps_prints(self):
        for text, seconds in (("0:00.43", 0.43), ("1:37.33", 97.33), ("1:02:03", 3723.0), ("2-01:00:00", 176400.0), ("0:07", 7.0)):
            with self.subTest(text=text):
                self.assertAlmostEqual(godot_slot.cpu_seconds(text), seconds)

    def test_the_real_process_table_lists_this_process_with_a_cpu_time(self):
        row = godot_slot.cpu_table()[os.getpid()]
        self.assertEqual(row[0], os.getppid())
        self.assertGreaterEqual(row[1], 0.0)
        self.assertIn("python", row[2].lower())

    def test_the_options_the_wrapper_passes_are_read_by_the_gate(self):
        args = ["--busy-cpu=35", "--busy-sample=0.5"]
        self.assertEqual(godot_slot.busy_options(args), (35.0, 0.5))
        self.assertEqual(godot_slot.busy_options([]), (20.0, 2.0), "the conf's values when none is given")


if __name__ == "__main__":
    unittest.main()
