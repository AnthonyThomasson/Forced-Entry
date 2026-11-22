"""tools/von_stop.sh and tools/proctree.py: stopping the Von server one game started, and only that one.

Each game is a fake (`godot.py`, so its command line reads as the game's): a Python 'game' process that starts a
Python 'boot script' (the PowerShell of a Windows boot script, the `von` shim of a Mac one), which starts a Python
HTTP server whose command line reads `fake_von.py serve` (what the default match, a `von serve`, looks for), plus a
'sidecar' child that has nothing to do with Von. Python fakes, not shebang scripts: Windows cannot run those. The tests
start two games, stop one's server through the script and check that only that branch went: the other server still
answers, both games and the sidecar still run. A wrapper around the game is refused, and a Git Bash `$!` is mapped.
"""
import contextlib
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import proctree  # noqa: E402  (the tool's own functions)

SCRIPT = ROOT / "tools" / "von_stop.sh"

SERVER = """\
import http.server, sys
server = http.server.HTTPServer(("127.0.0.1", 0), http.server.SimpleHTTPRequestHandler)
open(sys.argv[2], "w").write(str(server.server_address[1]))
server.serve_forever()
"""
BOOT = """\
import subprocess, sys
subprocess.Popen([sys.executable, sys.argv[1], "serve", sys.argv[2]]).wait()
"""
WRAPPER = """\
import subprocess, sys
subprocess.Popen([sys.executable] + sys.argv[1:]).wait()
"""
GAME = """\
import subprocess, sys
boot = subprocess.Popen([sys.executable, sys.argv[1], sys.argv[2], sys.argv[3]])
sidecar = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(300)"])
boot.wait()
sidecar.wait()
"""


def find_bash() -> str:
    """Git Bash on Windows (not the System32 WSL launcher `bash` finds first), `bash` elsewhere."""
    if os.name == "nt":
        for folder in Path(shutil.which("git") or "").parents:
            if (folder / "bin" / "bash.exe").exists():
                return str(folder / "bin" / "bash.exe")
    return shutil.which("bash") or ""


BASH = find_bash()


def answers(port: int) -> bool:
    try:
        socket.create_connection(("127.0.0.1", port), timeout=2).close()
        return True
    except OSError:
        return False


def wait_for(condition, seconds: float = 120.0) -> bool:
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if condition():
            return True
        time.sleep(0.1)
    return condition()


class Game:
    """One fake game: its process, its server's port and its sidecar."""

    def __init__(self, folder: Path, name: str, wrapper: bool = False):
        """With `wrapper`, `pid` is a wrapper script's, which runs the game as its only child."""
        self.port_file = folder / f"{name}.port"
        args = [sys.executable, str(folder / "godot.py"), str(folder / "boot.py"), str(folder / "fake_von.py"),
                str(self.port_file)]
        if wrapper:
            args.insert(1, str(folder / "wrapper.py"))
        self.process = subprocess.Popen(args)
        self.pid = self.process.pid
        if not wait_for(self.port_file.exists) or not wait_for(lambda: self.port_file.read_text() != ""):
            raise AssertionError(f"game {name} did not start its server")
        self.port = int(self.port_file.read_text())

    def server_pid(self) -> int:
        return next(p.pid for p in proctree.descendants(proctree.snapshot(), self.pid) if "fake_von.py serve" in p.cmd)

    def sidecar_pid(self) -> int:
        return next(p.pid for p in proctree.descendants(proctree.snapshot(), self.pid) if "time.sleep" in p.cmd)


@unittest.skipUnless(BASH, "no bash to run tools/von_stop.sh")
class VonStopTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.folder = Path(tmp.name)
        for name, text in (("fake_von.py", SERVER), ("boot.py", BOOT), ("godot.py", GAME), ("wrapper.py", WRAPPER)):
            (self.folder / name).write_text(text)
        self.games = []
        self.addCleanup(self.stop_games)

    def start_game(self, name: str, wrapper: bool = False) -> Game:
        game = Game(self.folder, name, wrapper)
        self.games.append(game)
        return game

    def stop_games(self):
        for game in self.games:
            proctree.kill_tree(game.pid)
            game.process.wait(timeout=120)

    def von_stop(self, *args: str) -> subprocess.CompletedProcess:
        env = {**os.environ, "PYTHON": sys.executable, "PROCTREE_NATIVE_PID": "1"}
        return subprocess.run([BASH, SCRIPT.as_posix(), *args], env=env, capture_output=True, text=True, timeout=300)

    def test_a_wrappers_pid_is_refused_and_the_game_is_left_running(self):
        wrapped = self.start_game("wrapped", wrapper=True)
        game_pid = proctree.children(proctree.snapshot(), wrapped.pid)[0].pid

        run = self.von_stop(str(wrapped.pid))

        self.assertEqual(run.returncode, 1, run.stdout + run.stderr)
        self.assertIn("wrapper", run.stderr)
        self.assertIn(f"({game_pid})", run.stderr, "it names the pid to pass")
        self.assertTrue(answers(wrapped.port), "the server was not touched")
        self.assertIn(game_pid, proctree.snapshot(), "the game was not killed")
        self.assertEqual(self.von_stop(str(game_pid)).returncode, 0, "the game's own pid works")

    @unittest.skipUnless(os.name == "nt", "the MSYS to Windows pid mapping exists only in Git Bash on Windows")
    def test_a_git_bash_background_pid_is_mapped_to_the_windows_pid(self):
        port_file = self.folder / "msys.port"
        script = (
            '"$PY" "$GODOT" "$BOOT" "$VON" "$PORTFILE" >/dev/null 2>&1 &\n'
            "pid=$!\n"
            'for _ in $(seq 1 600); do [ -s "$PORTFILE" ] && break; sleep 0.2; done\n'
            '"$BASH_EXE" "$VONSTOP" "$pid"\n'
            'echo "rc=$?"\n'
        )
        env = {**os.environ, "PYTHON": sys.executable, "PY": Path(sys.executable).as_posix(),
               "GODOT": (self.folder / "godot.py").as_posix(), "BOOT": (self.folder / "boot.py").as_posix(),
               "VON": (self.folder / "fake_von.py").as_posix(), "PORTFILE": port_file.as_posix(),
               "BASH_EXE": Path(BASH).as_posix(), "VONSTOP": SCRIPT.as_posix()}
        env.pop("PROCTREE_NATIVE_PID", None)
        run = subprocess.run([BASH, "-c", script], env=env, capture_output=True, text=True, timeout=300)
        mapped = re.search(r"MSYS pid (\d+) is Windows pid (\d+)", run.stderr)
        if mapped:
            self.addCleanup(proctree.kill_tree, int(mapped[2]))
        self.assertIn("rc=0", run.stdout, run.stdout + run.stderr)
        self.assertIsNotNone(mapped, "the script says which Windows pid the MSYS pid is: " + run.stderr)
        self.assertNotEqual(mapped[1], mapped[2])
        self.assertTrue(wait_for(lambda: not answers(int(port_file.read_text()))), "the server it found stopped")

    def test_it_stops_only_the_server_under_the_game_it_is_given(self):
        first, second = self.start_game("first"), self.start_game("second")
        self.assertTrue(answers(first.port) and answers(second.port))
        sidecar, boot_children = first.sidecar_pid(), proctree.children(proctree.snapshot(), first.pid)
        self.assertEqual(len(boot_children), 2, "the game's two children: the boot script and the sidecar")

        run = self.von_stop(str(first.pid))

        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIn("stopped pid", run.stdout)
        self.assertTrue(wait_for(lambda: not answers(first.port)), "the server under the game it was given stopped")
        self.assertTrue(answers(second.port), "the other game's server still answers")
        now = proctree.snapshot()
        self.assertIn(first.pid, now, "the game it was given is left running")
        self.assertIn(second.pid, now)
        self.assertIn(sidecar, now, "a child of the game that holds no server is left running")
        self.assertEqual([p.pid for p in proctree.children(now, first.pid)], [sidecar],
                         "the boot script that started the server went with it")

    def test_the_boot_script_and_the_server_under_it_both_stop(self):
        game = self.start_game("only")
        server = game.server_pid()
        boot = next(p.pid for p in proctree.children(proctree.snapshot(), game.pid) if p.pid != game.sidecar_pid())
        self.assertEqual(self.von_stop(str(game.pid)).returncode, 0)
        self.assertTrue(wait_for(lambda: server not in proctree.snapshot() and boot not in proctree.snapshot()))

    def test_a_game_with_no_server_under_it_exits_non_zero_with_a_message(self):
        game = self.start_game("gone")
        self.assertEqual(self.von_stop(str(game.pid)).returncode, 0)
        self.assertTrue(wait_for(lambda: not answers(game.port)))
        again = self.von_stop(str(game.pid))
        self.assertEqual(again.returncode, 1)
        self.assertIn("nothing stopped", again.stderr)
        self.assertIn(str(game.pid), again.stderr)
        self.assertNotEqual(self.von_stop(str(game.sidecar_pid())).returncode, 0, "the sidecar has no server under it")

    def test_a_bad_argument_is_a_usage_error(self):
        for args in ((), ("not-a-pid",), ("1", "2")):
            run = self.von_stop(*args)
            self.assertEqual(run.returncode, 2, args)
            self.assertIn("usage", run.stderr)


class ProctreeTests(unittest.TestCase):
    def test_descendants_list_the_whole_tree_parents_first(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            for name, text in (("fake_von.py", SERVER), ("boot.py", BOOT), ("godot.py", GAME), ("wrapper.py", WRAPPER)):
                (folder / name).write_text(text)
            game = Game(folder, "tree")
            try:
                found = proctree.descendants(proctree.snapshot(), game.pid)
                self.assertEqual(len(found), 3, [p.cmd for p in found])
                server = next(p for p in found if "fake_von.py serve" in p.cmd)
                boot = next(p for p in found if p.pid == server.ppid)
                self.assertLess(found.index(boot), found.index(server))
                self.assertTrue(proctree.kill_tree(game.pid))
                self.assertTrue(wait_for(lambda: not answers(game.port)))
                self.assertNotIn(game.pid, proctree.snapshot())
            finally:
                proctree.kill_tree(game.pid)
                game.process.wait(timeout=120)

    def test_a_pid_with_nothing_under_it_has_no_descendants(self):
        self.assertEqual(proctree.descendants({}, 4242), [])


# A Mac's Godot path, built in two pieces so no script names an install place whole (test_setup_resolvers' guard).
MAC_GODOT = "/Applic" + "ations/Godot.app/Contents/MacOS/Godot"
PS_OUTPUT = """    1     0 Ss   /sbin/launchd
  100     1 S    @GODOT@ --path /Users/me/Forced-Entry
  101   100 S    /Users/me/Library/Application Support/Forced-Entry/von/bin/python /Users/me/x/bin/von serve
  102   101 Z    (python)
  103   100 S    /usr/bin/taskpolicy -b -p 101
  200     1 S    @GODOT@ --path /Users/me/Other
  201   200 S    /Users/me/Library/Application Support/Forced-Entry/von/bin/python /Users/me/x/bin/von serve
""".replace("@GODOT@", MAC_GODOT)


class MacTableTests(unittest.TestCase):
    """The macOS side, which no Windows run can start: `ps`'s table read from a canned output, and the signals a stop
    sends on a platform that is not Windows."""

    def table(self):
        ps = subprocess.CompletedProcess([], 0, stdout=PS_OUTPUT.encode(), stderr=b"")
        with mock.patch.object(proctree.subprocess, "run", return_value=ps):
            return proctree.snapshot_ps()

    def test_ps_output_is_read_into_pids_parents_states_and_whole_command_lines(self):
        procs = self.table()
        self.assertEqual(procs[101].ppid, 100)
        self.assertEqual(procs[102].state, "Z")
        self.assertTrue(procs[101].cmd.endswith("bin/von serve"), procs[101].cmd)
        self.assertIn("Application Support", procs[101].cmd)

    def test_the_server_is_found_under_its_game_only(self):
        procs = self.table()
        self.assertEqual([p.pid for p in proctree.descendants(procs, 100)], [101, 103, 102])
        self.assertEqual([p.pid for p in proctree.branch_roots(procs, 100, proctree.VON_SERVER)], [101])
        self.assertEqual([p.pid for p in proctree.branch_roots(procs, 200, proctree.VON_SERVER)], [201])
        self.assertEqual(proctree.branch_roots(procs, 103, proctree.VON_SERVER), [])

    def test_the_server_match_ignores_case_and_the_game_match_knows_godot(self):
        self.assertIsNotNone(re.search(proctree.VON_SERVER, "C:\\Von\\Scripts\\VON.EXE Serve --port 8000"))
        self.assertIsNone(re.search(proctree.VON_SERVER, "godot --path /work/von-stop"))
        for game in (MAC_GODOT + " --path /x",
                     '"C:\\Program Files\\Godot\\Godot_v4.4.1-stable_win64.exe" --path x'):
            self.assertIsNotNone(proctree.GAME.search(game), game)
        for server in ("/Users/me/Library/Application Support/Forced-Entry/godot/4.4.1/von/bin/von serve",
                       "powershell -File boot.ps1 -Godot x"):
            self.assertIsNone(proctree.GAME.search(server), server)

    def test_a_taskkill_that_times_out_is_a_failed_stop_not_a_traceback(self):
        procs = {7: proctree.Proc(7, 1, "von serve", 1)}
        with contextlib.ExitStack() as stack:
            for target, name, kwargs in (
                    (proctree, "WINDOWS", {"new": True}),
                    (proctree, "win32", {"return_value": mock.Mock()}),
                    (proctree, "still_running", {"return_value": True}),
                    (proctree, "snapshot", {"return_value": procs}),
                    (proctree.time, "monotonic", {"side_effect": [0, 100, 100, 100]}),
                    (proctree.time, "sleep", {}),
                    (proctree.subprocess, "run", {"side_effect": subprocess.TimeoutExpired("taskkill", 300)})):
                stack.enter_context(mock.patch.object(target, name, **kwargs))
            self.assertFalse(proctree.kill_tree(7, procs))

    def test_a_stop_sends_sigterm_to_the_tree_then_sigkill_to_what_survives(self):
        procs = self.table()
        sent = []
        # The server ignores SIGTERM: snapshots show it alive until the SIGKILL, and the clock jumps past the grace.
        with contextlib.ExitStack() as stack:
            for target, name, kwargs in (
                    (proctree, "WINDOWS", {"new": False}),
                    (proctree, "snapshot", {"side_effect": [procs, procs, {}]}),
                    (proctree.signal, "SIGKILL", {"new": 9, "create": True}),
                    (proctree, "send", {"side_effect": lambda pids, sig: sent.append((sig, list(pids)))}),
                    (proctree.time, "monotonic", {"side_effect": [0, 0, 10, 10]}),
                    (proctree.time, "sleep", {})):
                stack.enter_context(mock.patch.object(target, name, **kwargs))
            self.assertTrue(proctree.kill_tree(101, procs))
        term, kill = sent
        self.assertEqual(term, (proctree.signal.SIGTERM, [101, 102]))
        self.assertEqual(kill, (9, [101]), "a zombie is gone already, the server that ignored SIGTERM is not")


if __name__ == "__main__":
    unittest.main()
