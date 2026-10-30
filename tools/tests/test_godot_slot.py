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


if __name__ == "__main__":
    unittest.main()
