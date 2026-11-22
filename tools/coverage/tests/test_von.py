"""The run's Von decision server handling (runner.ensure_von / runner.stop_von), with the repo's real boot script
(tools/von/boot.sh, boot.ps1 on Windows) run against the stand-in Von home of tools/tests/fake_von.py: no real Von, no
Godot.

  runner.ensure_von(copy, port) -> VonServer    a server that already decides on `port` is reused (started False);
                                                otherwise the copy's boot script is started from the per-user Von home
                                                (FORCED_ENTRY_HOME) and waited for (started True). A machine with no Von
                                                setup (the script's exit 3) has none (live False, started False, the
                                                note says why); a script that stops for another reason is a RunFailed
  runner.stop_von(server)                       stops the server only if the run started it, the whole tree
  runner.runs_von_tests(args)                   whether a run_tests.sh argument list runs Von tests against the live
                                                server (--include-von, --require-von, --record-von); the run then
                                                has a server ready

The stand-in server answers every GET with 200, and the run's health check (a POST of a decision) is replaced by a GET
of the same port, so the real check is not what these tests are about.
"""
import http.server
import os
import shutil
import socket
import threading
import unittest
import urllib.request
from pathlib import Path
from unittest import mock

from tools.coverage import runner
from tools.coverage.tests.support import ROOT, TempDir, copy_setup
from tools.tests import fake_von


class Health(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        self.send_response(200 if self.path == "/v1/systemone" else 404)
        self.end_headers()
        self.wfile.write(b"{}")

    def log_message(self, *_args):
        pass


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def answers(port: int, timeout: float = 2.0) -> bool:
    """The stand-in's health check: a GET of its port."""
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=timeout) as response:
            return response.status == 200
    except OSError:
        return False


def copy_with_boot(root: Path) -> Path:
    """A stand-in for the run's copy of the repo: the real tools/von and tools/setup."""
    copy = root / "copy"
    copy.mkdir()
    shutil.copytree(ROOT / "tools" / "von", copy / "tools" / "von", ignore=shutil.ignore_patterns("__pycache__"))
    copy_setup(copy)
    return copy


class VonTests(unittest.TestCase):
    def home(self, root: Path, set_up: bool) -> None:
        """FORCED_ENTRY_HOME for this test: the stand-in Von home (set_up) or an empty folder."""
        if set_up:
            fake = fake_von.von_home()
            fake.put_weights()
            home = fake.root
        else:
            home = root / "empty_home"
            home.mkdir()
        patcher = mock.patch.dict(os.environ, {"FORCED_ENTRY_HOME": str(home)})
        patcher.start()
        self.addCleanup(patcher.stop)

    def health(self) -> None:
        patcher = mock.patch.object(runner, "von_live", side_effect=lambda port, timeout=5.0: answers(port))
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_a_live_server_is_reused_and_not_stopped(self):
        server = http.server.HTTPServer(("127.0.0.1", 0), Health)
        port = server.server_address[1]
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        with TempDir() as d:
            von = runner.ensure_von(d / "no_boot_script_must_be_run", port=port)
            self.assertTrue(von.live)
            self.assertFalse(von.started, "an already-live server is reused, not started")
            self.assertIsNone(von.process)
            runner.stop_von(von)
        self.assertTrue(runner.von_live(port), "the reused server is still live after the run")
        self.assertTrue(thread.is_alive())

    def test_a_server_the_run_started_is_stopped_with_everything_under_it(self):
        port = free_port()
        self.health()
        with TempDir() as d:
            self.home(d, set_up=True)
            von = runner.ensure_von(copy_with_boot(d), port=port, log_path=d / "von.log")
            try:
                self.assertTrue(von.live, von.note)
                self.assertTrue(von.started)
                self.assertTrue(answers(port))
            finally:
                runner.stop_von(von)
            self.assertIsNotNone(von.process.poll(), "the started server's process has ended")
            deadline = runner.time.monotonic() + 15
            while answers(port, timeout=1.0) and runner.time.monotonic() < deadline:
                runner.time.sleep(0.25)
            self.assertFalse(answers(port, timeout=1.0), "no server of the started tree keeps answering")

    def test_no_von_setup_is_not_live_and_says_why_and_how_to_fix_it(self):
        with TempDir() as d:
            self.home(d, set_up=False)
            von = runner.ensure_von(copy_with_boot(d), port=free_port(), log_path=d / "von.log")
        self.assertFalse(von.live)
        self.assertFalse(von.started, "nothing was started, so nothing is stopped")
        self.assertIn("no Von venv", von.note)
        self.assertIn("bootstrap", von.note)
        self.assertIn("hold steady", von.note)

    def test_a_copy_with_no_boot_script_has_no_server_and_says_so(self):
        with TempDir() as d:
            von = runner.ensure_von(d, port=free_port())
        self.assertFalse(von.live)
        self.assertFalse(von.started)
        self.assertIn("hold steady", von.note)

    def test_a_boot_script_that_stops_for_another_reason_fails_the_run_naming_why(self):
        # Something else holds the port: the stand-in server cannot bind and ends with its own exit code.
        self.health()
        with TempDir() as d, socket.socket() as holder:
            holder.bind(("127.0.0.1", 0))
            holder.listen()
            port = holder.getsockname()[1]
            self.home(d, set_up=True)
            with self.assertRaises(runner.RunFailed) as raised:
                runner.ensure_von(copy_with_boot(d), port=port, log_path=d / "von.log")
        self.assertIn("stopped with exit", str(raised.exception))

    def test_each_flag_that_runs_von_tests_live_or_records_them_starts_a_server(self):
        for flag in ("--include-von", "--require-von", "--record-von"):
            with self.subTest(flag):
                self.assertTrue(runner.runs_von_tests(["--domain=ai", flag]))

    def test_a_replay_only_run_needs_no_server(self):
        self.assertFalse(runner.runs_von_tests([]))
        self.assertFalse(runner.runs_von_tests(["--domain=ai", "--id=ai/movement/follow_catches_up", "--repeat=3"]))


if __name__ == "__main__":
    unittest.main()
