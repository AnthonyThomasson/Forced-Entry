"""tools/run_tests.sh --quiet in a throwaway tree of its own (a copy of the wrapper and its tools, a perf_quiet.conf we
choose, a tests/perf folder holding a native suite), around a fake Godot and a fake `uptime` on PATH: a quiet gate that
fails for another reason than its timeout fails the run, and a native suite met in tests/perf is gated when it is run
again by --repeat while one outside it is not. (The gate around the real tree's perf tests is tools/test_log_gate.py's
QuietGateTests.)"""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# Stands in for Godot: `--import` does nothing; any other start notes itself in $FAKE_STARTS and writes a report of one
# passing case of the native suite $FAKE_SUITE (an id `<suite id>::test_x`).
FAKE_GODOT = r"""#!/usr/bin/env bash
for a in "$@"; do [ "$a" = "--import" ] && exit 0; done
log=""; out=""
while [ $# -gt 0 ]; do
  case "$1" in --log-file) log="$2"; shift ;; --out=*) out="${1#--out=}" ;; esac
  shift
done
echo "Godot Engine v4.4" > "$log"
echo started >> "$FAKE_STARTS"
printf '{"results": [{"id": "%s::test_x", "status": "PASS"}], "stray_logs": [], "log_end": %s}' "$FAKE_SUITE" \
  "$(wc -c < "$log" | tr -d ' ')" > "$out/report.json"
echo "1 passed, 0 failed, 0 timed out, 0 skipped, 0 gap"
exit 0
"""


class QuietTreeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="run_tests_quiet_"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.repo = self.tmp / "repo"
        self.state = self.tmp / "state"
        self.state.mkdir()
        tools = self.repo / "tools"
        tools.mkdir(parents=True)
        for name in ("run_tests.sh", "scan_godot_log.py", "godot_slot.py"):
            shutil.copy2(ROOT / "tools" / name, tools / name)
        self.conf = tools / "perf_quiet.conf"
        self.conf.write_text("max_load=6\ntimeout_min=30\n")
        (self.repo / ".godot").mkdir()
        (self.repo / ".godot" / "global_script_class_cache.cfg").write_text("")
        (self.repo / "tests" / "perf").mkdir(parents=True)
        (self.repo / "tests" / "perf" / "perf_suite.gd").write_text("")
        (self.repo / "tests" / "perf" / "n_suite.gd").write_text("")
        (self.repo / "tests" / "general").mkdir()
        (self.repo / "tests" / "general" / "m_suite.gd").write_text("")
        self.fake = self.tmp / "fakegodot"
        self.fake.write_text(FAKE_GODOT)
        self.fake.chmod(0o755)
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        (self.bin / "uptime").write_text('#!/bin/sh\necho " 0:31  up 5 days, 22 users, load averages: 9.00 13.70 13.61"\n')
        (self.bin / "pgrep").write_text("#!/bin/sh\nexit 1\n")
        for f in ("uptime", "pgrep"):
            (self.bin / f).chmod(0o755)
        self.starts = self.tmp / "starts"

    def run_tests(self, *args, suite="perf/n_suite"):
        env = {k: v for k, v in os.environ.items() if k not in ("GAME_TEST_JOBS", "GAME_TEST_CHANGED_FILES")}
        env.update(GODOT=str(self.fake), TMPDIR=str(self.state), FAKE_STARTS=str(self.starts), FAKE_SUITE=suite,
                   GAME_TEST_SLOT_DIR=str(self.state / "slots"), GAME_TEST_SLOT_POLL="0.05",
                   PATH=f"{self.bin}:{os.environ['PATH']}", GAME_TEST_QUIET_MINUTE="0.2", GAME_TEST_QUIET_POLL="0.05")
        r = subprocess.run(["bash", str(self.repo / "tools" / "run_tests.sh"), "--no-lint", *args], cwd=self.repo, env=env,
                           capture_output=True, text=True, timeout=120)
        return r.returncode, r.stdout + r.stderr

    def last_report(self):
        return json.loads(next(self.state.glob("example_godot_last_report_*.json")).read_text())["results"]

    def test_a_gate_that_fails_for_another_reason_than_its_timeout_fails_the_run(self):
        self.conf.write_text("max_load=\ntimeout_min=30\n")  # the helper cannot read it
        code, out = self.run_tests("--domain=perf", "--quiet")
        self.assertNotEqual(code, 0, out)
        self.assertRegex(out, r"quiet gate failed")
        self.assertFalse(self.starts.exists(), "the perf tests did not run on a gate that could not wait\n" + out)
        self.assertFalse(list(self.state.glob("example_godot_last_report_*.json")), "no result is marked loaded for it")

    def test_a_native_suite_met_in_tests_perf_is_gated_when_it_runs_again(self):
        code, out = self.run_tests("--repeat=2", "--quiet=1")
        self.assertEqual(code, 0, out)
        self.assertEqual(out.count("quiet gate timed out"), 2, "the first process and the rerun both wait\n" + out)
        self.assertEqual([r.get("loaded") for r in self.last_report()], [True, True])

    def test_a_native_suite_outside_tests_perf_is_not_gated_when_it_runs_again(self):
        code, out = self.run_tests("--repeat=2", "--quiet=1", suite="general/m_suite")
        self.assertEqual(code, 0, out)
        self.assertEqual(out.count("quiet gate timed out"), 1, "only the first process holds perf tests\n" + out)
        self.assertEqual([r.get("loaded") for r in self.last_report()], [True, None])


if __name__ == "__main__":
    unittest.main()
