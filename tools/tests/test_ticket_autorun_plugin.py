"""The editor plugin's autorun (addons/ticket_autorun/plugin.gd) presses Play from the editor's own `_process`.

`EditorInterface.play_main_scene()` opens a progress dialog. Called inside a `SceneTreeTimer`'s `timeout` the editor's
main loop runs inside `SceneTree::process_timers`, which erases the same timer twice (engine error `p_I->data != this`
at `list.h:231`, no game started, and a crash now and then); called through `call_deferred` the editor refuses the
dialog ("Do not use progress dialog while flushing the message queue"). The editor cannot be made outside a window, so
the test reads what the plugin does: it makes no timer, and runs `_play` from `_process` only.
"""
import re
import unittest
from pathlib import Path

PLUGIN = Path(__file__).resolve().parents[2] / "addons" / "ticket_autorun" / "plugin.gd"


class AutorunPlayTests(unittest.TestCase):
    def setUp(self):
        lines = PLUGIN.read_text().splitlines()
        self.source = "\n".join(line for line in lines if not line.lstrip().startswith("#"))

    def test_no_timer_starts_play(self):
        self.assertNotIn("create_timer", self.source)
        self.assertNotIn("call_deferred", self.source)

    def test_play_is_run_from_process_only(self):
        calls = [m.start() for m in re.finditer(r"(?<![\w.])_play\(\)", self.source)]
        calls = [at for at in calls if not self.source.startswith("func ", at - 5)]
        process = re.search(r"^func _process\(.*?(?=^func |\Z)", self.source, re.S | re.M)
        self.assertIsNotNone(process, "the plugin has a _process")
        self.assertTrue(calls, "the plugin plays the main scene")
        for at in calls:
            self.assertTrue(process.start() <= at < process.end(), "_play() is called outside _process")

    def test_process_runs_only_when_autorun_is_asked_for(self):
        ready = re.search(r"^func _ready\(.*?(?=^func |\Z)", self.source, re.S | re.M)
        self.assertIsNotNone(ready, "the plugin gates processing in _ready, after READY enables it")
        body = ready.group(0)
        off = body.index("set_process(false)")
        guard = body.index('OS.get_environment("GAME_AUTORUN")')
        on = body.index("set_process(true)")
        self.assertLess(off, guard, "_process is off until the autorun is asked for")
        self.assertLess(guard, on, "_process is turned on only after the GAME_AUTORUN check")
        self.assertIn("_countdown = AUTORUN_DELAY", body)


if __name__ == "__main__":
    unittest.main(verbosity=2)
