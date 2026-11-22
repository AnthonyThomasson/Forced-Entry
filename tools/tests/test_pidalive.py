"""tools/setup/pidalive.py: whether a pid is running. On Windows `os.kill(pid, 0)` would end the process asked about, so
the probe is the point: a live process must survive being asked, and an ended one (or a pid nothing holds) reads dead."""
import subprocess
import sys
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.setup import pidalive  # noqa: E402


class PidAliveTests(unittest.TestCase):
    def test_this_process_is_alive(self):
        import os
        self.assertTrue(pidalive.alive(os.getpid()))

    def test_asking_does_not_end_a_live_process(self):
        child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])
        self.addCleanup(child.wait)
        self.addCleanup(child.kill)
        for _ in range(5):
            self.assertTrue(pidalive.alive(child.pid))
        time.sleep(0.2)
        self.assertIsNone(child.poll(), "the probe ended the process it asked about")

    def test_a_process_that_ended_is_dead_even_while_a_handle_to_it_is_held(self):
        child = subprocess.Popen([sys.executable, "-c", "pass"])
        child.wait()  # `child` still holds its handle (Windows) or has been reaped (POSIX)
        self.assertFalse(pidalive.alive(child.pid))

    def test_a_pid_no_process_has_is_dead(self):
        child = subprocess.Popen([sys.executable, "-c", "pass"])
        child.wait()
        pid = child.pid
        del child
        self.assertFalse(pidalive.alive(pid))
        self.assertFalse(pidalive.alive(0))
        self.assertFalse(pidalive.alive(-5))


if __name__ == "__main__":
    unittest.main()
