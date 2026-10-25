#!/usr/bin/env python3
"""Tests for the gate that fails a test run on any engine error or warning.

  python3 tools/test_log_gate.py            scanner + wrapper (fake Godot) + the real engine, headless
  python3 tools/test_log_gate.py --headed   also the real engine WITH a window (batch --shots and the in-game runner)

(The GDScript lint that runs first has its own tests at the end: lint_report.py on crafted logs, run_tests.sh
aborting on a lint failure, the clean-lint fingerprint in a throwaway repo, the real engine through tools/lint.sh, and
gdstyle in tools/lint.sh on probe scripts, a probe per quality/* rule of gdstyle.toml on or off by decision among them,
each written into a copy of the checkout.)

Three layers, because the gate has three parts:
  1. tools/scan_godot_log.py on crafted logs (what counts as an error, the shutdown leak NOTE, --from offsets).
  2. tools/run_tests.sh against a fake `godot` that writes the log / report we choose, so every way a run can end
     (error after the runner stopped judging, no report, a shard failing, --list) is checked without an engine.
  3. The real engine: tests/_harness/log_gate_probe_test.gd logs an error / warning on purpose (GAME_TEST_PROBE) and
     the run must FAIL in batch and in the in-game runner (`-- --play`), headless and (with --headed) windowed.
Layer 3 is skipped when no Godot binary is found.

The run goes through gdUnit4 underneath (issue #70): GdUnitCommandLineTests checks, around a fake Godot, how
run_tests.sh starts gdUnit's command-line tool (headless, `--fixed-fps 60`, a log of its own per process), and
GdUnitEngineTests checks, on the real engine through the harness probes in tests/_harness/, that the verdicts, lines,
summary, report.json and bundles keep their shape, that gdUnit's JUnit and HTML reports land in the run's out dir with
the same verdicts (a GAP skipped, "gap: expected to fail"), that a logged warning ends its test at once, that a
requires_von test with no server is skipped (FAIL under --require-von), and that the flags still work: --id, --domain
and --skip-domain given twice add up (in a --list and in a run of native suites), --repeat reruns a native suite and
names its flaky case (a probe suite in a copy of the checkout), and a selection that holds no test fails ("no test
matched") while a --list that lists none passes.
FreshUserDirTests runs one native suite in a copy of the checkout whose user:// holds no logs/godot.log (a fresh
clone, CI): gdUnit's own log monitor reads the run's log, nothing is logged outside a test, project.godot is untouched.
"""
import json
import os
import re
import shutil
import socket
import stat
import subprocess
import sys
import tempfile
import time
import tomllib
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCAN = ROOT / "tools" / "scan_godot_log.py"
RUN = ROOT / "tools" / "run_tests.sh"
HEADED = "--headed" in sys.argv


def godot_binary():
    for name in ("godot", "godot4"):
        p = shutil.which(name)
        if p:
            return p
    for p in sorted(Path("/Applications").glob("Godot*.app/Contents/MacOS/Godot")):
        return str(p)
    return os.environ.get("GODOT")


def copy_checkout(dest: Path) -> Path:
    """A copy of this checkout at `dest` (its tracked and untracked files, not the ignored ones nor artifacts/, and its
    .godot import cache), for a run whose suites or settings must not appear in the live tree. It has no .git, so the
    wrapper's clean-lint fingerprint cannot be taken there: run it with --no-lint."""
    listed = subprocess.run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=ROOT,
                            check=True, capture_output=True).stdout.decode()
    for rel in sorted({p for p in listed.split("\0") if p}):
        src = ROOT / rel
        if rel.startswith("artifacts/") or not src.is_file():
            continue
        (dest / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest / rel)
    if (ROOT / ".godot").is_dir():
        shutil.copytree(ROOT / ".godot", dest / ".godot", symlinks=True)
    return dest


def scan(text: str, *flags: str):
    with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False) as f:
        f.write(text)
    try:
        r = subprocess.run([sys.executable, "-I", str(SCAN), f.name, *flags], capture_output=True, text=True)
    finally:
        os.unlink(f.name)
    return r.returncode, r.stdout


class ScannerTests(unittest.TestCase):
    def test_clean_log_passes(self):
        self.assertEqual(scan("Godot Engine v4.4\nsome print\n")[0], 0)

    def test_every_error_and_warning_header_fails(self):
        for line in ("ERROR: x", "WARNING: x", "SCRIPT ERROR: Parse Error: x", "USER SCRIPT ERROR: x",
                     "USER ERROR: x", "SHADER ERROR: x", "USER WARNING: x", "SCRIPT WARNING: x"):
            code, out = scan(line + "\n   at: f (a.gd:1)\n")
            self.assertEqual(code, 1, line)
            self.assertIn("Logged outside any test", out)

    def test_colour_codes_do_not_hide_an_error(self):
        self.assertEqual(scan("\x1b[1;31mERROR:\x1b[0;91m boom\n")[0], 1)

    def test_von_launcher_diagnostics_are_allowed(self):
        self.assertEqual(scan("WARNING: [von] server not found\n")[0], 0)

    def test_from_offset_skips_what_was_already_judged(self):
        head = "ERROR: judged by the runner\n"
        self.assertEqual(scan(head + "all quiet\n", f"--from={len(head)}")[0], 0)
        self.assertEqual(scan(head + "ERROR: after\n", f"--from={len(head)}")[0], 1)

    def test_missing_log_fails(self):
        r = subprocess.run([sys.executable, "-I", str(SCAN), "/nonexistent/godot.log"], capture_output=True, text=True)
        self.assertEqual(r.returncode, 1)

    LEAK = ("ERROR: Condition \"p_elem->_root != this\" is true.\n   at: remove (./core/templates/self_list.h:80)\n"
            "ERROR: 12 RID allocations of type 'X' were leaked at exit.\n"
            "WARNING: ObjectDB instances leaked at exit (run with --verbose for details).\n"
            "ERROR: 76 resources still in use at exit (run with --verbose for details).\n")

    def test_engine_shutdown_leak_report_is_a_note_unless_strict(self):
        code, out = scan(self.LEAK)
        self.assertEqual(code, 0)
        self.assertIn("NOTE", out)
        self.assertEqual(scan(self.LEAK, "--strict-exit")[0], 1)

    def test_a_real_error_next_to_the_leak_report_still_fails(self):
        self.assertEqual(scan(self.LEAK + "ERROR: something real\n")[0], 1)


FAKE_GODOT = r"""#!/usr/bin/env bash
# Stands in for Godot: writes the engine log and runner report that $FAKE_SCENARIO describes; started on the
# lint scene it prints the lint protocol with (FAKE_LINT=dirty) or without a warning instead.
for a in "$@"; do
  if [ "$a" = "res://tools/lint_scripts.tscn" ]; then
    echo "LINT-PASS2"; echo "LINT> res://scenes/x.gd"
    [ "$FAKE_LINT" = "dirty" ] && echo "ERROR: 'The local variable \"a\" is declared but never used in the block.'"
    echo "LINT-DONE 1"; exit 0
  fi
done
log=""; out=""; costs=""; selection=""
while [ $# -gt 0 ]; do
  case "$1" in
    --log-file) log="$2"; shift ;;
    --out=*) out="${1#--out=}" ;;
    --shard=*) shard="${1#--shard=}" ;;
    --costs=*) costs="${1#--costs=}" ;;
    --id=*|--domain=*|--skip-domain=*) selection="$selection $1" ;;
  esac
  shift
done
head='Godot Engine v4.4'
judged='ERROR: a test provoked this (the runner already failed that test)'
echo "$head" > "$log"
# A report of one passing test; `empty` one of no test at all (a selection that matched nothing).
report() { printf '{"results": [{"id": "a/x", "status": "PASS"}], "stray_logs": [], "log_end": %s}' "$(wc -c < "$log" | tr -d ' ')" > "$out/report.json"; }
empty() { printf '{"results": [], "stray_logs": [], "log_end": %s}' "$(wc -c < "$log" | tr -d ' ')" > "$out/report.json"; }
# A report of one passing case of a native suite (`<suite id>::<case>`).
native() { printf '{"results": [{"id": "a/n_suite::test_x", "status": "PASS"}], "stray_logs": [], "log_end": %s}' "$(wc -c < "$log" | tr -d ' ')" > "$out/report.json"; }
timed() {
  printf '{"results": [{"id": "a/x", "status": "PASS", "wall_ms": 120}, {"id": "a/z", "status": "PASS", "wall_ms": 80}, {"id": "a/s", "status": "SKIPPED", "wall_ms": 5}], "stray_logs": [], "log_end": %s}' \
    "$(wc -c < "$log" | tr -d ' ')" > "$out/report.json"
  echo "Slowest: a/x 120 ms, a/z 80 ms"
}
[ -n "$costs" ] && echo "costs-arg $costs"
[ -n "$selection" ] && echo "selection:$selection"
echo "0 passed, 0 failed, 0 timed out, 0 skipped, 0 gap"
case "$FAKE_SCENARIO" in
  clean) report ;;
  empty) empty ;;
  native) native ;;
  shard1_empty) if [ "$shard" = "1/2" ]; then empty; else report; fi ;;
  timed) timed ;;
  judged_error) echo "$judged" >> "$log"; report ;;
  shutdown_error) report; echo "ERROR: engine complained while quitting" >> "$log" ;;
  shutdown_warning) report; echo "WARNING: engine muttered while quitting" >> "$log" ;;
  shutdown_leak) report; printf 'WARNING: ObjectDB instances leaked at exit\nERROR: 3 resources still in use at exit\n' >> "$log" ;;
  no_report) echo "SCRIPT ERROR: Parse Error: broken script" >> "$log" ;;
  no_report_clean) ;;
  listing_error) echo "ERROR: while listing" >> "$log" ;;
  listing_clean) ;;
  shard1_error) report; [ "$shard" = "1/2" ] && echo "ERROR: only shard 1" >> "$log" ;;
esac
exit 0
"""


class WrapperTests(unittest.TestCase):
    """tools/run_tests.sh around a fake Godot: how a run can end, and whether the wrapper fails it."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp(prefix="log_gate_"))
        cls.fake = cls.tmp / "fakegodot"
        cls.fake.write_text(FAKE_GODOT)
        cls.fake.chmod(cls.fake.stat().st_mode | stat.S_IEXEC)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def run_wrapper(self, scenario, *args, lint=None, state=None):
        """`lint` = None skips the lint (these tests are about the log gate); "clean" / "dirty" runs it on the fake.
        A lint run keeps its state (the fingerprint of the last clean lint) in `state`, a fresh directory unless the
        caller passes one, so one test's clean lint never makes the next test skip its lint."""
        if lint and state is None:
            state = Path(tempfile.mkdtemp(dir=self.tmp))
        env = dict(os.environ, GODOT=str(self.fake), FAKE_SCENARIO=scenario, FAKE_LINT=lint or "",
                   TMPDIR=str(state or self.tmp))
        flags = list(args) + ([] if lint else ["--no-lint"])
        r = subprocess.run(["bash", str(RUN), *flags], cwd=ROOT, env=env, capture_output=True, text=True)
        return r.returncode, r.stdout + r.stderr

    def test_clean_run_passes(self):
        self.assertEqual(self.run_wrapper("clean")[0], 0)

    def test_error_the_runner_already_judged_does_not_fail_twice(self):
        self.assertEqual(self.run_wrapper("judged_error")[0], 0)

    def test_error_logged_while_the_engine_shuts_down_fails(self):
        code, out = self.run_wrapper("shutdown_error")
        self.assertEqual(code, 1)
        self.assertIn("Logged outside any test", out)
        self.assertIn("engine complained while quitting", out)

    def test_warning_logged_while_the_engine_shuts_down_fails(self):
        self.assertEqual(self.run_wrapper("shutdown_warning")[0], 1)

    def test_engine_leak_report_is_a_note_and_strict_exit_fails_it(self):
        code, out = self.run_wrapper("shutdown_leak")
        self.assertEqual(code, 0)
        self.assertIn("NOTE", out)
        self.assertEqual(self.run_wrapper("shutdown_leak", "--strict-exit")[0], 1)

    def test_run_that_wrote_no_report_fails_and_shows_why(self):
        code, out = self.run_wrapper("no_report")
        self.assertEqual(code, 1)
        self.assertIn("wrote no report", out)
        self.assertIn("broken script", out)
        self.assertEqual(self.run_wrapper("no_report_clean")[0], 1)

    def test_list_run_is_scanned_from_the_start(self):
        self.assertEqual(self.run_wrapper("listing_error", "--list")[0], 1)
        self.assertEqual(self.run_wrapper("listing_clean", "--list")[0], 0)

    def test_a_lint_warning_fails_the_run_before_any_test_starts(self):
        code, out = self.run_wrapper("clean", lint="dirty")
        self.assertEqual(code, 1)
        self.assertIn("declared but never used", out)
        self.assertIn("no tests were run", out)
        self.assertNotIn("passed,", out)

    def test_a_clean_lint_lets_the_tests_run(self):
        code, out = self.run_wrapper("clean", lint="clean")
        self.assertEqual(code, 0)
        self.assertIn("passed,", out)

    def test_no_lint_flag_and_listing_skip_the_lint(self):
        self.assertEqual(self.run_wrapper("clean", "--no-lint", lint="dirty")[0], 0)
        self.assertEqual(self.run_wrapper("listing_clean", "--list", lint="dirty")[0], 0)

    def test_play_is_refused_with_the_command_that_launches_the_runner(self):
        code, out = self.run_wrapper("clean", "--play", "some", "sandbox")
        self.assertEqual(code, 2)
        self.assertIn("test_runner.tscn -- --play <words>", out)
        self.assertNotIn("passed,", out)

    def test_an_unknown_flag_is_refused_with_the_usage(self):
        # A mistyped flag, and two flags quoted into one argument (zsh does not split "$sel"), would otherwise reach
        # the batch, which drops them, and run the whole suite in place of the narrow run asked for.
        for arg in ("--domian=ai", "--self-test --id=_harness/nope"):
            code, out = self.run_wrapper("clean", arg)
            self.assertEqual(code, 2, out)
            self.assertIn(f"unknown flag: {arg}", out)
            self.assertIn("Selecting tests", out, "the usage lines of the header follow")
            self.assertNotIn("passed,", out)

    def test_a_selection_that_holds_no_test_fails_but_an_empty_shard_does_not(self):
        code, out = self.run_wrapper("empty", "--id=a/nope")
        self.assertEqual(code, 1, out)
        self.assertIn("no test matched", out)
        self.assertIn("--id=a/nope", out, "the message names the selection it was given")
        code, out = self.run_wrapper("shard1_empty", "--jobs=2")
        self.assertEqual(code, 0, out)
        self.assertNotIn("no test matched", out)

    def test_failed_after_a_clean_run_has_nothing_to_rerun(self):
        state = Path(tempfile.mkdtemp(dir=self.tmp))
        code, out = self.run_wrapper("failed", "--failed", state=state)
        self.assertEqual(code, 2, "no previous run of this checkout: " + out)
        self.assertEqual(self.run_wrapper("clean", state=state)[0], 0)
        code, out = self.run_wrapper("clean", "--failed", state=state)
        self.assertEqual(code, 0, out)
        self.assertIn("no failed test in the last report: nothing to rerun", out)
        self.assertNotIn("passed,", out, "nothing is run")

    def test_failed_over_an_unreadable_last_report_is_refused_not_passed(self):
        state = Path(tempfile.mkdtemp(dir=self.tmp))
        self.assertEqual(self.run_wrapper("clean", state=state)[0], 0)
        (last,) = state.glob("example_godot_last_report_*.json")
        last.write_text("{ not json")
        code, out = self.run_wrapper("clean", "--failed", state=state)
        self.assertEqual(code, 2, out)
        self.assertIn("cannot read the last report", out)
        self.assertIn(str(last), out, "it names the file")
        self.assertNotIn("nothing to rerun", out)

    def test_an_explicit_shard_runs_native_suites_once_and_says_so(self):
        # The native reruns of --repeat are the wrapper's own processes, which a --shard given by hand never gets.
        code, out = self.run_wrapper("native", "--repeat=3", "--shard=0/1")
        self.assertEqual(code, 0, out)
        self.assertIn("NOTE native suites ran once (--shard)", out)
        for scenario, args in (("native", ["--repeat=3"]), ("native", ["--shard=0/1"]),
                               ("clean", ["--repeat=3", "--shard=0/1"])):
            with self.subTest(scenario=scenario, args=args):
                code, out = self.run_wrapper(scenario, *args)
                self.assertEqual(code, 0, out)
                self.assertNotIn("native suites ran once", out)

    def test_one_failing_shard_fails_the_whole_run(self):
        self.assertEqual(self.run_wrapper("shard1_error", "--jobs=2")[0], 1)
        self.assertEqual(self.run_wrapper("clean", "--jobs=2")[0], 0)

    def test_measured_times_are_kept_and_the_next_sharded_run_balances_by_them(self):
        state = Path(tempfile.mkdtemp(dir=self.tmp))
        code, out = self.run_wrapper("timed", "--jobs=2", state=state)
        self.assertEqual(code, 0)
        self.assertNotIn("costs-arg", out)  # nothing was measured yet
        costs = json.loads(next(state.glob("example_godot_costs_*.json")).read_text())
        self.assertEqual(costs, {"a/x": 120, "a/z": 80})  # the skipped test says nothing about how long a test takes
        code, out = self.run_wrapper("timed", "--jobs=2", state=state)
        self.assertEqual(out.count("costs-arg"), 2)  # every shard gets the same file
        self.assertIn(str(next(state.glob("example_godot_costs_*.json"))), out)

    def test_a_sharded_run_prints_one_combined_slowest_list(self):
        out = self.run_wrapper("timed", "--jobs=2")[1]
        self.assertEqual(out.count("Slowest:"), 1)
        self.assertIn("Slowest: a/x 120 ms, a/z 80 ms", out)
        self.assertNotIn("Slowest:", self.run_wrapper("timed", "--jobs=2", "--summary")[1])

    @staticmethod
    def shards(out):
        """How many processes a run was split over: the wrapper's combined total says so, a single process says nothing."""
        m = re.search(r"\((\d+) shards\)", out)
        return int(m.group(1)) if m else 1

    def test_the_jobs_default_is_every_core_for_the_whole_suite_and_one_for_a_selection(self):
        self.assertGreater(self.shards(self.run_wrapper("clean")[1]), 1)
        self.assertEqual(self.shards(self.run_wrapper("clean", "--id=a/x")[1]), 1)
        self.assertEqual(self.shards(self.run_wrapper("clean", "--domain=ai")[1]), 1)
        self.assertEqual(self.shards(self.run_wrapper("clean", "pistol")[1]), 1)
        self.assertEqual(self.shards(self.run_wrapper("clean", "--jobs=3", "--id=a/x,b/y")[1]), 2)  # never more than the ids

    def changed(self, files, scenario="clean", *extra):
        """What `--changed` runs when git reports exactly `files` as changed: the selection lines the fake prints, and
        the wrapper's own `== ` headers and `No …` lines."""
        env = dict(os.environ, GODOT=str(self.fake), FAKE_SCENARIO=scenario, TMPDIR=str(self.tmp),
                   GAME_TEST_CHANGED_FILES="\n".join(files))
        r = subprocess.run(["bash", str(RUN), "--changed", "--no-lint", "--jobs=1", *extra], cwd=ROOT, env=env, capture_output=True, text=True)
        return r.returncode, [ln for ln in (r.stdout + r.stderr).splitlines() if ln.startswith(("selection:", "== ", "No "))]

    def test_changed_runs_only_an_edited_test_not_the_domains_that_compose_its_code(self):
        code, lines = self.changed(["tests/projectile/pistol_shot_wounds_test.gd"])
        self.assertEqual(code, 0)
        self.assertEqual([l for l in lines if l.startswith("selection:")], ["selection: --id=projectile/pistol_shot_wounds"])

    def test_changed_maps_scene_edits_to_the_domains_that_compose_them_and_helpers_to_their_users(self):
        _, lines = self.changed(["scenes/ai/behavior/behavior.gd"])
        self.assertEqual([l for l in lines if l.startswith("selection:")], ["selection: --domain=ai,perf"])
        _, lines = self.changed(["tests/_ai/flank_probe.gd"])
        self.assertEqual([l for l in lines if l.startswith("selection:")], ["selection: --domain=ai"])
        _, lines = self.changed(["tests/_perf/perf_probe.gd"])
        self.assertEqual([l for l in lines if l.startswith("selection:")], ["selection: --domain=perf"])

    def test_changed_runs_the_domain_of_an_edited_gdunit_suite(self):
        # A native suite holds several cases, none of them a catalog id: its whole domain runs, the suite with it.
        _, lines = self.changed(["tests/general/weighted_pick_suite.gd"])
        self.assertEqual([l for l in lines if l.startswith("selection:")], ["selection: --domain=general"])

    def test_skip_domain_reaches_the_runner_and_stops_the_perf_helper_run(self):
        _, lines = self.changed(["scenes/ai/behavior/behavior.gd"], "clean", "--skip-domain=perf")
        self.assertEqual([l for l in lines if l.startswith("selection:")], ["selection: --domain=ai,perf --skip-domain=perf"])
        code, lines = self.changed(["tests/_perf/perf_probe.gd"], "clean", "--skip-domain=perf")
        self.assertEqual(code, 0)
        self.assertEqual([l for l in lines if l.startswith("selection:")], [])

    def test_repeated_skip_domain_flags_add_up_in_the_wrapper(self):
        code, lines = self.changed(["tests/_perf/perf_probe.gd"], "clean", "--skip-domain=perf", "--skip-domain=ai")
        self.assertEqual(code, 0)
        self.assertEqual([l for l in lines if l.startswith("selection:")], [], "perf is skipped by the first flag")

    def test_repeated_id_flags_count_together_against_the_jobs(self):
        self.assertEqual(self.shards(self.run_wrapper("clean", "--jobs=3", "--id=a/x", "--id=b/y")[1]), 2)

    def test_changed_with_nothing_mapped_or_only_skipped_still_passes_and_says_which(self):
        cases = ((["docs/hearing.md"], "No changed file maps to any tests (affected: none)."),
                 # A perf test or suite under the hook's --skip-domain=perf: mapped, then left out.
                 (["tests/perf/match_5v5_stress_test.gd"], "No test to run: the changed files map only to skipped domains (perf)."),
                 (["tests/perf/perf_suite.gd"], "No test to run: the changed files map only to skipped domains (perf)."))
        for files, says in cases:
            with self.subTest(files=files):
                code, lines = self.changed(files, "empty", "--skip-domain=perf")
                self.assertEqual(code, 0, lines)
                self.assertEqual([l for l in lines if l.startswith("selection:")], [])
                self.assertTrue(any(says in l for l in lines), lines)

    def test_changed_does_not_repeat_a_test_whose_domain_already_runs(self):
        _, lines = self.changed(["scenes/ai/behavior/behavior.gd", "tests/ai/decision/goal_names_the_gun_test.gd",
                                 "tests/audio/bank_test.gd", "tests/audio/bank_test.gd.uid"])
        self.assertEqual([l for l in lines if l.startswith("selection:")],
                         ["selection: --domain=ai,perf", "selection: --id=audio/bank"])


FAKE_LINT = r"""#!/usr/bin/env bash
# Stands in for tools/lint.sh: a warning and exit 1 with FAKE_LINT=dirty, clean otherwise.
if [ "$FAKE_LINT" = "dirty" ]; then
  echo "ERROR: 'The local variable \"a\" is declared but never used in the block.'"
  exit 1
fi
exit 0
"""


class LintFingerprintTests(unittest.TestCase):
    """The clean-lint fingerprint (HEAD plus every uncommitted change) through git: a throwaway repo holding a copy of
    run_tests.sh (with scan_godot_log.py) and a fake lint, so the untracked file that changes the fingerprint is
    written there, not in this checkout."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="lint_fingerprint_"))
        self.repo = self.tmp / "repo"
        self.state = self.tmp / "state"
        self.state.mkdir()
        tools = self.repo / "tools"
        tools.mkdir(parents=True)
        for name in ("run_tests.sh", "scan_godot_log.py"):
            shutil.copy2(ROOT / "tools" / name, tools / name)
        (tools / "lint.sh").write_text(FAKE_LINT)
        (tools / "lint.sh").chmod(0o755)
        self.fake = self.tmp / "fakegodot"
        self.fake.write_text(FAKE_GODOT)
        self.fake.chmod(0o755)
        for rel, text in {".gitignore": ".godot/\n", ".godot/global_script_class_cache.cfg": "",
                          "scenes/a.gd": "extends Node\n"}.items():
            (self.repo / rel).parent.mkdir(parents=True, exist_ok=True)
            (self.repo / rel).write_text(text)
        env = StagedChangedTests.env()
        for args in (["init", "-q"], ["add", "-A"],
                     ["-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "base"]):
            subprocess.run(["git", *args], cwd=self.repo, env=env, check=True, capture_output=True)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_wrapper(self, lint):
        r = subprocess.run(["bash", str(self.repo / "tools" / "run_tests.sh"), "--jobs=1"], cwd=self.repo,
                           capture_output=True, text=True, timeout=120,
                           env=StagedChangedTests.env(GODOT=str(self.fake), FAKE_SCENARIO="clean", FAKE_LINT=lint,
                                                      TMPDIR=str(self.state)))
        return r.returncode, r.stdout + r.stderr

    def test_a_clean_lint_is_not_repeated_on_an_unchanged_tree_but_any_change_runs_it_again(self):
        self.assertEqual(self.run_wrapper("clean")[0], 0)
        # Same sources: the lint is skipped, so a lint that would now fail does not stop the run.
        code, out = self.run_wrapper("dirty")
        self.assertEqual(code, 0, out)
        self.assertIn("lint skipped", out)
        # A new untracked file changes the fingerprint: the lint runs again and fails.
        probe = self.repo / "zz_lint_skip_probe.tmp"
        probe.write_text("changed")
        code, out = self.run_wrapper("dirty")
        self.assertEqual(code, 1, out)
        self.assertIn("no tests were run", out)
        # The failed lint recorded nothing, and with the probe gone the tree is the one the clean lint saw: skipped again.
        probe.unlink()
        self.assertEqual(self.run_wrapper("dirty")[0], 0)


FAKE_STAGED_LINT = r"""#!/usr/bin/env bash
# Stands in for tools/lint.sh: logs its arguments; with FAKE_LINT_FOREIGN=<path> reports a finding in that script.
echo "lint $*" >> "$LINT_LOG"
if [ -n "${FAKE_LINT_FOREIGN:-}" ]; then
  echo "== GDScript analyzer (engine) =="
  echo "res://$FAKE_LINT_FOREIGN  (1)"
  exit 1
fi
exit 0
"""


class StagedChangedTests(unittest.TestCase):
    """`--changed --staged` through git: a throwaway repo holding a copy of run_tests.sh (with scan_godot_log.py,
    lint_staged.sh and lint_label.py) and a fake lint, with one scene edit staged, one left unstaged and one untracked
    script. It maps only the staged file, lints only the staged script (labelling a finding elsewhere `not in this commit`), and never
    records the whole-tree clean-lint fingerprint."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="staged_changed_"))
        self.repo = self.tmp / "repo"
        self.state = self.tmp / "state"
        self.state.mkdir()
        tools = self.repo / "tools"
        tools.mkdir(parents=True)
        for name in ("run_tests.sh", "scan_godot_log.py", "lint_staged.sh", "lint_label.py"):
            shutil.copy2(ROOT / "tools" / name, tools / name)
        (tools / "lint.sh").write_text(FAKE_STAGED_LINT)
        (tools / "lint.sh").chmod(0o755)
        self.fake = self.tmp / "fakegodot"
        self.fake.write_text(FAKE_GODOT)
        self.fake.chmod(0o755)
        files = {".gitignore": ".godot/\n", ".godot/global_script_class_cache.cfg": "", "tests/ai/x_test.gd": "",
                 "tests/ui/y_test.gd": "", "tests/physics/z_test.gd": "", "scenes/ai/a.gd": "extends Node\n",
                 "scenes/ui/u.gd": "extends Node\n", "scenes/ui/u.tscn": "[gd_scene]\n"}
        for rel, text in files.items():
            (self.repo / rel).parent.mkdir(parents=True, exist_ok=True)
            (self.repo / rel).write_text(text)
        self.git("init", "-q")
        self.git("add", "-A")
        self.git("-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "base")
        with open(self.repo / "scenes/ai/a.gd", "a") as f:
            f.write("# staged\n")
        self.git("add", "scenes/ai/a.gd")
        with open(self.repo / "scenes/ui/u.gd", "a") as f:
            f.write("# not staged\n")
        (self.repo / "scenes/physics").mkdir()
        (self.repo / "scenes/physics/p.gd").write_text("extends Node\n")  # untracked

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    @staticmethod
    def env(**extra):
        """Without git's GIT_* variables (a run from inside a hook would act on this checkout)."""
        env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_") and k != "GAME_TEST_CHANGED_FILES"}
        env.update(extra)
        return env

    def git(self, *args):
        subprocess.run(["git", *args], cwd=self.repo, env=self.env(), check=True, capture_output=True)

    def run_changed(self, *args, **env):
        lint_log = self.tmp / "lint.log"
        lint_log.write_text("")
        r = subprocess.run(["bash", str(self.repo / "tools" / "run_tests.sh"), "--changed", "--jobs=1", *args],
                           cwd=self.repo, capture_output=True, text=True, timeout=120,
                           env=self.env(GODOT=str(self.fake), FAKE_SCENARIO="clean", TMPDIR=str(self.state),
                                        LINT_LOG=str(lint_log), **env))
        out = r.stdout + r.stderr
        return r.returncode, out, [ln for ln in out.splitlines() if ln.startswith("selection:")], lint_log.read_text()

    def test_it_maps_only_the_staged_files(self):
        code, out, selection, _ = self.run_changed("--staged")
        self.assertEqual(code, 0, out)
        self.assertEqual(selection, ["selection: --domain=ai"], "not ui (unstaged) nor physics (untracked)\n" + out)
        code, out, selection, _ = self.run_changed()
        self.assertNotEqual(selection, ["selection: --domain=ai"], "without --staged the working tree counts\n" + out)

    def test_its_lint_covers_only_the_staged_scripts_and_records_no_clean_lint(self):
        code, out, _, lint = self.run_changed("--staged")
        self.assertEqual(code, 0, out)
        self.assertEqual(lint.splitlines(), ["lint scenes/ai/a.gd"], out)
        self.assertEqual(list(self.state.glob("example_godot_lint_ok_*")), [], "a scoped lint is no whole-tree lint")

    def test_a_staged_scene_alone_leaves_the_lint_nothing_to_check(self):
        self.git("reset", "-q", "scenes/ai/a.gd")
        with open(self.repo / "scenes/ui/u.tscn", "a") as f:
            f.write("; staged\n")
        self.git("add", "scenes/ui/u.tscn")
        code, out, selection, lint = self.run_changed("--staged")
        self.assertEqual(code, 0, out)
        self.assertEqual(selection, ["selection: --domain=ui"], out)
        self.assertEqual(lint, "", "no staged script: no lint\n" + out)

    def test_a_lint_finding_in_a_script_not_staged_is_labelled(self):
        code, out, _, _ = self.run_changed("--staged", FAKE_LINT_FOREIGN="scenes/ui/u.gd")
        self.assertEqual(code, 1, out)
        self.assertIn("not in this commit: scenes/ui/u.gd", out)


class LintReportTests(unittest.TestCase):
    """tools/lint_report.py on crafted logs of the lint scene."""

    def report(self, text, *flags):
        with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False) as f:
            f.write(text)
        try:
            env = {k: v for k, v in os.environ.items() if k != "GODOT"}  # no engine: lines stay candidates
            r = subprocess.run([sys.executable, "-I", str(ROOT / "tools" / "lint_report.py"), f.name, *flags],
                               capture_output=True, text=True, env=env)
        finally:
            os.unlink(f.name)
        return r.returncode, r.stdout

    CLEAN = "Godot Engine\nLINT-PASS2\nLINT> res://a.gd\nLINT> res://b.gd\nLINT-DONE 2\nERROR: leaked at exit\n"

    def test_clean_run_passes_and_ignores_what_the_engine_prints_at_exit(self):
        self.assertEqual(self.report(self.CLEAN)[0], 0)

    def test_quiet_prints_nothing_when_clean(self):
        self.assertEqual(self.report(self.CLEAN, "--quiet"), (0, ""))

    def test_a_warning_is_attributed_to_the_script_printed_before_it(self):
        code, out = self.report("LINT-PASS2\nLINT> res://a.gd\nLINT> res://b.gd\n\x1b[1;31mERROR: 'Integer division, decimal part will be discarded.'\nLINT-DONE 2\n")
        self.assertEqual(code, 1)
        self.assertIn("res://b.gd  (1)", out)
        self.assertNotIn("res://a.gd", out)

    def test_a_parse_error_fails(self):
        code, out = self.report("LINT-PASS2\nLINT> res://a.gd\nSCRIPT ERROR: Parse Error: broken\nLINT-DONE 1\n")
        self.assertEqual(code, 1)
        self.assertIn("broken", out)

    def test_a_lint_that_never_finished_fails(self):
        self.assertEqual(self.report("LINT-PASS2\nLINT> res://a.gd\n")[0], 1)


@unittest.skipUnless(godot_binary(), "no Godot binary (set GODOT=/path/to/Godot)")
class LintEngineTests(unittest.TestCase):
    """The real engine: the project lints clean, and a script with warnings is caught with its exact lines (written
    into a copy of the checkout, so no other run in this worktree sees it)."""

    PROBE = "tests/_harness/zz_lint_probe.gd"

    def lint(self, *args, root=ROOT):
        env = dict(os.environ, GODOT=godot_binary())
        r = subprocess.run(["bash", str(root / "tools" / "lint.sh"), *args], cwd=root, env=env, capture_output=True, text=True, timeout=300)
        return r.returncode, r.stdout + r.stderr

    def test_the_project_is_clean(self):
        code, out = self.lint()
        self.assertEqual(code, 0, out)

    def test_warnings_are_found_per_file_with_the_division_pinpointed(self):
        with tempfile.TemporaryDirectory(prefix="lint_probe_") as tmp:
            copy = copy_checkout(Path(tmp))
            (copy / self.PROBE).write_text("extends RefCounted\n\n\nfunc f(wrap: bool) -> int:\n\tvar unused := 1\n\treturn 5 / 2\n")
            code, out = self.lint(self.PROBE, root=copy)
        self.assertEqual(code, 1, out)
        self.assertIn("res://tests/_harness/zz_lint_probe.gd  (4)", out)
        self.assertIn("declared but never used", out)
        self.assertIn("same name as a built-in function", out)
        self.assertIn("[line:col 6:11]", out)


@unittest.skipUnless(godot_binary(), "no Godot binary (set GODOT=/path/to/Godot)")
class GdStyleLintTests(unittest.TestCase):
    """tools/lint.sh runs gdstyle (v0.4.0, fetched by tools/gdstyle.sh): a script `gdstyle fmt --check` would change
    fails it, and so does a line over 100 columns the formatter leaves alone; a formatted script passes.

    gdstyle's quality/* rules (issue #76) are each in exactly one of three tables, read against gdstyle.toml: a rule
    on has a probe that breaks it alone, which tools/lint.sh fails naming the rule; a rule off by decision (its reason
    beside it in gdstyle.toml) has a probe that breaks it, which tools/lint.sh passes; a rule not yet on turns on in a
    later stage of #76, which moves it into QUALITY_ON with its probe."""

    CLEAN = "extends RefCounted\n\n\nfunc total() -> int:\n\tvar a := 1 + 2\n\treturn a\n"
    UNFORMATTED = "extends RefCounted\n\n\nfunc total()->int:\n\tvar a:=1+2\n\treturn a\n"  # no spaces round '+'
    LONG_LINE = "extends RefCounted\n\nconst MESSAGE := \"%s\"\n" % ("a long line only a person can shorten, never the formatter, " * 2)

    QUALITY_ON = {
        "quality/unnecessary-pass": "extends RefCounted\n\n\nfunc f(a: Array) -> void:\n\ta.clear()\n\tpass\n",
        "quality/self-comparison": "extends RefCounted\n\n\nfunc f(a: int) -> bool:\n\treturn a == a\n",
        # A key only known at run time: the same literal key twice is the engine's own parse error.
        "quality/duplicate-dict-key": "extends RefCounted\n\n\nfunc f(key: String) -> Dictionary:\n\treturn { key: 1, key: 2 }\n",
        "quality/duplicated-load": "extends RefCounted\n\n\nfunc f() -> Array:\n"
                                   "\treturn [load(\"res://tools/lint_scripts.gd\"), load(\"res://tools/lint_scripts.gd\")]\n",
        "quality/max-inner-classes": "extends RefCounted\n" + "".join(f"\n\nclass {c}:\n\tvar a := 0\n" for c in "ABCDEF"),
        "quality/no-self-assign": "extends RefCounted\n\nvar count := 0\n\n\nfunc f() -> void:\n\tcount = count\n",
        # After a `break`: the engine's own analyzer warns of a statement after a `return`.
        "quality/unreachable-code": "extends RefCounted\n\n\nfunc f(a: Array) -> int:\n\tfor x: int in a:\n\t\tif x > 0:\n"
                                    "\t\t\tbreak\n\t\t\treturn x\n\treturn 0\n",
        "quality/no-else-return": "extends RefCounted\n\n\nfunc f(a: bool) -> int:\n\tif a:\n\t\treturn 1\n\telse:\n\t\treturn 2\n",
        # The function-level rules, each one past gdstyle's default: 50 lines (header included), 5 parameters, 10
        # locals, nesting 4, 8 branches, 6 returns.
        "quality/max-function-length": "extends RefCounted\n\n\nfunc f() -> int:\n\tvar total := 0\n" + "\ttotal += 1\n" * 50
                                       + "\treturn total\n",
        "quality/max-parameters": "extends RefCounted\n\n\nfunc f(a: int, b: int, c: int, d: int, e: int, g: int) -> int:\n"
                                  "\treturn a + b + c + d + e + g\n",
        "quality/type-hint": "extends RefCounted\n\n\nfunc f(a) -> int:\n\treturn a + 1\n",
        "quality/max-nesting-depth": "extends RefCounted\n\n\nfunc f(a: int) -> int:\n"
                                     + "".join("\t" * (i + 1) + f"if a > {i}:\n" for i in range(5)) + "\t" * 6 + "return 1\n"
                                     + "\treturn 0\n",
        "quality/max-returns": "extends RefCounted\n\n\nfunc f(a: int) -> int:\n"
                               + "".join(f"\tif a == {i}:\n\t\treturn {i}\n" for i in range(6)) + "\treturn -1\n",
        "quality/max-branches": "extends RefCounted\n\n\nfunc f(a: int) -> int:\n\tvar total := 0\n"
                                + "".join(f"\tif a > {i}:\n\t\ttotal += {i}\n" for i in range(9)) + "\treturn total\n",
        "quality/max-local-variables": "extends RefCounted\n\n\nfunc f() -> int:\n\tvar v0 := 1\n"
                                       + "".join(f"\tvar v{i} := v{i - 1} + 1\n" for i in range(1, 11)) + "\treturn v10\n",
    }
    QUALITY_OFF_BY_DECISION = {
        "quality/no-debug-print": "extends RefCounted\n\n\nfunc f() -> void:\n\tprint(\"x\")\n",
        "quality/await-in-loop": "extends Node\n\n\nfunc f() -> void:\n\tfor i in 3:\n\t\tawait get_tree().process_frame\n",
        "quality/empty-function": "extends RefCounted\n\n\nfunc f() -> void:\n\tpass\n",
        "quality/allocation-in-loop": "extends Node\n\n\nfunc f() -> void:\n\tfor i in 3:\n\t\tadd_child(Node.new())\n",
        # No node in it: gdstyle reads a % format with a call after it as a %UniqueNode lookup.
        "quality/process-get-node": "extends Node\n\n\nfunc _process(delta: float) -> void:\n\tset_meta(\"t\", \"%d\" % ceili(delta))\n",
    }
    QUALITY_NOT_YET = ("quality/max-file-length", "quality/max-class-variables", "quality/max-public-methods")
    FINDING = re.compile(r"^\s+(\S+\.gd):\d+:\d+: .* \[([\w/-]+)\]$", re.M)  # a `gdstyle check` line of lint.sh

    @classmethod
    def setUpClass(cls):
        # The probes go in a copy of the checkout, so no other run in this worktree sees them.
        cls.tmp = Path(tempfile.mkdtemp(prefix="gdstyle_probe_"))
        cls.copy = copy_checkout(cls.tmp)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def write_probe(self, name, text):
        probe = f"tests/_harness/zz_style_{name}_probe.gd"
        (self.copy / probe).write_text(text)
        return probe

    def lint(self, *paths):
        env = dict(os.environ, GODOT=godot_binary())
        r = subprocess.run(["bash", str(self.copy / "tools" / "lint.sh"), *paths], cwd=self.copy, env=env,
                           capture_output=True, text=True, timeout=600)
        return r.returncode, r.stdout + r.stderr

    def lint_probe(self, name, text):
        return self.lint(self.write_probe(name, text))

    def quality_probe(self, rule):
        rules = {**self.QUALITY_ON, **self.QUALITY_OFF_BY_DECISION}
        return self.write_probe("quality_" + rule.removeprefix("quality/").replace("-", "_"), rules[rule])

    @staticmethod
    def quality_rules():
        with open(ROOT / "gdstyle.toml", "rb") as f:
            return {k: v for k, v in tomllib.load(f)["rules"].items() if k.startswith("quality/")}

    def set_every_quality_rule(self, level):
        """Every quality/* rule of the copy's gdstyle.toml at `level` until the test ends."""
        config = self.copy / "gdstyle.toml"
        text = config.read_text()
        self.addCleanup(config.write_text, text)
        config.write_text(re.sub(r'^("quality/[\w-]+") = "\w+"', rf'\1 = "{level}"', text, flags=re.M))

    def test_the_probes_are_what_they_claim(self):
        self.assertTrue(all(len(line) <= 100 for line in self.CLEAN.splitlines() + self.UNFORMATTED.splitlines()))
        self.assertGreater(max(len(line) for line in self.LONG_LINE.splitlines()), 100)

    def test_a_formatted_script_passes(self):
        code, out = self.lint_probe("clean", self.CLEAN)
        self.assertEqual(code, 0, out)

    def test_a_script_the_formatter_would_change_fails(self):
        code, out = self.lint_probe("unformatted", self.UNFORMATTED)
        self.assertEqual(code, 1, "gdstyle fmt --check would reformat it\n" + out)
        self.assertIn("zz_style_unformatted_probe.gd", out)

    def test_a_line_over_100_columns_fails(self):
        code, out = self.lint_probe("long_line", self.LONG_LINE)
        self.assertEqual(code, 1, "a 100-column limit\n" + out)
        self.assertIn("zz_style_long_line_probe.gd", out)
        self.assertIn("max-line-length", out)

    def test_every_quality_rule_is_in_exactly_one_table(self):
        rules = self.quality_rules()
        tables = [set(self.QUALITY_ON), set(self.QUALITY_OFF_BY_DECISION), set(self.QUALITY_NOT_YET)]
        self.assertEqual(sum(len(t) for t in tables), len(set().union(*tables)), "a rule in two tables")
        self.assertEqual(set().union(*tables), set(rules), "a quality/* rule of gdstyle.toml without a row, or a row for none")
        self.assertEqual(tables[0], {r for r, level in rules.items() if level == "error"}, "QUALITY_ON is the rules on")
        config = (ROOT / "gdstyle.toml").read_text()
        for rule in self.QUALITY_OFF_BY_DECISION:
            self.assertRegex(config, rf'(?m)^"{rule}" = "off" +# \S', f"{rule}: its reason beside it in gdstyle.toml")

    def test_the_quality_probes_are_what_they_claim(self):
        """Each quality probe is clean with every quality/* rule off, and with every one on breaks its own alone."""
        probes = {rule: self.quality_probe(rule) for rule in {**self.QUALITY_ON, **self.QUALITY_OFF_BY_DECISION}}
        self.set_every_quality_rule("off")
        code, out = self.lint(*probes.values())
        self.assertEqual(code, 0, "a probe breaks something besides its quality rule\n" + out)
        self.doCleanups()
        self.set_every_quality_rule("error")
        code, out = self.lint(*probes.values())
        found = {}
        for path, rule in self.FINDING.findall(out):
            found.setdefault(path, set()).add(rule)
        for rule, probe in probes.items():
            with self.subTest(rule):
                self.assertEqual(found.get(probe), {rule}, out)

    def test_a_quality_rule_on_fails_its_probe(self):
        for rule in self.QUALITY_ON:
            with self.subTest(rule):
                probe = self.quality_probe(rule)
                code, out = self.lint(probe)
                self.assertEqual(code, 1, out)
                self.assertIn(f"{probe}:", out)
                self.assertIn(f"[{rule}]", out)

    def test_a_quality_rule_off_by_decision_passes_its_probe(self):
        for rule in self.QUALITY_OFF_BY_DECISION:
            with self.subTest(rule):
                code, out = self.lint(self.quality_probe(rule))
                self.assertEqual(code, 0, out)


@unittest.skipUnless(godot_binary(), "no Godot binary (set GODOT=/path/to/Godot)")
class EngineTests(unittest.TestCase):
    """The real engine: an error or warning logged during a test must fail it, in batch and in the in-game runner."""

    PROBE = "_harness/log_gate_probe"

    def batch(self, probe, headed):
        env = dict(os.environ, GAME_TEST_PROBE=probe, GODOT=godot_binary())
        args = ["bash", str(RUN), "--self-test", f"--id={self.PROBE}", "--summary"] + (["--shots"] if headed else [])
        r = subprocess.run(args, cwd=ROOT, env=env, capture_output=True, text=True, timeout=300)
        return r.returncode, r.stdout + r.stderr

    def in_game(self, probe, headed):
        """The interactive runner (`-- --play`), which prints each verdict; it is stopped by --quit-after."""
        # No --log-file: a person runs the game with the default log (project setting debug/file_logging), which the
        # in-game runner follows; only a batch run started with --out is told where its log went.
        cmd = [godot_binary()] + ([] if headed else ["--headless"]) + [
            "--path", str(ROOT), "--fixed-fps", "60", "--quit-after", "420",
            "res://scenes/testing/test_runner.tscn", "--", "--play", "log", "gate", "probe"]
        r = subprocess.run(cmd, cwd=ROOT, env=dict(os.environ, GAME_TEST_PROBE=probe), capture_output=True, text=True, timeout=300)
        return r.stdout + "\n" + r.stderr

    def check_mode(self, headed):
        code, out = self.batch("", headed)
        self.assertEqual(code, 0, "no probe: the run passes\n" + out)
        for probe in ("error", "warning"):
            code, out = self.batch(probe, headed)
            self.assertEqual(code, 1, f"a logged {probe} fails the batch run\n" + out)
            self.assertIn(f"Logged {probe}: gate probe {probe}", out)
        out = self.in_game("", headed)
        self.assertRegex(out, r"PASS\s+_harness/log_gate_probe", "in-game, no probe: PASS\n" + out)
        for probe in ("error", "warning"):
            out = self.in_game(probe, headed)
            self.assertRegex(out, r"FAIL\s+_harness/log_gate_probe", f"in-game, a logged {probe} fails the test\n" + out)
            self.assertIn(f"Logged {probe}: gate probe {probe}", out)

    def test_headless(self):
        self.check_mode(False)

    @unittest.skipUnless(HEADED, "pass --headed to run the windowed engine")
    def test_headed(self):
        self.check_mode(True)


GDUNIT_TOOL = "res://addons/gdUnit4/bin/GdUnitCmdTool.gd"

FAKE_ARGV_GODOT = r"""#!/usr/bin/env bash
# Stands in for Godot: records its argv (one argument per line) in $FAKE_ARGV_DIR, one file per process, and its
# GODOT_CMD_PORT beside it (<pid>.port), and exits. Started on the lint scene it prints a clean lint.
for a in "$@"; do
  if [ "$a" = "res://tools/lint_scripts.tscn" ]; then echo "LINT-PASS2"; echo "LINT-DONE 0"; exit 0; fi
done
f="$FAKE_ARGV_DIR/$$.argv"
for a in "$@"; do printf '%s\n' "$a" >> "$f"; done
echo "${GODOT_CMD_PORT-<unset>}" > "$FAKE_ARGV_DIR/$$.port"
exit 0
"""


class GdUnitCommandLineTests(unittest.TestCase):
    """How tools/run_tests.sh starts the engine: gdUnit's command-line tool, headless at a fixed 60 fps, each process
    with its own engine log. A fake Godot records the arguments; what it then reports is not looked at here."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp(prefix="gdunit_cli_"))
        cls.fake = cls.tmp / "fakegodot"
        cls.fake.write_text(FAKE_ARGV_GODOT)
        cls.fake.chmod(cls.fake.stat().st_mode | stat.S_IEXEC)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def launches(self, *args, ports=None, **env_extra):
        """The argv of every engine process a run_tests.sh call started (the lint's aside); with `ports` a list, each
        one's GODOT_CMD_PORT is appended to it."""
        argv_dir = Path(tempfile.mkdtemp(dir=self.tmp))
        env = dict(os.environ, GODOT=str(self.fake), FAKE_ARGV_DIR=str(argv_dir), TMPDIR=str(argv_dir), **env_extra)
        subprocess.run(["bash", str(RUN), "--no-lint", *args], cwd=ROOT, env=env, capture_output=True, text=True, timeout=120)
        if ports is not None:
            ports += [f.with_suffix(".port").read_text().strip() for f in sorted(argv_dir.glob("*.argv"))]
        return [f.read_text().splitlines() for f in sorted(argv_dir.glob("*.argv"))]

    @staticmethod
    def value_after(argv, flag):
        return argv[argv.index(flag) + 1] if flag in argv and argv.index(flag) + 1 < len(argv) else None

    def gdunit_launches(self, *args):
        """The gdUnit processes of a run_tests.sh call, once every engine process it started is seen to have an engine
        log of its own and none to be today's batch runner."""
        runs = self.launches(*args)
        logs = [self.value_after(argv, "--log-file") for argv in runs]
        self.assertTrue(runs and all(logs), f"every engine process has an engine log of its own: {runs}")
        self.assertEqual(len(set(logs)), len(logs), f"no two processes share a log: {logs}")
        for argv in runs:
            self.assertNotIn("--run-tests", argv, f"the batch runner has given way to gdUnit: {argv}")
        tests = [argv for argv in runs if (self.value_after(argv, "-s") or self.value_after(argv, "--script")) == GDUNIT_TOOL]
        self.assertTrue(tests, f"no process runs gdUnit's command-line tool {GDUNIT_TOOL}: {runs}")
        return tests

    def assert_shape(self, argv, headless=True):
        self.assertEqual(self.value_after(argv, "--fixed-fps"), "60", f"at a fixed 60 fps: {argv}")
        self.assertEqual("--headless" in argv, headless, f"headless {headless}: {argv}")

    def test_a_run_drives_gdunits_command_line_tool_headless_at_a_fixed_60_fps(self):
        for argv in self.gdunit_launches("--id=a/x"):
            self.assert_shape(argv)

    def test_the_self_tests_go_through_gdunit_too(self):
        for argv in self.gdunit_launches("--self-test"):
            self.assert_shape(argv)

    def test_each_shard_is_a_gdunit_process_with_its_own_log(self):
        runs = self.gdunit_launches("--jobs=2", "--id=a/x,b/y")
        self.assertEqual(len(runs), 2, runs)
        for argv in runs:
            self.assert_shape(argv)

    def test_every_engine_process_runs_with_the_command_server_off_over_the_callers_port(self):
        for env in ({}, {"GODOT_CMD_PORT": "9123"}):
            for args in (["--id=a/x"], ["--jobs=2", "--id=a/x,b/y"], ["--list"]):
                with self.subTest(env=env, args=args):
                    ports = []
                    runs = self.launches(*args, ports=ports, **env)
                    self.assertTrue(runs, "the run started the engine")
                    self.assertEqual(ports, ["off"] * len(runs))

    def test_windowed_and_shots_runs_keep_a_window(self):
        for flag in ("--windowed", "--shots"):
            with self.subTest(flag=flag):
                for argv in self.gdunit_launches(flag, "--id=a/x"):
                    self.assert_shape(argv, headless=False)
                    if flag == "--windowed":
                        self.assertIn("--disable-vsync", argv)


RESULT_LINE = re.compile(r"^(PASS|FAIL|TIMEOUT|SKIPPED|GAP)\s+(\S+)\s+\((\d+\.\d)s sim, (\d+) ms\)(.*)$")
SUMMARY_LINE = re.compile(r"^(\d+) passed, (\d+) failed, (\d+) timed out, (\d+) skipped, (\d+) gap\b")


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class Run:
    """One tools/run_tests.sh call, read the way a person or an agent reads it."""

    def __init__(self, code, out, seconds):
        self.code, self.out, self.seconds = code, out, seconds
        self.results = {}  # id -> [(status, sim s, wall ms, tail)]
        self.summary = None
        self.report_path = None
        for line in out.splitlines():
            m = RESULT_LINE.match(line)
            if m:
                self.results.setdefault(m.group(2), []).append((m.group(1), float(m.group(3)), int(m.group(4)), m.group(5)))
            m = SUMMARY_LINE.match(line)
            if m:
                self.summary = tuple(int(g) for g in m.groups())
            if line.startswith("Report: "):
                self.report_path = Path(line[len("Report: "):].strip())

    def status(self, test_id):
        return [r[0] for r in self.results.get(test_id, [])]

    @property
    def out_dir(self):
        return self.report_path.parent if self.report_path else None

    def report(self):
        return json.loads(self.report_path.read_text())

    def junit(self):
        """test id -> (verdict child tag or "", its message + text): gdUnit's results.xml in the run's out dir."""
        files = sorted(self.out_dir.rglob("results.xml")) if self.out_dir else []
        if not files:
            return None
        cases = {}
        for f in files:
            for case in ET.parse(f).getroot().iter("testcase"):
                m = re.search(r"'([^']+)'\)$", case.get("name", ""))
                if not m:
                    continue
                verdict = next((c for c in case if c.tag in ("failure", "error", "skipped")), None)
                cases[m.group(1)] = ("", "") if verdict is None else \
                    (verdict.tag, (verdict.get("message") or "") + "\n" + (verdict.text or ""))
        return cases

    def bundles(self):
        return [Path(m) for m in re.findall(r"^\s+bundle: (\S+)$", self.out, re.M)]


@unittest.skipUnless(godot_binary(), "no Godot binary (set GODOT=/path/to/Godot)")
class GdUnitEngineTests(unittest.TestCase):
    """The real engine through gdUnit: the harness probes' verdicts as run_tests.sh prints them and as gdUnit's JUnit
    records them, the log gate ending a test at once, a requires_von test with no server, and the flags."""

    VERDICT = "_harness/verdict_probe"
    GAP = "_harness/gap_probe"
    HOLD = "_harness/warning_hold_probe"
    VON = "_harness/von_probe"
    PROBE_ENV = ("GAME_TEST_PROBE", "GAME_TEST_VERDICT", "GAME_TEST_GAP", "GAME_TEST_HOLD", "GAME_TEST_VON_PORT",
                 "GAME_TEST_FLAKY_COUNT")

    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp(prefix="gdunit_engine_"))

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def run_tests(self, *args, timeout=900, root=ROOT, **probe_env):
        """run_tests.sh of the checkout at `root` with `args`; its per-checkout state ($TMPDIR) kept apart from the
        person's."""
        env = {k: v for k, v in os.environ.items() if k not in self.PROBE_ENV}
        env.update(GODOT=godot_binary(), TMPDIR=str(Path(tempfile.mkdtemp(dir=self.tmp))), **probe_env)
        started = time.monotonic()
        r = subprocess.run(["bash", str(root / "tools" / "run_tests.sh"), *args], cwd=root, env=env,
                           capture_output=True, text=True, timeout=timeout)
        return Run(r.returncode, r.stdout + r.stderr, time.monotonic() - started)

    def probe(self, test_id, *flags, **probe_env):
        return self.run_tests("--self-test", f"--id={test_id}", *flags, **probe_env)

    def assert_junit(self, run, test_id, tag, *texts):
        junit = run.junit()
        self.assertIsNotNone(junit, f"no gdUnit results.xml under the run's out dir {run.out_dir}\n{run.out[-3000:]}")
        self.assertIn(test_id, junit, f"no JUnit case named by {test_id}: {sorted(junit)}")
        got_tag, text = junit[test_id]
        if tag == "failure":
            self.assertIn(got_tag, ("failure", "error"), f"{test_id} is a gdUnit failure in the JUnit, got {got_tag!r}")
        else:
            self.assertEqual(got_tag, tag, f"{test_id} in the JUnit")
        for t in texts:
            self.assertIn(t, text, f"the JUnit {got_tag} of {test_id}")

    def test_a_run_writes_gdunits_junit_and_html_reports_in_its_out_dir(self):
        run = self.probe(self.VERDICT)
        self.assertEqual(run.code, 0, run.out)
        self.assertEqual(run.status(self.VERDICT), ["PASS"], run.out)
        self.assertIsNotNone(run.out_dir, "a run prints `Report: <out dir>/report.json`\n" + run.out)
        self.assertTrue(list(run.out_dir.rglob("results.xml")), f"gdUnit's JUnit report in {run.out_dir}")
        self.assertTrue(list(run.out_dir.rglob("index.html")), f"gdUnit's HTML report in {run.out_dir}")
        self.assert_junit(run, self.VERDICT, "")

    def test_lines_summary_report_and_bundles_keep_their_shape(self):
        run = self.probe(self.VERDICT, GAME_TEST_VERDICT="fail")
        self.assertEqual(run.code, 1, run.out)
        self.assertEqual(run.status(self.VERDICT), ["FAIL"], "one `FAIL  <id>  (<sim>s sim, <ms> ms)` line\n" + run.out)
        self.assertIn("        ✗ verdict probe: a failed check", run.out)
        self.assertEqual(run.summary, (0, 1, 0, 0, 0), run.out)
        report = run.report()
        self.assertTrue({"results", "stray_logs", "log_end"} <= set(report), sorted(report))
        result = next(r for r in report["results"] if r["id"] == self.VERDICT)
        self.assertTrue({"id", "name", "domain", "status", "reason", "time", "checks", "logs", "wall_ms"} <= set(result), sorted(result))
        self.assertEqual(result["status"], "FAIL")
        bundles = run.bundles()
        self.assertEqual(len(bundles), 1, "a failed test prints one `bundle:` path\n" + run.out)
        bundle = json.loads(bundles[0].read_text())
        self.assertTrue({"events", "snapshot", "traces"} <= set(bundle), sorted(bundle))

    def test_a_failed_check_is_a_gdunit_failure(self):
        run = self.probe(self.VERDICT, GAME_TEST_VERDICT="fail")
        self.assert_junit(run, self.VERDICT, "failure", "verdict probe: a failed check")

    def test_a_timeout_is_a_gdunit_failure(self):
        run = self.probe(self.VERDICT, GAME_TEST_VERDICT="timeout")
        self.assertEqual(run.code, 1, run.out)
        self.assertEqual(run.status(self.VERDICT), ["TIMEOUT"], run.out)
        self.assertIn("timed out after 1.0s", run.out)
        self.assert_junit(run, self.VERDICT, "failure")

    def test_a_skipped_test_is_gdunit_skipped(self):
        run = self.probe(self.VERDICT, GAME_TEST_VERDICT="skip")
        self.assertEqual(run.code, 0, run.out)
        self.assertEqual(run.status(self.VERDICT), ["SKIPPED"], run.out)
        self.assert_junit(run, self.VERDICT, "skipped", "verdict probe: skipped on purpose")

    def test_a_gap_is_gdunit_skipped_as_expected_to_fail_with_its_failed_checks(self):
        run = self.probe(self.GAP)
        self.assertEqual(run.code, 0, "a GAP is not a failure of the run\n" + run.out)
        self.assertEqual(run.status(self.GAP), ["GAP"], run.out)
        self.assertEqual(run.summary, (0, 0, 0, 0, 1), run.out)
        self.assert_junit(run, self.GAP, "skipped", "gap: expected to fail", "gap probe: the behaviour is not built")

    def test_a_gap_test_that_passes_is_a_failure(self):
        run = self.probe(self.GAP, GAME_TEST_GAP="pass")
        self.assertEqual(run.code, 1, run.out)
        self.assertEqual(run.status(self.GAP), ["FAIL"], run.out)
        self.assertIn("drop the gap tag", run.out)
        self.assert_junit(run, self.GAP, "failure", "drop the gap tag")

    def test_a_logged_warning_fails_the_test_and_ends_it_at_once(self):
        # The probe would wait 50000 s of sim time (timeout 100000 s): only the log gate gives a verdict in time, and
        # gdUnit's own test timeout (300 s) is far off.
        run = self.probe(self.HOLD, timeout=900, GAME_TEST_HOLD="warning")
        self.assertEqual(run.code, 1, run.out)
        self.assertEqual(run.status(self.HOLD), ["FAIL"], run.out)
        self.assertIn("Logged warning: gate probe hold warning", run.out)
        _, sim, wall_ms, _ = run.results[self.HOLD][0]
        self.assertLess(sim, 1.0, f"ended at the warning, not {sim}s of sim time later")
        self.assertLess(wall_ms, 20000, f"ended at once, not after {wall_ms} ms")
        self.assertLess(run.seconds, 120, f"the run took {run.seconds:.0f} s")
        self.assert_junit(run, self.HOLD, "failure", "gate probe hold warning")

    def test_a_requires_von_test_with_no_server_is_skipped_and_fails_under_require_von(self):
        port = str(free_port())
        run = self.probe(self.VON, "--include-von", GAME_TEST_VON_PORT=port)
        self.assertEqual(run.code, 0, run.out)
        self.assertEqual(run.status(self.VON), ["SKIPPED"], f"no server on port {port}: skipped\n" + run.out)
        self.assert_junit(run, self.VON, "skipped")
        run = self.probe(self.VON, "--require-von", GAME_TEST_VON_PORT=port)
        self.assertEqual(run.code, 1, run.out)
        self.assertEqual(run.status(self.VON), ["FAIL"], f"no server on port {port} under --require-von: FAIL\n" + run.out)
        self.assert_junit(run, self.VON, "failure")

    def test_a_requires_von_test_is_skipped_without_include_von(self):
        run = self.probe(self.VON)
        self.assertEqual(run.code, 0, run.out)
        self.assertEqual(run.status(self.VON), ["SKIPPED"], run.out)
        self.assertIn("--include-von", run.out)
        self.assert_junit(run, self.VON, "skipped")

    def test_list_prints_the_selection_and_runs_nothing(self):
        run = self.run_tests("--self-test", "--list")
        self.assertEqual(run.code, 0, run.out)
        self.assertRegex(run.out, re.compile(r"^_harness/von_probe\s+von\s+\[harness, von\]\s+Von probe$", re.M))
        self.assertRegex(run.out, re.compile(r"^\d+ test\(s\)$", re.M))
        self.assertEqual(run.results, {}, "--list runs no test")

    def test_list_matching_nothing_still_passes(self):
        run = self.run_tests("--self-test", "--list", "zzqq_no_such_word")
        self.assertEqual(run.code, 0, run.out)
        self.assertRegex(run.out, re.compile(r"^0 test\(s\)$", re.M))
        self.assertNotIn("no test matched", run.out)

    def test_summary_prints_only_what_did_not_pass(self):
        run = self.run_tests("--self-test", f"--id={self.VERDICT},{self.GAP}", "--summary")
        self.assertEqual(run.code, 0, run.out)
        self.assertEqual(run.status(self.GAP), ["GAP"], run.out)
        self.assertEqual(run.status(self.VERDICT), [], "a PASS is not printed with --summary\n" + run.out)
        self.assertEqual(run.summary, (1, 0, 0, 0, 1), run.out)

    def test_a_selection_matching_nothing_fails(self):
        for args in (["--self-test", "--id=_harness/no_such_probe"], ["--self-test", "zzqq_no_such_word"],
                     ["--no-lint", "--domain=projectile", "--skip-domain=projectile"]):
            with self.subTest(args=args):
                run = self.run_tests(*args, "--summary")
                self.assertEqual(run.code, 1, run.out)
                self.assertIn("no test matched", run.out)

    def test_repeated_id_flags_add_up(self):
        run = self.run_tests("--self-test", f"--id={self.VERDICT}", f"--id={self.GAP}", "--summary")
        self.assertEqual(run.code, 0, run.out)
        self.assertEqual(run.status(self.GAP), ["GAP"], "the second --id runs too\n" + run.out)
        self.assertEqual(run.summary, (1, 0, 0, 0, 1), "the first --id runs too\n" + run.out)

    def listed(self, *args):
        """The ids a `--list` run with `args` prints."""
        run = self.run_tests("--list", *args)
        self.assertEqual(run.code, 0, run.out)
        return {ln.split()[0] for ln in run.out.splitlines() if re.match(r"^[a-z_]+/\S+\s", ln)}

    def test_repeated_domain_and_skip_domain_flags_add_up(self):
        domains = {i.split("/")[0] for i in self.listed("--domain=projectile", "--domain=worldgen")}
        self.assertEqual(domains, {"projectile", "worldgen"})
        domains = {i.split("/")[0] for i in self.listed("--domain=projectile,worldgen,lighting",
                                                       "--skip-domain=projectile", "--skip-domain=worldgen")}
        self.assertEqual(domains, {"lighting"})

    def test_repeated_domain_and_skip_domain_flags_add_up_in_a_run(self):
        # A run, not --list: a native suite is picked by native_selected, which reads the flags itself.
        selected = "--id=general/weighted_pick_suite,physics/deformation_outline_suite,ai/door_stack_suite"
        for flags, domains in ((["--domain=general", "--domain=physics"], {"general", "physics"}),
                               (["--skip-domain=general", "--skip-domain=physics"], {"ai"})):
            with self.subTest(flags=flags):
                run = self.run_tests("--no-lint", selected, *flags)
                self.assertEqual(run.code, 0, run.out)
                self.assertEqual({i.split("/")[0] for i in run.results}, domains, run.out)

    def test_json_prints_the_results(self):
        run = self.probe(self.VERDICT, "--json")
        line = next((l for l in run.out.splitlines() if l.startswith("JSON: ")), None)
        self.assertIsNotNone(line, run.out)
        data = json.loads(line[len("JSON: "):])
        self.assertEqual([r["status"] for r in data["results"] if r["id"] == self.VERDICT], ["PASS"])

    def test_repeat_runs_each_test_that_many_times(self):
        run = self.probe(self.VERDICT, "--repeat=2")
        self.assertEqual(run.code, 0, run.out)
        self.assertEqual(run.summary[0], 2, run.out)

    # A native suite written into tests/general/ of a copy of the checkout (never the live tree, where another run
    # would pick it up): `test_counted` always passes, `test_flaky` fails on its second run (the runs are counted in
    # the file GAME_TEST_FLAKY_COUNT names, so across processes).
    FLAKY_NATIVE = "general/zz_flaky_native_probe_suite"
    FLAKY_NATIVE_SOURCE = """extends UnitSuite


func test_counted() -> void:
	assert_bool(true).is_true()


func test_flaky() -> void:
	var path := OS.get_environment("GAME_TEST_FLAKY_COUNT")
	var runs := int(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else 0
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(str(runs + 1))
	f.close()
	assert_int(runs).override_failure_message("flaky probe: the second run fails").is_not_equal(1)
"""

    def test_repeat_reruns_a_native_suite_and_names_a_flaky_case(self):
        copy = copy_checkout(Path(tempfile.mkdtemp(dir=self.tmp)) / "checkout")
        (copy / "tests" / (self.FLAKY_NATIVE + ".gd")).write_text(self.FLAKY_NATIVE_SOURCE)
        count = Path(tempfile.mkdtemp(dir=self.tmp)) / "runs"
        run = self.run_tests("--no-lint", f"--id={self.FLAKY_NATIVE}", "--repeat=3", root=copy,
                             GAME_TEST_FLAKY_COUNT=str(count))
        counted, flaky = self.FLAKY_NATIVE + "::test_counted", self.FLAKY_NATIVE + "::test_flaky"
        self.assertEqual(run.status(counted), ["PASS"] * 3, "each native case runs 3 times\n" + run.out)
        self.assertEqual(sorted(run.status(flaky)), ["FAIL", "PASS", "PASS"], run.out)
        self.assertRegex(run.out, re.compile(r"^FLAKY\s+2/3 passed\s+" + re.escape(flaky) + "$", re.M))
        self.assertNotRegex(run.out, re.compile(r"^(FLAKY|FAILING).*test_counted", re.M))
        self.assertEqual(run.summary, (5, 1, 0, 0, 0), run.out)
        self.assertEqual(run.code, 1, run.out)

    def test_fail_fast_stops_after_the_first_failure(self):
        run = self.run_tests("--self-test", f"--id={self.GAP},{self.VERDICT}", "--fail-fast", GAME_TEST_GAP="pass")
        self.assertEqual(run.code, 1, run.out)
        self.assertEqual(run.status(self.GAP), ["FAIL"], run.out)
        self.assertEqual(run.status(self.VERDICT), [], "nothing runs after the first failure\n" + run.out)

    def test_jobs_split_a_run_over_shards_and_print_one_total(self):
        ids = ["projectile/pistol_shot_wounds", "worldgen/seed_reproducible"]
        run = self.run_tests("--no-lint", "--jobs=2", "--id=" + ",".join(ids))
        self.assertEqual(run.code, 0, run.out)
        for test_id in ids:
            self.assertEqual(run.status(test_id), ["PASS"], run.out)
        self.assertRegex(run.out, re.compile(r"^2 passed, 0 failed, 0 timed out, 0 skipped, 0 gap  \(2 shards\)$", re.M))


def os_data_dir() -> Path:
    """The OS data folder Godot puts a project's custom user:// folder in (`config/custom_user_dir_name`)."""
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support"
    if sys.platform.startswith("win"):
        return Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming"))
    return Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share")


# A native suite written into the copy only: gdUnit's own log monitor (GodotGdErrorMonitor, which reads
# GdUnitSettings.get_log_path()) must read the log this run writes (`--log-file <out>/godot.log`).
LOG_PATH_PROBE = """extends UnitSuite


func test_gdunit_reads_this_runs_log() -> void:
	var run_log := ProjectSettings.globalize_path(TestBatch.option("--out").path_join("godot.log"))
	assert_str(ProjectSettings.globalize_path(GdUnitSettings.get_log_path())).is_equal(run_log)
"""


@unittest.skipUnless(godot_binary(), "no Godot binary (set GODOT=/path/to/Godot)")
class FreshUserDirTests(unittest.TestCase):
    """A run in a checkout whose user:// was never used (a fresh clone, CI, a coverage copy), so it holds no
    logs/godot.log: gdUnit reads the run's own log, nothing is logged outside a test, and the run leaves
    project.godot as it was. The checkout is a copy of this one with a user:// of its own (a custom user dir)."""

    PROBE_ID = "general/zz_log_path_probe_suite"

    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp(prefix="fresh_user_dir_"))
        cls.copy = copy_checkout(cls.tmp / "checkout")
        cls.user_dir_name = f"fe-fresh-user-dir-{cls.tmp.name}"
        cls.user_dir = os_data_dir() / cls.user_dir_name
        project = cls.copy / "project.godot"
        text = project.read_text()
        head = "[application]\n"
        assert head in text, "project.godot has an [application] section"
        project.write_text(text.replace(head, head + "\nconfig/use_custom_user_dir=true\n"
                                        f'config/custom_user_dir_name="{cls.user_dir_name}"\n', 1))
        (cls.copy / "tests" / "general" / "zz_log_path_probe_suite.gd").write_text(LOG_PATH_PROBE)
        cls.project_before = project.read_bytes()
        cls.fresh = not (cls.user_dir / "logs" / "godot.log").exists()
        env = dict(os.environ, GODOT=godot_binary(), TMPDIR=str(cls.tmp))
        # No .git in the copy, so the wrapper's clean-lint fingerprint cannot be taken: --no-lint.
        r = subprocess.run(["bash", str(cls.copy / "tools" / "run_tests.sh"), "--no-lint", f"--id={cls.PROBE_ID}"],
                           cwd=cls.copy, env=env, capture_output=True, text=True, timeout=600)
        cls.done = Run(r.returncode, r.stdout + r.stderr, 0.0)
        cls.project_after = project.read_bytes()

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)
        shutil.rmtree(cls.user_dir, ignore_errors=True)

    def test_the_copys_user_dir_held_no_log(self):
        self.assertTrue(self.fresh, f"{self.user_dir} already held logs/godot.log")

    def test_the_run_passes_with_nothing_logged_outside_a_test(self):
        self.assertEqual(self.done.code, 0, self.done.out)
        self.assertNotIn("Logged outside any test", self.done.out)
        self.assertEqual(self.done.report()["stray_logs"], [], self.done.out)

    def test_gdunit_reads_the_runs_own_log(self):
        probe = f"{self.PROBE_ID}::test_gdunit_reads_this_runs_log"
        self.assertEqual(self.done.status(probe), ["PASS"], self.done.out)

    def test_the_run_leaves_project_godot_as_it_was(self):
        self.assertEqual(self.project_after, self.project_before)


if __name__ == "__main__":
    sys.argv = [a for a in sys.argv if a != "--headed"]
    unittest.main(verbosity=2)
