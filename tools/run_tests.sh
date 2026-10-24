#!/usr/bin/env bash
# Run the game tests headless through gdUnit4's command-line tool (addons/gdUnit4/bin/GdUnitCmdTool.gd, the suites in
# tests/: one wrapper suite per folder running its catalog tests, scenes/testing/game_test_suite.gd, plus the native
# *_suite.gd ones) and exit non-zero on any failure, timeout, or engine error/warning logged ANYWHERE in the run: while
# a test is open (that test fails), between tests and at start-up (reported as "Logged outside any test"), and after
# the run has finished judging (gdUnit's own reports, engine shutdown; tools/scan_godot_log.py reads that tail of each
# process's log). The flags below reach the suites after `--` (scenes/testing/test_batch.gd); the verdict is read
# from the run's report.json, gdUnit's own exit code only telling a crash. A run whose selection holds no test at all
# (every shard together) ends on "no test matched the selection: <args>" and exits 1; a --list that lists none, and a
# --changed run with nothing mapped, exit 0.
#
# Selecting tests
#   tools/run_tests.sh                    every test (Von tests skipped)
#   tools/run_tests.sh projectile         only tests matching "projectile" (id, name, domain, tag;
#                                         every word must start a word of one of those)
#   tools/run_tests.sh --domain=ai        only the tests of exactly that domain; comma list allowed
#                                         (--domain=ai,navigation). No word-prefix matching.
#   tools/run_tests.sh --id=ai/foo_bar    exactly that test id (comma list allowed)
#                                         --id, --domain and --skip-domain given again add up, as one comma list:
#                                         --id=a --id=b is --id=a,b
#   tools/run_tests.sh --skip-domain=perf leave out the tests of exactly that domain (comma list allowed); wins over
#                                         every other selection, --changed's included. The pre-commit hook skips perf:
#                                         its frame-time budgets fail on a loaded machine, so they are a separate run.
#   tools/run_tests.sh --failed           only the tests that FAILED / TIMED OUT in the previous run
#                                         of this checkout (its report is kept in $TMPDIR); none: it says so
#                                         ("nothing to rerun") and exits 0; a report it cannot read: exit 2
#   tools/run_tests.sh --changed          tests for what uncommitted changes can affect: each changed
#                                         scenes/<domain>/ plus the domains that compose it (see
#                                         `affected` below), in ONE run; main.gd, root scenes,
#                                         project.godot, worldgen, art and general run everything;
#                                         testing adds --self-test. An edited tests/<d>/[<topic>/]<name>_test.gd
#                                         runs just that test; tests/_ai, _audio, _perf, _vehicle their users.
#                                         Nothing mapped, or only domains --skip-domain leaves out: it says which
#                                         and exits 0.
#   tools/run_tests.sh --changed --staged the same for what is staged (git diff --cached), not the working tree, and
#                                         the lint of what the commit holds (tools/lint_staged.sh: the staged
#                                         scripts as they are on disk; the whole tree when project.godot or a gdstyle
#                                         file is staged; none when no script is), a finding in a script not staged
#                                         labelled `not in this commit: <path>`. The pre-commit hook runs it.
#   tools/run_tests.sh --list [words]     list matching tests (id, flags, tags, name) and exit
#   tools/run_tests.sh --include-von ai   also run tests that need the Von decision server
#   tools/run_tests.sh --require-von ai   Von tests FAIL instead of skipping when no server is live
#   tools/run_tests.sh gap                the tests tagged `gap`: specs the code does not meet yet, written first and
#                                         left red; their failure is reported as GAP and does not fail the run, and one
#                                         that passes FAILs ("drop the gap tag")
#   tools/run_tests.sh --self-test        the harness's own tests (tests/_harness, hidden from normal runs)
# Speed
#   --jobs=N|auto   split the run over N parallel godot processes (auto = cores, at most 6). Without it, a run of the
#                   whole suite uses auto and a selection (words, --id, --domain, --failed, --repeat) one process. The
#                   tests are dealt out to balance the shards by the wall-clock ms measured in earlier runs (kept in
#                   $TMPDIR, falling back to the declared timeout); Von tests all stay in shard 0. One combined
#                   summary and slowest list is printed; exit 1 if any shard failed. Not used with --list/--self-test.
#   --fail-fast     stop after the first FAIL / TIMEOUT (per shard when sharded)
# Output
#   --summary       print only the non-passing tests and the totals (best for an agent or a hook)
#   --verbose       also print the game's log of what happens (shots, punches, Von decisions, PERF
#                   numbers); a run is quiet by default
#   --json          also print the full results as one `JSON: {...}` line
#   --shots         windowed run (not headless) that saves a PNG of each failed test
#   --windowed      windowed run with vsync off, in one process: a perf test's frame times then include the render
#                   (headless measures the CPU only) without being held to the display's refresh
# Other
#   --repeat=5      run each test 5 times, a native suite's cases too (it runs again in 4 more processes); names
#                   FLAKY / FAILING tests. With a --shard given by hand a native suite runs once ("NOTE native suites
#                   ran once (--shard)").
#   --seed=42       pin every house() test to seed 42
#   --strict-exit   also fail on Godot's own end-of-process leak report (reported as a NOTE by default)
#   --report=FILE   also write the run's merged report (results, stray_logs) to FILE (the in-game browser's Run all)
#   --no-lint       skip the lint that runs first (tools/lint.sh, ~14 s: unused variables, integer division, shadowed
#                   names ... the warnings of the editor's Debugger > Errors tab, the project lint rules, gdstyle). Any
#                   finding fails the run before a single test starts. Not run for --list or --self-test, nor when
#                   the sources are unchanged since the last clean lint (fingerprint kept in $TMPDIR; the lint of
#                   --changed --staged never records one).
# Not here: --play <words> (play one test or sandbox in the runner) is the runner's own flag; this wrapper only runs
# batches, so it refuses --play and prints the command that launches the runner.
# Every run ends with a `Slowest:` line (wall-clock ms per test).
# A failed test prints its final actor state and a `bundle:` path to a JSON with its event log,
# state and traces. Each invocation gets its own engine log, report and bundles in a fresh temp dir
# (printed as `Report:` / `bundle:`), so concurrent runs and a running game never share files. gdUnit's JUnit and
# HTML reports land in that dir too (gdunit/report_1/results.xml, index.html), and its own console, which the
# printed output leaves out, in gdunit.txt.
set -euo pipefail
cd "$(dirname "$0")/.."
# Every engine process runs with the dev command server off (over any port the caller set): a test run never drives
# it, and a port another worktree's game or run holds would otherwise fail the run on its "failed to listen" warning.
export GODOT_CMD_PORT=off
GODOT="${GODOT:-$( command -v godot || command -v godot4 \
  || ls /Applications/Godot*.app/Contents/MacOS/Godot 2>/dev/null | head -1 )}"
if [[ -z "$GODOT" ]]; then
  echo "Godot binary not found (set GODOT=/path/to/Godot)" >&2
  exit 2
fi

# A fresh checkout has no import cache (.godot/ is untracked): without the class cache every test script
# fails to parse and the runner hangs instead of failing, so import first.
if [[ ! -f .godot/global_script_class_cache.cfg ]]; then
  echo "importing the project (first run in this checkout)..." >&2
  "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
fi

# Per-checkout state kept in $TMPDIR: the previous run's merged report (for --failed), the measured wall-clock
# ms per test (what --shard balances the parallel processes by) and the fingerprint of the last clean lint.
KEY=$(printf %s "$PWD" | shasum | cut -c1-8)
LAST="${TMPDIR:-/tmp}/example_godot_last_report_$KEY.json"
COSTS="${TMPDIR:-/tmp}/example_godot_costs_$KEY.json"
LINT_OK="${TMPDIR:-/tmp}/example_godot_lint_ok_$KEY.txt"

HEADLESS=--headless
NOVSYNC=
WINDOWED=0
STRICT=
JOBS=
CHANGED=0
STAGED=0
LINT=1
SKIP=""   # --skip-domain=a,b (every one given, joined), also forwarded to the runner
export RUN_TESTS_REPORT_TO=""   # --report=FILE (save_reports writes the merged report there too)
args=()
for a in "$@"; do
  case "$a" in
    --shots) HEADLESS=; args+=("$a") ;;
    --windowed) HEADLESS=; NOVSYNC=--disable-vsync; WINDOWED=1 ;;
    --play)
      echo "--play is the test runner's own flag; this wrapper only runs batches (and they never see sandboxes). Launch the runner:" >&2
      echo "  \"\$GODOT\" --path . res://scenes/testing/test_runner.tscn -- --play <words>" >&2
      exit 2 ;;
    --strict-exit) STRICT=--strict-exit ;;
    --report=*) RUN_TESTS_REPORT_TO="${a#--report=}" ;;
    --jobs=*) JOBS="${a#--jobs=}" ;;
    --changed) CHANGED=1 ;;
    --staged) STAGED=1 ;;
    --no-lint) LINT=0 ;;
    --skip-domain=*) SKIP="${SKIP:+$SKIP,}${a#--skip-domain=}"; args+=("$a") ;;
    --failed)
      [[ -f "$LAST" ]] || { echo "No previous run of this checkout to take failures from." >&2; exit 2; }
      # 0: a failed test to rerun; 1: none; 3: the report cannot be read.
      python3 -c 'import json, sys
try:
    results = json.load(open(sys.argv[1])).get("results", [])
except (OSError, ValueError, AttributeError):
    sys.exit(3)
sys.exit(0 if any(r.get("status") in ("FAIL", "TIMEOUT") for r in results) else 1)' "$LAST" && found=0 || found=$?
      case $found in
        0) args+=("--failed=$LAST") ;;
        1) echo "no failed test in the last report: nothing to rerun"; exit 0 ;;
        *) echo "--failed: cannot read the last report ($LAST); run the tests again to write a new one." >&2; exit 2 ;;
      esac ;;
    *) args+=("$a") ;;
  esac
done
[[ $STAGED -eq 1 && $CHANGED -eq 0 ]] && { echo "--staged goes with --changed (--changed --staged)" >&2; exit 2; }
# --jobs=N|auto is explicit; without it a run of the whole suite uses auto and a selection (words, --id,
# --domain, --failed, --repeat, --list ...) one process, since a process costs ~3 s to start and a few tests
# do not repay it. Resolved per run() call in `jobs_for`.
JOBS_EXPLICIT=0
[[ -n "$JOBS" ]] && JOBS_EXPLICIT=1
auto_jobs() {
  local cores
  cores=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 2)
  echo $(( cores < 6 ? cores : 6 ))
}
if [[ $JOBS_EXPLICIT -eq 1 ]]; then
  [[ "$JOBS" == "auto" ]] && JOBS=$(auto_jobs)
  [[ "$JOBS" =~ ^[0-9]+$ && "$JOBS" -ge 1 ]] || { echo "--jobs wants a number or auto" >&2; exit 2; }
fi
# The number of processes for a run() with these arguments (the selection args it was called with + the global ones).
jobs_for() {
  local x ids="" n
  [[ $WINDOWED -eq 1 ]] && { echo 1; return; }  # one window, and no shard competing with what it measures
  if [[ $JOBS_EXPLICIT -eq 1 ]]; then
    # No more processes than there are tests when the selection is a list of ids (every --id given).
    for x in "$@"; do
      case "$x" in --id=*) ids="$ids,${x#--id=}" ;; esac
    done
    n=$(echo "$ids" | tr ',' '\n' | grep -c . || true)
    if [[ $n -ge 1 && $n -lt $JOBS ]]; then echo "$n"; return; fi
    echo "$JOBS"; return
  fi
  for x in "$@"; do
    case "$x" in
      --*) case "$x" in --id=*|--domain=*|--failed=*|--shots|--list|--self-test|--repeat=*) echo 1; return ;; esac ;;
      *) echo 1; return ;;  # a filter word
    esac
  done
  auto_jobs
}

# The suites (res:// paths) a run with these selection args can find its tests in, one per line, for gdUnit's `-a`:
# the harness suite for --self-test; else every suite in tests/ outside the helper folders, narrowed by the paths the
# selection names (--domain, --skip-domain, the folders of --id and --failed's ids). Which tests run is decided by the
# suites themselves (test_batch.gd); this only spares gdUnit loading suites that cannot hold one.
suites_for() {
  python3 - "$@" <<'EOF'
import json, os, sys
from pathlib import Path
opts, flags = {}, set()
for a in sys.argv[1:]:
    if a.startswith("--"):
        k, eq, v = a.partition("=")
        (opts.setdefault(k, []).append(v)) if eq else flags.add(k)
def csv(k):
    return [x.strip() for v in opts.get(k, []) for x in v.split(",") if x.strip()]
def domain(path):
    parts = path.relative_to("tests").parts
    return parts[0] if len(parts) > 1 else "general"
suites = sorted(Path("tests").rglob("*_suite.gd"))
if "--self-test" in flags:
    picked = [s for s in suites if domain(s) == "_harness"]
else:
    picked = [s for s in suites if not domain(s).startswith("_") and domain(s) not in csv("--skip-domain")]
    if csv("--domain"):
        picked = [s for s in picked if domain(s) in csv("--domain")]
    ids = csv("--id")
    for report in opts.get("--failed", []):
        try:
            ids += [r["id"] for r in json.load(open(report)).get("results", []) if r.get("status") in ("FAIL", "TIMEOUT")]
        except Exception:
            pass
    if ids or "--failed" in opts:
        # A catalog test is in its folder's wrapper suite; a native suite is named by its id or one of its cases'.
        want = set()
        for i in ids:
            want.add(Path("tests", i.split("::")[0] + ".gd"))
            folder = os.path.dirname(i)
            want.add(Path("tests", folder, os.path.basename(folder) + "_suite.gd"))
        picked = [s for s in picked if s in want]
print("\n".join("res://" + s.as_posix() for s in picked))
EOF
}

# gdUnit's own console (its banner, suite and case lines, statistics: coloured with CSI codes, a multi-line message
# coloured over several lines) left out of what a run prints, so it reads as it always has: the verdict lines, the
# summary, the game's log under --verbose. Line by line, as it comes: a line in CSI colour is gdUnit's, and so is each
# line while a colour it opened is still open; what follows the last reset of a line whose coloured part is blank
# (gdUnit's console leaves a coloured blank before the next line) is ours. Plain lines gdUnit prints are named.
CONSOLE_FILTER=$(cat <<'EOF'
import re, sys
CSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
GDUNIT = re.compile(r"^(-{20,}|GdUnit4 Comandline Tool|Disabled fail fast!|Set report history count to |Set write reports to |"
                    r"Headless mode is ignored by option |Please note that tests that use UI interaction |"
                    r"Godot 'InputEvents' are not transported |have no effect in the test!|Finallize \.\. done|"
                    r"Scanning for test suites in:|No test cases found, abort test run!)")
open_colour = False
for raw in sys.stdin:
    line = raw.rstrip("\n")
    codes = list(CSI.finditer(line))
    if codes:
        open_colour = codes[-1].group() not in ("\x1b[0m", "\x1b[m")
        tail = line[codes[-1].end():]
        if open_colour or not tail.strip() or CSI.sub("", line[:codes[-1].start()]).strip():
            continue
        line = tail
    elif open_colour or not line.strip() or GDUNIT.match(line):
        continue
    print(line, flush=True)
EOF
)

# Start one gdUnit process writing its log/report/bundles to $1 (a fresh dir); the selection args follow. Its console
# goes whole to $1/gdunit.txt and, filtered (CONSOLE_FILTER), to stdout; the engine's stderr passes as it is. Its
# reports go to $1/gdunit (-rd is resolved under res://, so the dir is named relative to the project). The suites are
# the selection's (suites_for), or those ONLY_SUITES names (res:// paths, one per line: a --repeat's native reruns).
# Returns the run's verdict from $1/report.json (1 on a FAIL / TIMEOUT or a line logged outside any test), and 1 when
# gdUnit crashed (an exit code other than its 0 / 100 failures / 101 orphans).
ONLY_SUITES=""
godot_run() {
  local out="$1"; shift
  local rel suites=() s code
  rel=$(python3 -c 'import os, sys; print(os.path.relpath(sys.argv[1]))' "$out")
  while IFS= read -r s; do [[ -n "$s" ]] && suites+=(-a "$s"); done < <(
    if [[ -n "$ONLY_SUITES" ]]; then echo "$ONLY_SUITES"; else suites_for "$@"; fi)
  set +e
  "$GODOT" $HEADLESS $NOVSYNC --path . --fixed-fps 60 --log-file "$out/godot.log" \
    -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -c -rc 1 -rd "res://$rel/gdunit" \
    ${suites[@]+"${suites[@]}"} -- --out="$out" "$@" | tee "$out/gdunit.txt" | python3 -u -c "$CONSOLE_FILTER"
  code=${PIPESTATUS[0]}
  set -e
  if [[ $code -ne 0 && $code -ne 100 && $code -ne 101 ]]; then
    echo "gdUnit exited with $code: the run crashed (its console: $out/gdunit.txt)"
    return 1
  fi
  if [[ ! -f "$out/report.json" ]] && grep -q "No test cases found" "$out/gdunit.txt"; then
    # gdUnit runs no session, so no suite and no hook, when the selection holds no test: an empty run, as it was.
    echo '{"results": [], "stray_logs": [], "log_end": 0}' > "$out/report.json"
    echo "0 passed, 0 failed, 0 timed out, 0 skipped, 0 gap"
    echo "Report: $out/report.json"
  fi
  verdict "$out"
}

# The verdict of the run that wrote $1/report.json: 1 when a test FAILED or TIMED OUT or a line was logged outside
# any test, 0 otherwise (and when there is no report, which scan_log reports).
verdict() {
  python3 - "$1/report.json" <<'EOF'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
bad = any(r.get("status") in ("FAIL", "TIMEOUT") for r in data.get("results", [])) or bool(data.get("stray_logs"))
sys.exit(1 if bad else 0)
EOF
}

# Whether the runs that wrote the dirs given held no test at all, catalog or native: every one wrote a report and none
# has a result (a single empty shard is not an empty selection; a run that wrote no report is scan_log's to fail).
no_test() {
  python3 - "$@" <<'EOF'
import json, os, sys
try:
    sys.exit(1 if any(json.load(open(os.path.join(d, "report.json"))).get("results") for d in sys.argv[1:]) else 0)
except Exception:
    sys.exit(1)
EOF
}

# The line a run whose selection held no test ends on (it then exits 1), naming the selection: the args given.
no_test_matched() {
  echo "no test matched the selection: ${*:-the whole suite}"
}

# `--list [words]`: the tests a run with these args would select, one line each, and nothing run
# (scenes/testing/test_list.gd); it writes no report, so its whole log is scanned.
godot_list() {
  local out="$1"; shift
  "$GODOT" --headless --path . --log-file "$out/godot.log" -s res://scenes/testing/test_list.gd -- --out="$out" "$@"
}

# Merge the report.json of each dir given into $LAST (what --failed reads) and fold each test's wall-clock ms into
# $COSTS (what --shard balances the processes by: the mean of the old and the new measurement; a skip or a timeout
# says nothing about how long a test takes). With TALLY=1 it first prints the FLAKY / FAILING lines of the merged run
# (a test that passed some of its runs / none), as each process prints its own; with SLOWEST=1 the five slowest tests.
save_reports() {
  python3 - "$LAST" "$COSTS" "${SLOWEST:-0}" "${TALLY:-0}" "$@" <<'EOF'
import json, os, sys
last, costs_path, slowest, tally = sys.argv[1], sys.argv[2], sys.argv[3] == "1", sys.argv[4] == "1"
results, stray = [], []
for d in sys.argv[5:]:
    try:
        data = json.load(open(os.path.join(d, "report.json")))
    except Exception:
        continue
    results += data.get("results", [])
    stray += data.get("stray_logs", [])
if tally:
    runs = {}
    for r in results:
        if r.get("status") != "SKIPPED":
            runs.setdefault(r["id"], []).append(r.get("status") in ("PASS", "GAP"))
    for test_id, passes in runs.items():
        if not all(passes):
            print("%s  %d/%d passed  %s" % ("FLAKY  " if any(passes) else "FAILING", sum(passes), len(passes), test_id))
if results or stray:
    json.dump({"results": results, "stray_logs": stray}, open(last, "w"))
if os.environ.get("RUN_TESTS_REPORT_TO"):
    json.dump({"results": results, "stray_logs": stray}, open(os.environ["RUN_TESTS_REPORT_TO"], "w"))
fresh = {}
for r in results:
    if r.get("status") in ("PASS", "FAIL", "GAP") and r.get("wall_ms", 0) > 0:
        fresh.setdefault(r["id"], []).append(r["wall_ms"])
if fresh:
    try:
        costs = json.load(open(costs_path))
    except Exception:
        costs = {}
    for test_id, ms in fresh.items():
        if "::" in test_id:
            continue  # a native suite's case: it is never dealt out to a shard (they all run in the first)
        mean = sum(ms) / len(ms)
        costs[test_id] = mean if test_id not in costs else (costs[test_id] + mean) / 2
    json.dump(costs, open(costs_path + ".tmp", "w"))
    os.replace(costs_path + ".tmp", costs_path)
if slowest and len(fresh) > 1:
    top = sorted(((sum(v) / len(v), k) for k, v in fresh.items()), reverse=True)[:5]
    print("Slowest: " + ", ".join("%s %d ms" % (k, ms) for ms, k in top))
EOF
}

# Check the engine log of the process that wrote into dir $1 for errors and warnings the runner did not
# judge: from the byte offset it reports as `log_end` (shutdown), or from the start when it wrote no report
# (--list, a crash, a start-up failure). Prints what it finds; returns non-zero on any.
scan_log() {
  local dir="$1" listing="$2" from=0 bad=0
  if [[ -f "$dir/report.json" ]]; then
    from=$(python3 -c 'import json,sys; print(int(json.load(open(sys.argv[1])).get("log_end", 0)))' "$dir/report.json" 2>/dev/null || echo 0)
  elif [[ "$listing" -eq 0 ]]; then
    echo "Logged outside any test: the runner wrote no report (it crashed or stopped early) in $dir"
    bad=1
  fi
  python3 "$(dirname "$0")/scan_godot_log.py" "$dir/godot.log" --from="$from" $STRICT || bad=1
  return $bad
}

# A process's lines left out where several processes make one run (a sharded run, a --repeat with native suites):
# its banner, totals, FLAKY / FAILING lines and slowest list, printed once for every process together instead.
QUIET='^(Godot Engine|Godot [0-9]|Running [0-9]+ test|[0-9]+ passed, |Report: |Slowest: |FLAKY |FAILING |$)'

# One gdUnit process (godot_run) in dir $1, its lines printed as they come but the QUIET ones (all of them kept in
# $1/stdout.txt), then its log's scan (scan_log); returns 1 when either fails.
live_run() {
  local out="$1" code
  set +e
  godot_run "$@" 2>&1 | tee "$out/stdout.txt" | grep --line-buffered -Ev "$QUIET"
  code=${PIPESTATUS[0]}
  set -e
  scan_log "$out" 0 || code=1
  return $code
}

# The native suites met by the runs that wrote the dirs given (their records' `<suite id>::<case>` ids), as res://
# paths, one per line.
native_suites_met() {
  python3 - "$@" <<'EOF'
import json, os, sys
seen = []
for d in sys.argv[1:]:
    try:
        results = json.load(open(os.path.join(d, "report.json"))).get("results", [])
    except Exception:
        continue
    for r in results:
        suite = "res://tests/" + r["id"].split("::")[0] + ".gd"
        if "::" in r["id"] and suite not in seen:
            seen.append(suite)
print("\n".join(seen))
EOF
}

# One run of the runner with the given selection args, split over several processes when asked (see jobs_for). With
# --repeat=N every selected test is listed N times in its process, but a native suite runs once a process: it runs
# N-1 times more, each in a process of its own given only the native suites the run met, and the FLAKY / FAILING
# lines and the totals are those of every process together. A --shard given by hand is one process: its native
# suites run once, and a NOTE says so.
run() {
  local keep=1 sharded=0 listing=0 jobs x repeat=1 once=0
  jobs=$(jobs_for "$@" ${args[@]+"${args[@]}"})
  [[ $jobs -gt 1 ]] && sharded=1
  for x in "$@" ${args[@]+"${args[@]}"}; do
    case "$x" in --repeat=*) repeat="${x#--repeat=}" ;; esac
  done
  if [[ "$repeat" =~ ^[0-9]+$ && $repeat -gt 1 ]]; then sharded=1; else repeat=1; fi
  for x in "$@" ${args[@]+"${args[@]}"}; do
    case "$x" in --shard=*) [[ $repeat -gt 1 ]] && once=1 ;; esac
    case "$x" in --list|--self-test|--shard=*) sharded=0; repeat=1 ;; esac
    case "$x" in --list|--self-test) keep=0 ;; esac
    case "$x" in --list) listing=1 ;; esac
  done
  local out
  if [[ $sharded -eq 0 ]]; then
    out=$(mktemp -d "${TMPDIR:-/tmp}/game_tests.XXXXXX")
    local code=0
    if [[ $listing -eq 1 ]]; then
      godot_list "$out" "$@" ${args[@]+"${args[@]}"} || code=$?
    else
      godot_run "$out" "$@" ${args[@]+"${args[@]}"} || code=$?
    fi
    [[ $keep -eq 1 ]] && save_reports "$out"
    scan_log "$out" $listing || code=1
    if [[ $once -eq 1 && -n "$(native_suites_met "$out")" ]]; then
      echo "NOTE native suites ran once (--shard)"
    fi
    if [[ $listing -eq 0 ]] && no_test "$out"; then
      no_test_matched "$@" ${args[@]+"${args[@]}"}
      code=1
    fi
    return $code
  fi

  local costs_args=() shard_args=()
  local dirs=() pids=() i status=0 pid fail_fast=0
  for x in "$@" ${args[@]+"${args[@]}"}; do [[ "$x" == "--fail-fast" ]] && fail_fast=1; done
  if [[ $jobs -gt 1 ]]; then
    # Every shard reads the same costs snapshot (the file is only rewritten once they have all finished), so they
    # all compute the same split. Each one's output is printed once they have all finished.
    [[ -f "$COSTS" ]] && costs_args=("--costs=$COSTS")
    for ((i = 0; i < jobs; i++)); do
      out=$(mktemp -d "${TMPDIR:-/tmp}/game_tests.XXXXXX")
      dirs+=("$out")
      shard_args=("--shard=$i/$jobs")
      godot_run "$out" "$@" ${args[@]+"${args[@]}"} ${costs_args[@]+"${costs_args[@]}"} "${shard_args[@]}" \
        >"$out/stdout.txt" 2>&1 &
      pids+=($!)
    done
    for pid in "${pids[@]}"; do wait "$pid" || status=1; done
    for out in "${dirs[@]}"; do
      scan_log "$out" 0 >>"$out/stdout.txt" 2>&1 || status=1
      grep -Ev "$QUIET" "$out/stdout.txt" || true
    done
  else
    out=$(mktemp -d "${TMPDIR:-/tmp}/game_tests.XXXXXX")
    dirs+=("$out")
    live_run "$out" "$@" ${args[@]+"${args[@]}"} || status=1
  fi
  if [[ $repeat -gt 1 ]] && ! [[ $fail_fast -eq 1 && $status -ne 0 ]]; then
    # The native suites the run met, each run again in N-1 processes, one after another (a suite's own files are
    # never shared by two processes at once).
    ONLY_SUITES=$(native_suites_met "${dirs[@]}")
    if [[ -n "$ONLY_SUITES" ]]; then
      for ((i = 1; i < repeat; i++)); do
        out=$(mktemp -d "${TMPDIR:-/tmp}/game_tests.XXXXXX")
        dirs+=("$out")
        live_run "$out" "$@" ${args[@]+"${args[@]}"} || status=1
        [[ $fail_fast -eq 1 && $status -ne 0 ]] && break
      done
    fi
    ONLY_SUITES=""
  fi
  # Then the FLAKY / FAILING lines of every process together (with --repeat), one combined slowest list (not with
  # --summary, like the runner) and one combined total.
  local files=() show_slowest=1 tally=0 shards=""
  for out in "${dirs[@]}"; do files+=("$out/stdout.txt"); done
  for x in "$@" ${args[@]+"${args[@]}"}; do [[ "$x" == "--summary" ]] && show_slowest=0; done
  [[ $repeat -gt 1 ]] && tally=1
  [[ $jobs -gt 1 ]] && shards="  ($jobs shards)"
  TALLY=$tally SLOWEST=$show_slowest save_reports "${dirs[@]}"
  grep -h -E '^[0-9]+ passed, ' "${files[@]}" | sed -E 's/[^0-9]+/ /g' \
    | awk -v s="$shards" '{p+=$1; f+=$2; t+=$3; k+=$4; g+=$5} END {printf "%d passed, %d failed, %d timed out, %d skipped, %d gap%s\n", p, f, t, k, g, s}'
  if no_test "${dirs[@]}"; then
    no_test_matched "$@" ${args[@]+"${args[@]}"}
    status=1
  fi
  return $status
}

# Which test domains a change to scenes/<domain>/ can break: the domain itself plus everything that
# composes it (from the architecture skill's dependency graph). "all" = the whole suite.
affected() {
  case "$1" in
    ai) echo ai perf ;;
    navigation) echo navigation ai perf ;;
    interaction) echo interaction character ai ;;
    items) echo items projectile character ai perf ;;
    projectile) echo projectile physics objects character items ai perf ;;
    physics) echo physics objects projectile character items ai perf ;;
    objects) echo objects physics projectile character items interaction navigation ai perf ;;
    character) echo character items interaction projectile physics objects ai perf ;;
    # The character composes the vehicle's CharacterVehicleUse; the camera (general) and Sound (audio) read the vehicle.
    vehicle) echo vehicle character items interaction projectile physics objects ai perf audio general ;;
    ui) echo ui ;;
    # audio: the Sound autoload runs in every test; lighting: every test world is lit (WorldLighting).
    worldgen|art|general|testing|audio|lighting) echo all ;;
    *) echo all ;;  # anything unknown is treated as risky
  esac
}

# The lint comes first: it takes seconds, and a script the analyzer complains about is not worth a test run.
for x in ${args[@]+"${args[@]}"}; do
  case "$x" in --list|--self-test) LINT=0 ;; esac
done
# The same sources lint the same: the fingerprint of the last clean lint (HEAD plus every uncommitted change,
# the way tools/stop_hook_checks.sh fingerprints) is kept in $LINT_OK, and a run on an identical tree skips the
# ~14 s. It spans the whole checkout, so it covers everything the lint reads: the scripts the engine pass compiles,
# the rules in tools/lint_rules/ and what they scan (scenes/, tests/, addons/, project.godot). Any edit, new file or
# new commit changes it, so the lint still runs before every first test run.
lint_fingerprint() {
  { git rev-parse HEAD; git diff HEAD; git ls-files --others --exclude-standard | while read -r f; do echo "$f"; shasum "$f"; done; } \
    | shasum | cut -d' ' -f1
}
# With --changed --staged the lint covers what the commit holds (tools/lint_staged.sh: the staged scripts, or the
# whole tree when a file that governs every script is staged). It may say nothing of the rest of the tree, so it never
# records the clean-lint fingerprint.
if [[ $LINT -eq 1 ]]; then
  fingerprint=$(lint_fingerprint)
  if [[ -f "$LINT_OK" && "$(cat "$LINT_OK")" == "$fingerprint" ]]; then
    echo "lint skipped: the sources are unchanged since the last clean lint" >&2
  else
    lint=("$(dirname "$0")/lint.sh")
    [[ $STAGED -eq 1 ]] && lint=("$(dirname "$0")/lint_staged.sh")
    if ! lint_out=$("${lint[@]}" 2>&1); then
      echo "$lint_out"
      echo "GDScript lint failed: no tests were run (--no-lint skips it)." >&2
      exit 1
    fi
    [[ $STAGED -eq 0 ]] && echo "$fingerprint" > "$LINT_OK"
  fi
fi

if [[ $CHANGED -eq 1 ]]; then
  # GAME_TEST_CHANGED_FILES (newline-separated paths) stands in for git's view of the changes: tools/test_log_gate.py
  # uses it to test the mapping below without crafting a working tree.
  if [[ -n "${GAME_TEST_CHANGED_FILES:-}" ]]; then
    files="$GAME_TEST_CHANGED_FILES"
  elif [[ $STAGED -eq 1 ]]; then
    files=$(git -c core.quotePath=false diff --cached --name-only)   # what the commit holds, not the working tree
  else
    files=$( { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u )
  fi
  domains=""   # domains a changed scene can break, with the ones that compose it (see `affected`)
  exact=""     # domains whose own tests a changed test helper feeds, and nothing beyond them
  ids=""       # test ids of changed test files: an edited test can only change its own result
  perf=0       # the shared perf helper changed: every test of the perf domain
  self_test=0
  for f in $files; do
    case "$f" in
      scenes/testing/*|scenes/ai/decision/decision_stub.gd|scenes/ai/decision/decision_client.gd) self_test=1 ;;
    esac
    case "$f" in
      tests/_harness/*) self_test=1 ;;
      tests/_ai/*) exact="$exact ai" ;;
      tests/_audio/*) exact="$exact audio" ;;
      tests/_lighting/*) exact="$exact lighting" ;;
      tests/_vehicle/*) exact="$exact vehicle audio general" ;;   # also feeds audio/vehicle_sounds and the general vehicle tests
      tests/_perf/*) perf=1 ;;
      tests/_*/*) domains="$domains all" ;;    # an unknown helper folder: assume the worst
      tests/*/*.uid) ;;                        # generated next to a script
      tests/*/*_test.gd) [[ -f "$f" ]] && { id="${f#tests/}"; ids="$ids ${id%_test.gd}"; } ;;
      tests/*/*_suite.gd) exact="$exact $(echo "$f" | cut -d/ -f2)" ;;   # a gdUnit suite: its domain's tests
      tests/*/*) exact="$exact $(echo "$f" | cut -d/ -f2)" ;;   # some other file in a domain's test folder
      scenes/*/*) domains="$domains $(affected "$(echo "$f" | cut -d/ -f2)")" ;;
      scenes/*|project.godot) domains="$domains all" ;;   # main.gd, root scenes, autoload wiring
    esac
  done
  domains=$(echo $domains | tr ' ' '\n' | sort -u | tr '\n' ' ')
  domains="${domains% }"
  status=0
  skipped=""   # the domains a changed file maps to that --skip-domain leaves out
  ran=0
  if [[ " $domains " == *" all "* ]]; then
    ran=1
    echo "== all tests (a changed file can affect every domain) =="
    run || status=1
  else
    # A domain or test --skip-domain leaves out maps to nothing (the hook's perf): a run of only those would be empty.
    existing=""
    kept=0
    for d in $domains $exact; do
      [[ -d "tests/$d" && ",$existing," != *",$d,"* ]] && existing="$existing,$d"
      [[ -d "tests/$d" && ",$SKIP," != *",$d,"* ]] && kept=1
      [[ -d "tests/$d" && ",$SKIP," == *",$d,"* && ",$skipped," != *",$d,"* ]] && skipped="$skipped,$d"
    done
    if [[ $kept -eq 1 ]]; then
      ran=1
      echo "== ${existing#,} =="
      run "--domain=${existing#,}" || status=1
    fi
    # Changed test files whose domain is not already running above.
    only_ids=""
    for id in $ids; do
      d="${id%%/*}"
      [[ ",$SKIP," == *",$d,"* && ",$skipped," != *",$d,"* ]] && skipped="$skipped,$d"
      [[ ",$existing," == *",$d,"* || ",$SKIP," == *",$d,"* ]] || only_ids="$only_ids,$id"
    done
    if [[ -n "$only_ids" ]]; then
      ran=1
      echo "== ${only_ids#,} =="
      run "--id=${only_ids#,}" || status=1
    fi
    [[ $perf -eq 1 && ",$SKIP," == *",perf,"* && ",$skipped," != *",perf,"* ]] && skipped="$skipped,perf"
    if [[ $perf -eq 1 && ",$SKIP," != *",perf,"* ]]; then
      ran=1
      echo "== perf tests (tests/_perf changed) =="
      run --domain=perf || status=1
    fi
  fi
  if [[ $self_test -eq 1 ]]; then
    ran=1
    echo "== harness self-tests =="
    run --self-test || status=1
  fi
  if [[ $ran -eq 0 && -n "$skipped" ]]; then
    echo "No test to run: the changed files map only to skipped domains (${skipped#,})."
  elif [[ $ran -eq 0 ]]; then
    echo "No changed file maps to any tests (affected: ${domains:-none})."
  fi
  exit $status
fi

run
