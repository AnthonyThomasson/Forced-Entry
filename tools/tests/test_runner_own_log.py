"""The in-game test runner reports only its own process's engine errors, on every start path that has no `--out`
(`-- --play`, the Tests browser): the default log, `user://logs/godot.log`, is written by every Godot start of the project
(lint, editors, shard runs, another worktree's window) and rotated by each start by copying and truncating it, so no part
of it is one process's alone. A runner reads only the log its process was started with (`--log-file`); a start without
one watches none and says so.

Each case runs the real engine headless in a copy of this checkout whose `user://` is a folder of its own
(`config/custom_user_dir_name`), so the shared default log of the live checkout is never read or written. The runner is
started as `-- --play` starts it (no `--log-file`, no `--out`) on the log gate probe, and a second Godot start on the
copy logs an error and a warning, which rotates the log the runner was reading.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

from tools.coverage.tests.support import clean_env, godot_binary, needs_godot
from tools.test_log_gate import copy_checkout

RUNNER_SCENE = "res://scenes/testing/test_runner.tscn"
VERDICT = re.compile(r"^(PASS|FAIL|TIMEOUT|SKIPPED|GAP)\s+(\S+)", re.M)
FOREIGN = "foreign process error"
FOREIGN_SCRIPT = f'extends SceneTree\n\n\nfunc _init() -> void:\n\tpush_error("{FOREIGN}")\n\tpush_warning("foreign process warning")\n\tquit()\n'
# The editor plugin's log argument (addons/ticket_autorun/game_log_argument.gd), driven as the editor's save hook
# drives it (`EditorPlugin` itself cannot be made outside the editor): after each step it prints whether the project
# setting the editor reads on Play exists and what it holds, and whether a project file saved then would hold it.
ARGUMENT_SCRIPT = '''extends SceneTree

const Argument := preload("res://addons/ticket_autorun/game_log_argument.gd")


func _report(step: String) -> void:
	var path := OS.get_environment("SAVED") + "/" + step + ".godot"
	ProjectSettings.save_custom(path)
	var saved := FileAccess.get_file_as_string(path).contains(Argument.RUN_ARGS.get_file())
	print("STEP %s present=%s value=%s saved=%s" % [step, ProjectSettings.has_setting(Argument.RUN_ARGS),
		ProjectSettings.get_setting(Argument.RUN_ARGS, "<missing>"), saved])


func _init() -> void:
	_report("start")
	Argument.give()
	_report("given")
	Argument.after_save()
	_report("after_save")
	Argument.forget()
	_report("forgotten")
	quit()
'''
STEP = re.compile(r"^STEP (\w+) present=(\w+) value=(.*) saved=(\w+)$", re.M)


def os_data_dir() -> Path:
    """The OS data folder Godot puts a project's custom user:// folder in."""
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support"
    if sys.platform.startswith("win"):
        return Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming"))
    return Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share")


def wait_for(cond, timeout: float) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if cond():
            return True
        time.sleep(0.1)
    return cond()


@needs_godot
class RunnerOwnLogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp(prefix="runner_own_log."))
        cls.copy = copy_checkout(cls.tmp / "copy")
        cls.user_dir = os_data_dir() / f"fe-own-log-{cls.tmp.name}"
        project = cls.copy / "project.godot"
        head = "[application]\n"
        text = project.read_text()
        assert head in text, "project.godot has an [application] section"
        project.write_text(text.replace(head, head + "\nconfig/use_custom_user_dir=true\n"
                                        f'config/custom_user_dir_name="{cls.user_dir.name}"\n', 1))
        (cls.tmp / "foreign.gd").write_text(FOREIGN_SCRIPT)
        # The copy has no .godot/ class cache of its own unless the checkout had one: import it once.
        subprocess.run([godot_binary(), "--headless", "--path", str(cls.copy), "--import"], capture_output=True,
                       timeout=300, env=clean_env())

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)
        shutil.rmtree(cls.user_dir, ignore_errors=True)

    def start_runner(self, name: str, log: Path | None = None, **env: str):
        """The runner as `-- --play` starts it: no `--out`, and no `--log-file` unless `log` is given. Returns the
        process and a reader of its stdout."""
        out_path = self.tmp / f"{name}.txt"
        engine = ["--log-file", str(log)] if log else []
        cmd = [godot_binary(), "--headless", "--path", str(self.copy), *engine, RUNNER_SCENE, "--",
               "--play", "log", "gate", "probe"]
        environ = {k: v for k, v in clean_env().items() if k != "GAME_TEST_PROBE"}  # the probe passes quietly
        environ.update(env)
        with open(out_path, "w") as sink:
            proc = subprocess.Popen(cmd, cwd=self.copy, env=environ, stdout=sink, stderr=subprocess.STDOUT)
        self.addCleanup(lambda: (proc.kill(), proc.wait()))
        return proc, lambda: out_path.read_text(errors="replace")

    def other_godot_start(self):
        """Another start of the project on the copy, logging an error and a warning: a Godot that rotates the default
        log the runner follows and then writes the shared name afresh."""
        r = subprocess.run([godot_binary(), "--headless", "--path", str(self.copy), "-s", str(self.tmp / "foreign.gd")],
                           cwd=self.copy, env=clean_env(), capture_output=True, text=True, timeout=120)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        logs = self.user_dir / "logs"
        self.assertTrue(any(FOREIGN in p.read_text(errors="replace") for p in logs.glob("godot*.log")),
                        "premise: the other start logged its error to the shared default log")

    def test_an_error_another_godot_logs_never_reaches_the_runner(self):
        """A start with no log of its own (`-- --play` in a terminal, the editor's Play, the Tests button)."""
        proc, read = self.start_runner("foreign")
        self.assertTrue(wait_for(lambda: VERDICT.search(read()), 120), "the probe's verdict\n" + read())
        self.other_godot_start()
        time.sleep(2.0)  # the runner polls the log every physics frame
        self.assertIsNone(proc.poll(), "the runner stays open\n" + read())
        out = read()
        self.assertNotIn("foreign process", out, "the other start's error and warning stay out of the runner\n" + out)
        self.assertEqual([m.group(1) for m in VERDICT.finditer(out)], ["PASS"], "and no verdict flips\n" + out)

    def test_a_start_with_no_log_of_its_own_says_it_watches_none(self):
        """Its own errors cannot be told apart in the shared default log: the runner says so and fails nothing."""
        proc, read = self.start_runner("unwatched", GAME_TEST_PROBE="error")
        self.assertTrue(wait_for(lambda: VERDICT.search(read()), 120), "the probe's verdict\n" + read())
        out = read()
        self.assertRegex(out, r"NOTE: .*errors and warnings will NOT fail this test", out)
        self.assertIn("--log-file", out, "and how to give it a log\n" + out)

    def test_its_own_error_fails_the_test_though_another_godot_started_meanwhile(self):
        """A start with a log of its own (`--log-file`): the other start rotates and writes the default log, and the
        runner's own error, logged after it, is still its own."""
        go = self.tmp / "go"
        go.unlink(missing_ok=True)
        proc, read = self.start_runner("own", log=self.tmp / "own.log", GAME_TEST_PROBE="error",
                                       GAME_TEST_PROBE_AFTER=str(go))
        self.assertTrue(wait_for(lambda: "probe waiting for" in read(), 120), "the probe waits to log\n" + read())
        self.other_godot_start()
        go.write_text("go")  # the probe logs its error now
        self.assertTrue(wait_for(lambda: "✗ Logged error: gate probe error" in read(), 60),
                        "the runner reports its own error\n" + read())
        out = read()
        self.assertNotIn("foreign process", out, out)
        self.assertNotIn("NOTE:", out, "a start with a log of its own watches it\n" + out)
        verdicts = {test_id: status for status, test_id in VERDICT.findall(out)}
        self.assertEqual(verdicts.get("_harness/log_gate_probe"), "FAIL", out)

    def run_argument_steps(self, log_file: str | None) -> dict[str, tuple[bool, str, bool]]:
        """What the editor's Play would read at each step of the plugin's hooks: (present, value, saved)."""
        script, saved = self.tmp / "argument.gd", self.tmp / "saved"
        script.write_text(ARGUMENT_SCRIPT)
        saved.mkdir(exist_ok=True)
        env = {**clean_env(), "SAVED": str(saved)}
        env.pop("GAME_LOG_FILE", None)
        if log_file:
            env["GAME_LOG_FILE"] = log_file
        r = subprocess.run([godot_binary(), "--headless", "--path", str(self.copy), "--log-file",
                            str(self.tmp / "argument.log"), "-s", str(script)],
                           cwd=self.copy, env=env, capture_output=True, text=True, timeout=120)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        steps = {m.group(1): (m.group(2) == "true", m.group(3), m.group(4) == "true")
                 for m in STEP.finditer(r.stdout)}
        self.assertEqual(list(steps), ["start", "given", "after_save", "forgotten"], r.stdout + r.stderr)
        return steps

    def test_the_editors_log_argument_is_never_missing_when_play_reads_it(self):
        """The editor's save hook runs just before Play reads `editor/run/main_run_args` for the game's command line:
        the setting must still exist then, holding the game's `--log-file` (a setting erased and put back a frame
        later is missing for that read: the editor logs `Property not found` and the game starts with none)."""
        log = str(self.tmp / "game.engine.log")
        steps = self.run_argument_steps(log)
        self.assertEqual(steps["given"][:2], (True, "--log-file " + log), "premise: given, the argument is set")
        self.assertEqual(steps["after_save"][:2], (True, "--log-file " + log), "present and set after the save hook")

    def test_the_editors_log_argument_is_left_out_of_the_saved_project_when_forgotten(self):
        """Forgotten (the editor closing), the setting is back at its default, which a saved project.godot omits; and
        it is still there, not erased."""
        steps = self.run_argument_steps(str(self.tmp / "game.engine.log"))
        self.assertEqual(steps["forgotten"], (True, "", False), "present, empty, not in the saved project")

    def test_the_editors_log_argument_touches_nothing_without_a_game_log(self):
        """No `GAME_LOG_FILE` (an editor not started by tools/editor.sh): every step leaves the setting as it was."""
        steps = self.run_argument_steps(None)
        self.assertEqual(steps, {step: steps["start"] for step in steps})


if __name__ == "__main__":
    unittest.main(verbosity=2)
