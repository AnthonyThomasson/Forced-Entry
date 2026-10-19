#!/usr/bin/env python3
"""Tests for a run of the editor's GdUnit panel: the verdicts of the command line, and the checkout left as it was.

  python3 tools/test_gdunit_panel.py            the panel's runner, headless
  python3 tools/test_gdunit_panel.py --headed   also the panel's runner in a window, as the panel starts it

The panel's Run (addons/gdUnit4/src/core/command/GdUnitCommandHandler.gd) discovers the cases, saves them with its TCP
server's port to res://addons/gdUnit4/GdUnitRunner.cfg and starts GdUnitTestRunner.tscn as
`godot --no-window --path <project> <runner scene>`: no `--fixed-fps`, so the engine paces the run to the clock, no
`--` options (no `--out`, no selection) and gdUnit's default report folder, res://reports/. tools/gdunit_panel.gd
does the same without an editor (its TCP server, its run config, its runner arguments) and prints each case's verdict
as gdUnit reports it to the panel. Each class runs it on a scratch copy of the checkout with a user:// of its own.

Headless (always):
  - a case per catalog id runs to its verdict and the session closes (the runner is then stopped, as the editor
    stops it);
  - the harness's `_harness/frame_step` passes: every physics frame a test waits brings a process frame, which a run
    paced to the clock breaks by catching a slow frame up with several physics steps in one iteration (the cause of
    the draw tests' failures under the panel), and the two draw tests pass;
  - no res://reports/ appears; gdUnit's JUnit report lands in user://gdunit_reports/ and lists the cases;
  - every file the run writes in the checkout is one .gitignore ignores, so `git status` stays clean.
With --headed (a window, run by hand; perf numbers want a quiet machine, check `uptime`):
  - the nine timing tests, the two draw tests and the two click tests pass in the panel's windowed runner as under
    `tools/run_tests.sh --windowed`.
Skipped when no Godot binary is found.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))  # run as a script: the repo root, for tools.coverage.tests.support
from tools.coverage.tests.support import clean_env  # noqa: E402
HEADED = "--headed" in sys.argv
PANEL = "res://tools/gdunit_panel.gd"
SCAN = ROOT / "tools" / "scan_godot_log.py"
FRAME_STEP = "_harness/frame_step"
DRAW_TESTS = ["ui/leader_overlay_draw", "ai/debug/vision_overlay_cone_along_wall"]
CLICK_TESTS = ["ui/command_menu_items", "ui/inspector_outfit"]
# The tests with a wall-clock budget that a run paced to the clock failed (issue #70, feedback round 1).
TIMING_TESTS = [
    "perf/automatic_fire_stress", "perf/crowd_deaths_stress", "perf/furniture_pile_stress",
    "perf/grenade_burst_stress", "perf/grenade_match_stress", "perf/hit_overload_stress",
    "perf/match_10v10_stress", "perf/npc_crowd_stress", "audio/bank",
]


def godot_binary():
    for name in ("godot", "godot4"):
        p = shutil.which(name)
        if p:
            return p
    for p in sorted(Path("/Applications").glob("Godot*.app/Contents/MacOS/Godot")):
        return str(p)
    return os.environ.get("GODOT")


def os_data_dir() -> Path:
    """The OS data folder Godot puts a project's custom user:// folder in (`config/custom_user_dir_name`)."""
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support"
    if sys.platform.startswith("win"):
        return Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming"))
    return Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share")


def files_of(root: Path) -> dict:
    """Every file under `root` but the import cache: relative path -> (size, mtime)."""
    out = {}
    for p in root.rglob("*"):
        rel = p.relative_to(root)
        if p.is_file() and rel.parts[0] != ".godot":
            st = p.stat()
            out[rel.as_posix()] = (st.st_size, st.st_mtime_ns)
    return out


class PanelRun:
    """One panel run of `ids` on a fresh copy of the checkout: its cases, its output and the files it touched."""

    def __init__(self, ids, headless_runner, timeout):
        self.tmp = Path(tempfile.mkdtemp(prefix="gdunit_panel_"))
        self.copy = self.tmp / "checkout"
        listed = subprocess.run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=ROOT,
                                env=clean_env(), check=True, capture_output=True).stdout.decode()
        for rel in sorted({p for p in listed.split("\0") if p}):
            src = ROOT / rel
            # A panel run's leftovers in this checkout (an untracked report folder) are not copied: the copy shows
            # what the run writes.
            if rel.startswith(("artifacts/", "reports/")) or not src.is_file():
                continue
            (self.copy / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, self.copy / rel)
        if (ROOT / ".godot").is_dir():
            shutil.copytree(ROOT / ".godot", self.copy / ".godot", symlinks=True)
        self.user_dir = os_data_dir() / f"fe-gdunit-panel-{self.tmp.name}"
        project = self.copy / "project.godot"
        head = "[application]\n"
        text = project.read_text()
        assert head in text, "project.godot has an [application] section"
        project.write_text(text.replace(head, head + "\nconfig/use_custom_user_dir=true\n"
                                        f'config/custom_user_dir_name="{self.user_dir.name}"\n', 1))
        self.before = files_of(self.copy)
        log = self.tmp / "panel.log"
        # Its options go by environment: options after `--` would reach the suites (test_batch.gd) as a selection.
        env = dict(clean_env(), GDUNIT_PANEL_IDS=",".join(ids), GDUNIT_PANEL_TIMEOUT=str(timeout),
                   GDUNIT_PANEL_HEADLESS="1" if headless_runner else "0")
        cmd = [godot_binary(), "--headless", "--path", str(self.copy), "--log-file", str(log), "-s", PANEL]
        r = subprocess.run(cmd, cwd=self.copy, env=env, capture_output=True, text=True, timeout=timeout + 120)
        self.code = r.returncode
        self.out = r.stdout + r.stderr
        self.cases = {}
        for line in r.stdout.splitlines():
            if line.startswith("CASE "):
                c = json.loads(line[len("CASE "):])
                self.cases[c["id"]] = c
        self.done = next((line.split() for line in r.stdout.splitlines() if line.startswith("DONE ")), [])
        self.after = files_of(self.copy)
        self.runner_log = self.user_dir / "logs" / "godot.log"

    def written(self):
        """The files the run added or changed in the checkout."""
        return sorted(p for p, stamp in self.after.items() if self.before.get(p) != stamp)

    def status(self, test_id):
        return self.cases.get(test_id, {}).get("status")

    def failures(self, ids):
        return {i: self.cases.get(i, {"status": "not run"}) for i in ids if self.status(i) != "passed"}

    def remove(self):
        shutil.rmtree(self.tmp, ignore_errors=True)
        shutil.rmtree(self.user_dir, ignore_errors=True)


@unittest.skipUnless(godot_binary(), "no Godot binary (set GODOT=/path/to/Godot)")
class PanelHeadlessTests(unittest.TestCase):
    """The panel's runner, started as the panel starts it but headless."""

    maxDiff = None  # a failure prints each failed case's checks whole

    IDS = [FRAME_STEP] + DRAW_TESTS + ["projectile/pistol_shot_wounds"]

    @classmethod
    def setUpClass(cls):
        cls.panel = PanelRun(cls.IDS, headless_runner=True, timeout=600)

    @classmethod
    def tearDownClass(cls):
        cls.panel.remove()

    def test_each_case_runs_to_a_verdict_and_the_session_closes(self):
        self.assertEqual(self.panel.code, 0, self.panel.out[-4000:])
        self.assertEqual(sorted(self.panel.cases), sorted(self.IDS), self.panel.out[-4000:])
        self.assertEqual(self.panel.done[2:], ["stopped"], self.panel.out[-4000:])

    def test_each_physics_frame_a_test_waits_brings_a_process_frame(self):
        self.assertEqual(self.panel.status(FRAME_STEP), "passed", self.panel.cases.get(FRAME_STEP))

    def test_the_draw_tests_pass(self):
        self.assertEqual(self.panel.failures(DRAW_TESTS), {})

    def test_no_report_folder_appears_in_the_checkout(self):
        self.assertFalse((self.panel.copy / "reports").exists(), self.panel.written())

    def test_gdunits_reports_land_in_user_dir(self):
        xml = self.panel.user_dir / "gdunit_reports" / "report_1" / "results.xml"
        self.assertTrue(xml.is_file(), f"no JUnit report at {xml}")
        names = [tc.get("name") for tc in ET.parse(xml).iter("testcase")]
        for test_id in self.IDS:
            self.assertTrue(any(f"('{test_id}')" in n for n in names), f"{test_id} not in {names}")

    def test_every_file_the_run_writes_in_the_checkout_is_ignored(self):
        written = self.panel.written()
        self.assertTrue(written, "the run wrote nothing in the checkout: its run config, at least")
        r = subprocess.run(["git", "check-ignore", "--no-index", "--verbose", "--non-matching", *written], cwd=ROOT,
                           env=clean_env(), capture_output=True, text=True)
        not_ignored = [line.split("\t", 1)[1] for line in r.stdout.splitlines() if line.startswith("::")]
        self.assertEqual(not_ignored, [], "files a panel run leaves for `git status`")

    def test_nothing_is_logged_outside_a_test(self):
        scan = subprocess.run([sys.executable, "-I", str(SCAN), str(self.panel.runner_log)], capture_output=True,
                              text=True)
        self.assertEqual(scan.returncode, 0, scan.stdout)


@unittest.skipUnless(godot_binary(), "no Godot binary (set GODOT=/path/to/Godot)")
@unittest.skipUnless(HEADED, "pass --headed to run the panel's runner in a window")
class PanelWindowedTests(unittest.TestCase):
    """The panel's runner in a window, as the panel starts it: the timing, draw and click tests of the user's panel
    run (issue #70, feedback round 1) pass as under `tools/run_tests.sh --windowed`."""

    maxDiff = None  # a failure prints each failed case's checks whole

    IDS = TIMING_TESTS + DRAW_TESTS + CLICK_TESTS + [FRAME_STEP]

    @classmethod
    def setUpClass(cls):
        cls.panel = PanelRun(cls.IDS, headless_runner=False, timeout=1200)

    @classmethod
    def tearDownClass(cls):
        cls.panel.remove()

    def test_each_case_runs_to_a_verdict(self):
        self.assertEqual(sorted(self.panel.cases), sorted(self.IDS), self.panel.out[-4000:])

    def test_the_timing_tests_pass(self):
        self.assertEqual(self.panel.failures(TIMING_TESTS), {})

    def test_the_draw_tests_pass(self):
        self.assertEqual(self.panel.failures(DRAW_TESTS + [FRAME_STEP]), {})

    def test_the_click_tests_pass(self):
        self.assertEqual(self.panel.failures(CLICK_TESTS), {})

    def test_no_report_folder_appears_in_the_checkout(self):
        self.assertFalse((self.panel.copy / "reports").exists(), self.panel.written())


if __name__ == "__main__":
    sys.argv = [a for a in sys.argv if a != "--headed"]
    unittest.main(verbosity=2)
