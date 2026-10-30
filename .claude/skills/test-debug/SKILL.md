---
name: test-debug
description: Debug a failing or flaky game test - read the failure bundle, narrow it down, tell a test bug from a code bug. Use when `tools/run_tests.sh` reports FAIL / TIMEOUT or a test is intermittent. Fixing a bug is `fix`.
---

# Debugging game tests

Runner flags and selection: `domain-testing`, "Running tests". Run Godot with the Bash sandbox disabled. Every test runs
through gdUnit4: a simulation test (`GameTest`) as one case of its folder's wrapper suite, a native pure-logic suite
(`*_suite.gd`, `UnitSuite`) case by case, id `<path>::<function>`.

## 1. Read the failure first

A FAIL/TIMEOUT prints its ✗ checks, each actor's final state (`· name at (x, y) health … act …`), the `t.trace` series
(min/max/last) and a `bundle:` path. The bundle JSON has the time-stamped `events` (EventBus topics, `died`,
`hit_landed`, `spawned`/`removed`), the final `snapshot` (actors + objects), `traces` and logged errors. Read it before
rerunning; it usually names the cause (no `hit` event: the shot never fired; target `health` unchanged: it hit cover).
Add `--summary` to keep output to the failures and totals. A hang with no output: the project was never imported, or a
parse error. The run's out dir (the `Report:` line's folder) also holds gdUnit's console (`gdunit.txt`), its JUnit
`gdunit/report_1/results.xml` and HTML report, and the engine log (`godot.log`): `gdUnit exited with <n>: the run
crashed` sends you to `gdunit.txt`. A run of the editor's GdUnit panel keeps its bundles in `user://test_failures/` and
gdUnit's reports in `user://gdunit_reports/report_<n>/`.

## 2. Narrow it down

- One test: `--id=<domain>/<name>`; then `--failed` (with `--fail-fast` to stop at the first).
- Flaky: `--repeat=10 <words>` names `FLAKY` (some pass) vs `FAILING` (none). `--seed=N` pins every `house()` layout to
  separate layout luck from logic. Watching a repeat run with `Monitor`, filter to the failures and the totals line,
  `FAIL|TIMEOUT|FLAKY|FAILING|[0-9]+ passed, [0-9]+ failed`: it wakes you on what you act on, not once per pass.
- `t.trace("gap", value)` in the wait loop shows *why* a threshold was missed; rerun and read the series.
- Turn behaviours off to isolate (`s.switch(&"ai.callouts", false)`) rather than editing production code.
- A picture: `--shots <words>` (windowed) saves a PNG per failed test; Read it.
- Suspect the harness: `--self-test`.
- Watch it live: `"$GODOT" --path . res://scenes/testing/test_runner.tscn -- --play <words>` (`$GODOT`: `godot-run`)
  (windowed, result banner, overlay bar, Rerun).
- Step through it: in the editor's GdUnit panel, right-click the case (`test_<folder>:<n> ('<id>')`) → **Debug**; a
  breakpoint in the test or the game code stops there, the world in gdUnit's window (`domain-testing`, "The GdUnit
  panel").
- Suspiciously slow: every run ends with a `Slowest:` line (wall-clock ms).

## 3. Test bug or code bug?

- Waited a fixed time instead of `t.until(...)`, or fired before the facing caught up (aim, wait ~0.5 s, fire): test bug.
- An engine error/warning logged: real; fix the code (or `t.verdict.expect_log` / `allowed_logs` if intended).
- A behaviour that misses a band or a distance (a follower too far behind, a walker off its line), or a walker that
  stops or stalls: trace the actor frame by frame through the miss window before calling it test slack or proposing a
  design. Series and p50s hide a per-frame stall. The first trace logs `movement.move_input`, `movement.run_input`,
  the destination and the body holding it, not only the rule that stopped it, as one `[dbg]` line
  (the temporary-trace rule below). A frame with no step that no rule names is a code bug. A question to the user
  about the miss quotes the trace.
- Passes alone, fails after another test: a leaked `static var`. Use `set_static` or a switch so it is restored; never
  assign a config holder directly in a test.
- A failure the diff cannot reach (a test of a domain the change leaves untouched, or one failing on `main` too): rerun
  it alone, `--id=<id> --repeat=10`, report its `FLAKY` / `FAILING` line (`FLAKY … 7/10 passed`) and its `bundle:`
  path, and hand it to a ticket of its own. The change's work stays inside the change's domains.
- Temporary traces: one tagged line (`print("[dbg] …")`), under 100 columns, removed before the turn ends, since the
  Stop hook lints the tree. A diagnostic copy of a test lives outside `tests/` (the scratchpad), or is deleted before
  the turn ends.
- A native suite case failing: the pure function under it, or the suite's premise (it checks its premise first). The
  behaviour is still the simulation test's to prove: native suites only supplement simulation tests, never replace
  them, so a fix keeps (or adds) the `GameTest` that shows the behaviour.
