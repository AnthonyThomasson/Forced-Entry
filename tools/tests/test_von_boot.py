"""tools/von/boot.sh and boot.ps1: start the Von server from <von home>, or say fast why it cannot start.

Both scripts run against the fake Von home of fake_von.py (a real venv with a stand-in von-sdk that serves HTTP 200):
bash on every OS, Windows PowerShell 5.1 on Windows. The interface under test: `--check` / `-Check` exits 0 with
`von: ready` or 3 with one cause line `von: <cause>. Fix: <bootstrap command>`; a start runs `von serve --host H --port N
--device D` with <von home> as its working directory, passes the server's output and exit code through, and (PowerShell)
ends the server when the script is ended.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.request
from pathlib import Path

from tools.tests import fake_von

ROOT = Path(__file__).resolve().parents[2]
WINDOWS = sys.platform == "win32"
BASH = shutil.which("bash")
POWERSHELL = shutil.which("powershell") if WINDOWS else None
BOOT_SH = ROOT / "tools" / "von" / "boot.sh"
BOOT_PS1 = ROOT / "tools" / "von" / "boot.ps1"
FIX = "bootstrap.ps1" if WINDOWS else "bootstrap.sh"


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def answers(port: int) -> bool:
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=2) as r:
            return r.status == 200
    except OSError:
        return False


def wait_for(cond, seconds: float) -> bool:
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if cond():
            return True
        time.sleep(0.25)
    return cond()


class Boot:
    """One way to run a boot script: `command(args)` is the argv, args in the bash spelling (`--check --port 1`)."""

    def __init__(self, name: str, script: Path):
        self.name, self.script = name, script

    def command(self, args: list) -> list:
        if self.name == "bash":
            return [BASH, str(self.script), *args]
        names = {"--check": "-Check", "--port": "-Port", "--host": "-BindHost", "--device": "-Device"}
        return [POWERSHELL, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(self.script),
                *[names.get(a, a) for a in args]]


def boots() -> list:
    found = [Boot("bash", BOOT_SH)] if BASH else []
    if POWERSHELL:
        found.append(Boot("powershell", BOOT_PS1))
    return found


class BootCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fake = fake_von.von_home()

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="von_boot."))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.fake.put_weights()
        self.addCleanup(self.fake.clear_weights)
        (self.fake.von_home / "served.json").unlink(missing_ok=True)

    def env(self, **over) -> dict:
        env = {k: v for k, v in os.environ.items() if k not in ("PYTHONPATH", "PYTHONHOME", "VIRTUAL_ENV")}
        env["FORCED_ENTRY_HOME"] = str(self.fake.root)
        env.update(over)
        return env

    def each(self, check) -> None:
        """`check(boot)` for boot.sh and, on Windows, boot.ps1, each its own subtest."""
        for boot in boots():
            with self.subTest(boot=boot.name):
                check(boot)

    def run_boot(self, boot: Boot, args: list, **over) -> subprocess.CompletedProcess:
        return subprocess.run(boot.command(args), env=self.env(**over), capture_output=True, text=True, timeout=120)

    def swap(self, path: Path, new_text: str = "", *, rename_to: Path | None = None) -> None:
        """Break a file for the rest of the test; it is put back at cleanup."""
        original = path.read_bytes()
        if rename_to is not None:
            path.rename(rename_to)
            self.addCleanup(rename_to.rename, path)
        else:
            path.write_text(new_text)
            self.addCleanup(path.write_bytes, original)


class CheckTests(BootCase):
    def assert_broken(self, boot: Boot, cause_pattern: str, **over) -> None:
        r = self.run_boot(boot, ["--check"], **over)
        self.assertEqual(r.returncode, 3, r.stdout + r.stderr)
        lines = [ln for ln in r.stderr.splitlines() if ln.strip()]
        self.assertEqual(len(lines), 1, f"one cause line, got: {r.stderr!r}")
        self.assertRegex(lines[0], rf"^von: {cause_pattern}\. Fix: .*{re.escape(FIX)}$")
        self.assertEqual(r.stdout.strip(), "")

    def test_a_complete_setup_is_ready(self):
        def check(boot):
            r = self.run_boot(boot, ["--check"])
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertRegex(r.stdout.strip(), r"^von: ready \(")
            self.assertEqual(r.stderr.strip(), "")
        self.each(check)

    def test_no_venv(self):
        def check(boot):
            self.assert_broken(boot, r"no Von venv at .*venv", FORCED_ENTRY_HOME=str(self.tmp / "empty"))
        self.each(check)

    def test_a_venv_whose_base_python_is_gone(self):
        cfg = self.fake.venv / "pyvenv.cfg"
        self.swap(cfg, re.sub(r"(?m)^home = .*$", lambda _m: "home = " + str(self.tmp / "gone"), cfg.read_text()))
        def check(boot):
            self.assert_broken(boot, r"the Von venv's base Python is gone \(pyvenv\.cfg home = .*gone\)")
        self.each(check)

    def test_a_venv_without_von_sdk(self):
        von = self.fake.bin / ("von.exe" if WINDOWS else "von")
        self.swap(von, rename_to=self.tmp / "von.moved")
        def check(boot):
            self.assert_broken(boot, r"von-sdk is not installed in the Von venv \(.*von.* is missing\)")
        self.each(check)

    def test_missing_weights(self):
        self.fake.clear_weights()
        def check(boot):
            self.assert_broken(boot, r"the Von weights are missing \(.*von-1\.2.*\)")
        self.each(check)
        self.fake.put_weights()
        (self.fake.weights / "model.safetensors").write_text("")  # an empty file is a missing one
        def check(boot):
            self.assert_broken(boot, r"the Von weights are missing \(.*model\.safetensors\)")
        self.each(check)

    def test_check_runs_von_version(self):
        mod = self.fake.site_packages() / "fakevon.py"
        self.swap(mod, "import sys\nsys.exit(5)\n")
        def check(boot):
            self.assert_broken(boot, r"'von --version' fails in the Von venv")
        self.each(check)

    def test_a_bad_argument_exits_2_in_bash(self):
        if not BASH:
            self.skipTest("no bash")
        for args in (["--bogus"], ["--port", "not-a-number"]):
            r = self.run_boot(Boot("bash", BOOT_SH), args)
            self.assertEqual(r.returncode, 2, r.stderr)


class StartTests(BootCase):
    def start(self, boot: Boot, *extra, **over) -> tuple:
        port = free_port()
        proc = subprocess.Popen(boot.command(["--port", str(port), *extra]), env=self.env(**over),
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        self.addCleanup(proc.stdout.close)  # runs after stop
        self.addCleanup(self.stop, proc)
        self.assertTrue(wait_for(lambda: answers(port), 60), f"{boot.name}: no answer on {port}; exit {proc.poll()}")
        return proc, port

    def stop(self, proc: subprocess.Popen) -> None:
        """What the game does (a kill of the script's pid), then whatever server is left: a script that does not end its
        server (bash on Windows, where exec starts a child) must not leave one behind the tests."""
        served = self.fake.von_home / "served.json"
        pid = None
        try:
            pid = json.loads(served.read_text()).get("pid")
        except (OSError, ValueError):
            pass
        if proc.poll() is None:
            proc.kill()
        proc.wait(timeout=30)
        if pid:
            try:
                os.kill(pid, signal.SIGTERM)
            except OSError:
                pass

    def test_it_serves_from_the_von_home_with_the_arguments_given(self):
        def check(boot):
            (self.fake.von_home / "served.json").unlink(missing_ok=True)
            proc, port = self.start(boot, "--device", "cpu", PYTHONPATH=str(self.tmp))
            served = json.loads((self.fake.von_home / "served.json").read_text())
            self.assertTrue(os.path.samefile(served["cwd"], self.fake.von_home), served)
            self.assertEqual(served["args"], ["serve", "--host", "127.0.0.1", "--port", str(port), "--device", "cpu"])
            self.assertIsNone(served["pythonpath"], "the caller's PYTHONPATH is not the server's")
            self.assertIsNone(proc.poll(), "the script stays alive while the server runs")
        self.each(check)

    def test_the_server_output_is_the_scripts_output(self):
        def check(boot):
            proc, port = self.start(boot)
            self.stop(proc)
            self.assertIn(f"fake von serving on 127.0.0.1 {port}", proc.stdout.read())
        self.each(check)

    def test_the_servers_exit_code_is_the_scripts(self):
        def check(boot):
            r = self.run_boot(boot, ["--device", "crash"])
            self.assertEqual(r.returncode, 7, r.stdout + r.stderr)
        self.each(check)

    @unittest.skipUnless(POWERSHELL, "boot.ps1 is the Windows script")
    def test_ending_boot_ps1_ends_the_server_too(self):
        proc, port = self.start(Boot("powershell", BOOT_PS1))
        # A kill of the script's pid alone (what the game does), not of its tree: the job object ends the rest.
        proc.kill()
        self.assertTrue(wait_for(lambda: not answers(port), 20), "the server outlived boot.ps1")

    @unittest.skipIf(WINDOWS, "under MSYS bash an exec starts the program as a child; on a Mac boot.sh becomes the server")
    def test_boot_sh_becomes_the_server(self):
        proc, port = self.start(Boot("bash", BOOT_SH))
        proc.terminate()  # a kill of boot.sh's pid is a kill of the server: nothing is left listening
        self.assertTrue(wait_for(lambda: not answers(port), 20))


if __name__ == "__main__":
    unittest.main()
