"""tools/run_tests.sh --require-von (and --record-von): before any engine starts, a preflight stops the run when the Von
setup is missing or broken, naming which and printing the bootstrap command for the OS. The run is a throwaway tree
around a fake Godot (tools/tests/fake_tree.py) and the fake Von home of tools/tests/fake_von.py, whose venv a test breaks
the way a removed Python, a deleted venv or a broken von-sdk would.
"""
import os
import re
import shutil
import sys
import unittest
from pathlib import Path

from tools.tests import fake_von
from tools.tests.fake_tree import FakeTree

ROOT = Path(__file__).resolve().parents[2]
WINDOWS = sys.platform == "win32"
# The bootstrap command the message must print for this OS: Windows's even though run_tests.sh runs in Git Bash.
FIX = r"powershell -ExecutionPolicy Bypass -File tools\setup\bootstrap.ps1" if WINDOWS else "tools/setup/bootstrap.sh"


class PreflightTests(FakeTree):
    @classmethod
    def setUpClass(cls):
        cls.home = fake_von.von_home()

    def setUp(self):
        super().setUp()
        shutil.copytree(ROOT / "tools" / "von", self.repo / "tools" / "von", ignore=shutil.ignore_patterns("__pycache__"))
        self.home.put_weights()
        self.addCleanup(self.home.clear_weights)

    def run_von(self, *args, home: Path | None = None, **env):
        """The wrapper with the Von home of this test: the fake one unless `home`."""
        return self.run_tests(*args, FORCED_ENTRY_HOME=str(home or self.home.root), **env)

    def swap(self, path: Path, new_text: str = "", *, rename_to: Path | None = None) -> None:
        """Break a file for the rest of the test; it is put back at cleanup."""
        original = path.read_bytes()
        if rename_to is not None:
            path.rename(rename_to)
            self.addCleanup(rename_to.rename, path)
        else:
            path.write_text(new_text)
            self.addCleanup(path.write_bytes, original)

    def assert_stopped(self, code: int, out: str, cause: str) -> None:
        self.assertEqual(code, 1, out)
        self.assertRegex(out, r"--require-von: no test ran, the Von decision server cannot start on this machine\.")
        self.assertRegex(out, rf"von: {cause}\. Fix: {re.escape(FIX)}")
        self.assertEqual(self.started(), [], "no engine process was started")
        self.assertEqual(self.listed(), [], "not even to list the tests")

    def test_a_missing_venv_stops_the_run_before_any_test(self):
        empty = self.tmp / "empty_home"
        empty.mkdir()
        code, out = self.run_von("--require-von", "--id=general/m_suite", home=empty)
        self.assert_stopped(code, out, r"no Von venv at .*venv")

    def test_a_venv_whose_base_python_is_gone_is_named(self):
        cfg = self.home.venv / "pyvenv.cfg"
        self.swap(cfg, re.sub(r"(?m)^home = .*$", lambda _m: "home = " + str(self.tmp / "gone"), cfg.read_text()))
        code, out = self.run_von("--require-von", "--id=general/m_suite")
        self.assert_stopped(code, out, r"the Von venv's base Python is gone \(pyvenv\.cfg home = .*gone\)")

    def test_a_von_that_will_not_run_is_named(self):
        module = self.home.site_packages() / "fakevon.py"
        self.swap(module, "import sys\nsys.exit(5)\n")
        code, out = self.run_von("--require-von", "--id=general/m_suite")
        self.assert_stopped(code, out, r"'von --version' fails in the Von venv")

    def test_missing_weights_are_named(self):
        self.home.clear_weights()
        code, out = self.run_von("--require-von", "--id=general/m_suite")
        self.assert_stopped(code, out, r"the Von weights are missing \(.*von-1\.2.*\)")

    def test_record_von_is_stopped_the_same_way(self):
        empty = self.tmp / "empty_home"
        empty.mkdir()
        code, out = self.run_von("--record-von", "--id=general/m_suite", home=empty)
        self.assertEqual(code, 1, out)
        self.assertIn("--record-von: no test ran", out)
        self.assertEqual(self.started(), [])

    def test_a_complete_setup_runs_the_tests(self):
        code, out = self.run_von("--require-von", "--id=general/m_suite", suite="general/m_suite")
        self.assertNotIn("cannot start on this machine", out)
        self.assertEqual(len(self.started()), 1, out)

    def test_a_run_that_needs_no_server_never_looks_at_the_setup(self):
        empty = self.tmp / "empty_home"
        empty.mkdir()
        for flag in ("--include-von", None):
            with self.subTest(flag=flag):
                self.starts.unlink(missing_ok=True)
                code, out = self.run_von(*([flag] if flag else []), "--id=general/m_suite", suite="general/m_suite", home=empty)
                self.assertNotIn("cannot start on this machine", out)
                self.assertEqual(len(self.started()), 1, out)

    def test_a_port_given_for_the_launcher_to_probe_needs_no_setup(self):
        empty = self.tmp / "empty_home"
        empty.mkdir()
        code, out = self.run_von("--require-von", "--id=general/m_suite", suite="general/m_suite", home=empty,
                                 GAME_TEST_VON_PORT="1")
        self.assertNotIn("cannot start on this machine", out)
        self.assertEqual(len(self.started()), 1, out)


if __name__ == "__main__":
    unittest.main()
