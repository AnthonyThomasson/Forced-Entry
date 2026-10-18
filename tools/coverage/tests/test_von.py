"""The run's Von decision server handling (runner.ensure_von / runner.stop_von), with stand-in servers: no Von, no
Godot.

  runner.ensure_von(copy, port) -> VonServer    a server that already decides on `port` is reused (started False);
                                                otherwise the copy's `application/von/server_path` is started as
                                                `<path> serve --host 127.0.0.1 --port <port> --device cpu` and
                                                waited for (started True); with no path, none (live False)
  runner.stop_von(server)                       stops the server only if the run started it

A stand-in server answers the game launcher's health check (POST /v1/systemone) with 200, on a free port.
"""
import http.server
import socket
import sys
import threading
import unittest
from pathlib import Path

from tools.coverage import runner
from tools.coverage.tests.support import TempDir

STAND_IN = '''import http.server, sys
port = int(sys.argv[sys.argv.index("--port") + 1])
class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        self.send_response(200 if self.path == "/v1/systemone" else 404)
        self.end_headers()
        self.wfile.write(b"{}")
    def log_message(self, *args):
        pass
http.server.HTTPServer(("127.0.0.1", port), Handler).serve_forever()
'''


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


def project(root: Path, server_path: str = "") -> Path:
    setting = f'von/server_path="{server_path}"\n' if server_path else ""
    (root / "project.godot").write_text(f'config_version=5\n\n[application]\n\nconfig/name="von-test"\n{setting}')
    return root


class VonTests(unittest.TestCase):
    def test_a_live_server_is_reused_and_not_stopped(self):
        server = http.server.HTTPServer(("127.0.0.1", 0), Health)
        port = server.server_address[1]
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        with TempDir() as d:
            von = runner.ensure_von(project(d, "/nonexistent/von-must-not-be-started"), port=port)
            self.assertTrue(von.live)
            self.assertFalse(von.started, "an already-live server is reused, not started")
            self.assertIsNone(von.process)
            runner.stop_von(von)
        self.assertTrue(runner.von_live(port), "the reused server is still live after the run")
        self.assertTrue(thread.is_alive())

    def test_a_server_the_run_started_is_stopped(self):
        port = free_port()
        with TempDir() as d:
            fake = d / "von"
            fake.write_text(f"#!{sys.executable}\n{STAND_IN}")
            fake.chmod(0o755)
            von = runner.ensure_von(project(d, str(fake)), port=port, log_path=d / "von.log")
            try:
                self.assertTrue(von.live)
                self.assertTrue(von.started)
                self.assertTrue(runner.von_live(port))
            finally:
                runner.stop_von(von)
            self.assertIsNotNone(von.process.poll(), "the started server's process has ended")
        self.assertFalse(runner.von_live(port, timeout=1.0))

    def test_no_server_and_no_path_is_not_live_and_says_so(self):
        with TempDir() as d:
            von = runner.ensure_von(project(d), port=free_port())
        self.assertFalse(von.live)
        self.assertFalse(von.started)
        self.assertIn("server_path", von.note)


if __name__ == "__main__":
    unittest.main()
