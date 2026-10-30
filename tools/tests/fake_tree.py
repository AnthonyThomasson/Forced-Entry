"""A throwaway tree of its own for tools/run_tests.sh (a copy of the wrapper and its tools, a perf_quiet.conf we choose, a
tests/perf folder holding a native suite) around a fake Godot and a fake `uptime` on PATH: the fixture the test modules
that run the wrapper's flags and gate on it share. The cases are the subclasses'."""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# Stands in for Godot: `--import` does nothing; the list script (`-s res://scenes/testing/test_list.gd`) notes its
# arguments in $FAKE_LISTS and says it lists $FAKE_LISTED tests (the line `<n> test(s)`; none for "no answer"); any other start notes its arguments in $FAKE_STARTS and
# writes a report of one passing case of the native suite $FAKE_SUITE (an id `<suite id>::test_x`).
FAKE_GODOT = r"""#!/usr/bin/env bash
for a in "$@"; do [ "$a" = "--import" ] && exit 0; done
log=""; out=""; listing=""; after=""
while [ $# -gt 0 ]; do
  case "$1" in
    --log-file) log="$2"; shift ;;
    --out=*) out="${1#--out=}" ;;
    res://scenes/testing/test_list.gd) listing=1 ;;
    --) after=1 ;;
    *) [ -n "$after" ] && rest="$rest $1" ;;
  esac
  shift
done
echo "Godot Engine v4.4" > "$log"
if [ -n "$listing" ]; then
  echo "list$rest" >> "$FAKE_LISTS"
  if [ "${FAKE_LISTED:-0}" = "no answer" ]; then echo "the engine says no count"; else echo "${FAKE_LISTED:-0} test(s)"; fi
  exit 0
fi
echo "start$rest" >> "$FAKE_STARTS"
printf '{"results": [{"id": "%s::test_x", "status": "PASS"}], "stray_logs": [], "log_end": %s}' "$FAKE_SUITE" \
  "$(wc -c < "$log" | tr -d ' ')" > "$out/report.json"
echo "1 passed, 0 failed, 0 timed out, 0 skipped, 0 gap"
exit 0
"""


class FakeTree(unittest.TestCase):
    """A throwaway tree around the wrapper: no test in it, the cases are the subclasses'."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="run_tests_tree_"))
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
        self.lists = self.tmp / "lists"

    def run_tests(self, *args, suite="perf/n_suite", **env_extra):
        env = {k: v for k, v in os.environ.items() if k not in ("GAME_TEST_JOBS", "GAME_TEST_CHANGED_FILES")}
        env.update(GODOT=str(self.fake), TMPDIR=str(self.state), FAKE_STARTS=str(self.starts), FAKE_LISTS=str(self.lists),
                   FAKE_SUITE=suite,
                   GAME_TEST_SLOT_DIR=str(self.state / "slots"), GAME_TEST_SLOT_POLL="0.05",
                   PATH=f"{self.bin}:{os.environ['PATH']}", GAME_TEST_QUIET_MINUTE="0.2", GAME_TEST_QUIET_POLL="0.05", **env_extra)
        r = subprocess.run(["bash", str(self.repo / "tools" / "run_tests.sh"), "--no-lint", *args], cwd=self.repo, env=env,
                           capture_output=True, text=True, timeout=120)
        return r.returncode, r.stdout + r.stderr

    def listed(self):
        """The arguments of each listing the run asked the engine for, one string each."""
        return self.lists.read_text().splitlines() if self.lists.exists() else []

    def started(self):
        """The arguments of each engine process the run started (after the `--` of the command line), one string each."""
        return self.starts.read_text().splitlines() if self.starts.exists() else []

    def last_report(self):
        return json.loads(next(self.state.glob("example_godot_last_report_*.json")).read_text())["results"]
