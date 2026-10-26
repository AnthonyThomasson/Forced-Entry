extends RefCounted
## Testing domain: a running test's verdict (test_context.gd's `verdict`): its checks, the logged
## lines that failed it, its status and how the run is judged once it is over. It holds nothing of
## its context (an Object the session frees by hand): a method that records a check or ends the
## test takes the context at the call, `ctx`.

## Assertion records: `{ ok, message, time }`.
var checks: Array = []
## Unexpected logged errors/warnings: `{ severity, message, location }`.
var logs: Array = []
## "PASS" | "FAIL" | "SKIPPED" | "TIMEOUT" | "GAP" once ended ("" while running). GAP is a test
## tagged `gap` (a behaviour the code does not show yet, written first and left red) that failed or
## timed out as expected; one that passes is a FAIL ("drop the gap tag").
var status := ""
## Why it was skipped / timed out.
var reason := ""
## Outstanding expected log lines: `{ pattern, count }`.
var _expected_logs: Array = []
## Patterns of log lines the test lets pass (its `allowed_logs`).
var _allowed_logs: Array = []
## Whether a logged engine error / warning fails the test (its `fail_on_errors` /
## `fail_on_warnings`).
var _fail_on_errors := true
var _fail_on_warnings := true
## Whether `conclude` has already run its one-time checks (expected logs, no assertions).
var _concluded := false
## Tagged `gap`: failing is the expected verdict (GAP), passing is the failure.
var _gap := false
## A gap test passed, which is reported as the failing check "drop the gap tag" (once).
var _gap_passed := false
## The test ended by timing out; its verdict stays TIMEOUT whatever the checks say.
var _timed_out := false


func _init(description: Dictionary) -> void:
	_allowed_logs = description.get("allowed_logs", [])
	_fail_on_errors = description.get("fail_on_errors", true)
	_fail_on_warnings = description.get("fail_on_warnings", true)
	_gap = Array(description.get("tags", [])).has("gap")


## Declare that this test means to log a line matching `pattern` (regex) `count` times: those lines
## don't fail it, and the test fails if they never appear.
func expect_log(pattern: String, count := 1) -> void:
	_expected_logs.append({ "pattern": pattern, "count": count })


## The test ended with `result` (`ctx.finish`, whose first call wins): its status, and whether it
## timed out.
func end(result: String) -> void:
	status = result
	_timed_out = _timed_out or result == "TIMEOUT"


## Handle one logged entry from LogWatch: allowed or expected lines pass, anything else fails the
## test `ctx`.
func on_log(ctx: TestContext, entry: Dictionary) -> void:
	if entry["severity"] == "error" and not _fail_on_errors:
		return
	if entry["severity"] == "warning" and not _fail_on_warnings:
		return
	var LogWatch := preload("res://scenes/testing/log_watch.gd")
	for e in _expected_logs:
		if e["count"] > 0 and LogWatch.matches_any(entry, [e["pattern"]]):
			e["count"] -= 1
			return
	if LogWatch.matches_any(entry, _allowed_logs):
		return
	logs.append(entry)
	var where: String = entry["location"]
	ctx.check(
		false,
		"Logged %s: %s%s"
			% [entry["severity"], entry["message"], "" if where == "" else " (at %s)" % where],
	)
	ctx.finish("FAIL")


## Final verdict once the run of `ctx` is over: fails unmet expected logs, and a non-manual test
## that asserted nothing. A test tagged `gap` is expected to fail: its FAIL or TIMEOUT is reported
## as GAP (the failed checks say what the code does not do yet) and a pass is a FAIL that says to
## drop the tag. Safe to call again (a late logged error re-decides it). Returns the status.
func conclude(ctx: TestContext, manual: bool) -> String:
	if not _concluded:
		_concluded = true
		_close_checks(ctx, manual)
	if status == "SKIPPED":
		return status
	if _timed_out:
		status = "TIMEOUT"
	else:
		status = "FAIL" if checks.any(func(c): return not c["ok"]) else "PASS"
	if _gap:
		_gap_verdict(ctx)
	return status


## The checks the end of a run adds, once: one failed per expected log that never appeared, and one
## for a test that asserted nothing (not `manual`, not skipped).
func _close_checks(ctx: TestContext, manual: bool) -> void:
	for e in _expected_logs:
		if e["count"] > 0:
			ctx.check(
				false,
				"Expected log never appeared: /%s/ (%d more)" % [e["pattern"], e["count"]],
			)
	if checks.is_empty() and not manual and status != "SKIPPED":
		ctx.check(false, "The test made no assertions")


## A `gap` test's status: its FAIL or TIMEOUT is GAP (with a default reason), a pass a FAIL with a
## failed check that says to drop the tag (added once).
func _gap_verdict(ctx: TestContext) -> void:
	if _gap_passed or status == "PASS":
		if not _gap_passed:
			_gap_passed = true
			ctx.check(false, "passes: drop the gap tag")
		status = "FAIL"
	else:
		status = "GAP"
		if reason == "":
			reason = "expected to fail (tagged gap)"
