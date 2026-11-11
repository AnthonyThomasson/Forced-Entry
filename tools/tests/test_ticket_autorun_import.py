"""A fresh headless import without GAME_AUTORUN must not press Play (#204).

The scratch copy's main scene quits on its first frame, so even the failing case leaves no game window open. Cleanup also
ends any game whose command line names the import editor's pid, after the editor has exited and the game may be orphaned.
"""
import os
import re
import shutil
import signal
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

from tools.coverage.tests.support import clean_env, godot_binary, needs_godot
from tools.test_log_gate import copy_checkout

PLAY_LINE = "[worktree] autorun: playing the main scene"
STUB_SCENE = """[gd_scene load_steps=2 format=3]

[ext_resource type=\"Script\" path=\"res://autorun_test_main.gd\" id=\"1\"]

[node name=\"AutorunTestMain\" type=\"Node\"]
script = ExtResource(\"1\")
"""
STUB_SCRIPT = """extends Node


func _process(_delta: float) -> void:
	get_tree().quit()
"""


def games_from_editor(editor_pid: int) -> list[tuple[int, str]]:
    """Live processes whose argv has this editor's exact --editor-pid value."""
    ps = subprocess.run(["ps", "-axo", "pid=,command="], check=True, capture_output=True, text=True).stdout
    tagged = re.compile(rf"(?:^|\s)--editor-pid\s+{editor_pid}(?:\s|$)")
    games = []
    for line in ps.splitlines():
        pid, _, command = line.strip().partition(" ")
        if tagged.search(command):
            games.append((int(pid), command))
    return games


def kill_games(editor_pid: int) -> None:
    games = games_from_editor(editor_pid)
    for pid, _command in games:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 2.0
    while games and time.monotonic() < deadline:
        time.sleep(0.05)
        alive = {pid for pid, _command in games_from_editor(editor_pid)}
        games = [game for game in games if game[0] in alive]
    for pid, _command in games:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


@needs_godot
class TicketAutorunImportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="ticket_autorun_import."))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.copy = copy_checkout(self.tmp / "copy")
        shutil.rmtree(self.copy / ".godot", ignore_errors=True)  # a fresh, never-imported checkout

        project = self.copy / "project.godot"
        main_scene = 'run/main_scene="res://scenes/main.tscn"'
        self.assertIn(main_scene, project.read_text(), "premise: the checkout has its usual main scene")
        project.write_text(project.read_text().replace(
            main_scene, 'run/main_scene="res://autorun_test_main.tscn"', 1))
        (self.copy / "autorun_test_main.tscn").write_text(STUB_SCENE)
        (self.copy / "autorun_test_main.gd").write_text(STUB_SCRIPT)

    def test_headless_import_without_autorun_starts_no_game(self):
        env = clean_env()
        env.pop("GAME_AUTORUN", None)
        editor = subprocess.Popen(
            [godot_binary(), "--headless", "--path", str(self.copy), "--import"],
            cwd=self.copy, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        self.addCleanup(self._cleanup, editor)
        try:
            output, _ = editor.communicate(timeout=120)
        except subprocess.TimeoutExpired:
            editor.kill()
            output, _ = editor.communicate()
            self.fail("the fresh headless import did not exit within 120 seconds\n" + output)
        self.assertEqual(editor.returncode, 0, "the fresh headless import itself succeeds\n" + output)

        games = games_from_editor(editor.pid)
        if PLAY_LINE in output:
            deadline = time.monotonic() + 5.0
            while not games and time.monotonic() < deadline:
                time.sleep(0.05)
                games = games_from_editor(editor.pid)
        self.assertNotIn(PLAY_LINE, output, "the import editor pressed Play without GAME_AUTORUN")
        self.assertEqual(games, [], "the import editor left a game process running")

    @staticmethod
    def _cleanup(editor: subprocess.Popen) -> None:
        kill_games(editor.pid)
        if editor.poll() is None:
            editor.kill()
            editor.wait()


if __name__ == "__main__":
    unittest.main(verbosity=2)
