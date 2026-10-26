extends GameTest
## Harness self-test: TestContext decides verdicts correctly from fed log entries and assertions
## (logged warning/error fails, expect_log consumes, allowed/disabled logs pass, no-assertion test
## fails, skip stays skipped, a `gap` test fails as GAP and passes as FAIL). Uses throwaway
## contexts, so nothing real is logged.


func describe() -> Dictionary:
	return {
		"name": "Context verdict rules",
		"tags": ["harness", "context", "log"],
		"internal": true,
		"timeout": 3.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func _ctx(t: TestContext, desc := {}) -> TestContext:
	return TestContext.new(t.world.get_tree(), desc)


static func _entry(severity: String, message: String) -> Dictionary:
	return { "severity": severity, "message": message, "location": "x.gd:1", "line": "" }


func run(t: TestContext) -> void:
	_check_logs(t)
	_check_assertions(t)
	_check_gaps(t)


## Logged lines: an unexpected warning fails, an expected one is consumed (and fails when it never
## comes), `allowed_logs` and `fail_on_warnings` off let them pass.
func _check_logs(t: TestContext) -> void:
	var c := _ctx(t)
	c.check(true, "fine")
	c.verdict.on_log(c, _entry("warning", "stray warning"))
	t.expect_eq(c.verdict.conclude(c, false), "FAIL", "an unexpected warning fails the test")
	t.check(c.is_finished, "and ends it")
	c.free()

	c = _ctx(t)
	c.verdict.expect_log("boom")
	c.check(true, "fine")
	c.verdict.on_log(c, _entry("error", "boom happened"))
	t.expect_eq(c.verdict.conclude(c, false), "PASS", "an expected log line is consumed")
	t.check(c.verdict.logs.is_empty(), "and not recorded as unexpected")
	c.free()

	c = _ctx(t)
	c.verdict.expect_log("never logged")
	c.check(true, "fine")
	t.expect_eq(
		c.verdict.conclude(c, false),
		"FAIL",
		"an expected log line that never appears fails",
	)
	c.free()

	c = _ctx(t, { "allowed_logs": ["noisy"] })
	c.check(true, "fine")
	c.verdict.on_log(c, _entry("error", "noisy thing"))
	t.expect_eq(c.verdict.conclude(c, false), "PASS", "allowed_logs pass")
	c.free()

	c = _ctx(t, { "fail_on_warnings": false })
	c.check(true, "fine")
	c.verdict.on_log(c, _entry("warning", "ignored"))
	t.expect_eq(c.verdict.conclude(c, false), "PASS", "fail_on_warnings off ignores warnings")
	c.free()


## Assertions: none fails a non-manual test, skip stays SKIPPED, a failed require ends it as FAIL.
func _check_assertions(t: TestContext) -> void:
	var c := _ctx(t)
	t.expect_eq(c.verdict.conclude(c, false), "FAIL", "a non-manual test with no assertions fails")
	c.free()
	c = _ctx(t)
	t.expect_eq(c.verdict.conclude(c, true), "PASS", "a manual test needs none")
	c.free()

	c = _ctx(t)
	c.skip("because")
	t.expect_eq(c.verdict.conclude(c, false), "SKIPPED", "skip stays SKIPPED")
	c.free()

	c = _ctx(t)
	c.require(false, "stop here")
	t.check(
		c.is_finished and c.verdict.conclude(c, false) == "FAIL",
		"a failed require ends the test as FAIL",
	)
	c.free()


## Gap tests and timeouts: a failing or timed-out gap test is GAP, a passing one FAIL with a check
## that says to drop the tag, a timeout stays TIMEOUT; each verdict holds when re-decided.
func _check_gaps(t: TestContext) -> void:
	var c := _ctx(t, { "tags": ["ai", "gap"] })
	c.check(false, "not yet")
	t.expect_eq(c.verdict.conclude(c, false), "GAP", "a gap test that fails is GAP")
	t.expect_eq(c.verdict.conclude(c, false), "GAP", "and stays GAP when re-decided")
	c.free()

	c = _ctx(t, { "tags": ["gap"] })
	c.check(true, "fine")
	t.expect_eq(c.verdict.conclude(c, false), "FAIL", "a gap test that passes is FAIL")
	t.check(
		c.verdict.checks.any(
			func(k): return not k["ok"] and String(k["message"]).contains("drop the gap tag"),
		),
		"and says to drop the tag",
	)
	t.expect_eq(c.verdict.conclude(c, false), "FAIL", "and stays FAIL when re-decided")
	c.free()

	c = _ctx(t, { "tags": ["gap"] })
	c.check(true, "fine so far")
	c.finish("TIMEOUT")
	t.expect_eq(c.verdict.conclude(c, false), "GAP", "a gap test that times out is GAP")
	c.free()

	c = _ctx(t)
	c.check(true, "fine so far")
	c.finish("TIMEOUT")
	t.expect_eq(
		c.verdict.conclude(c, false),
		"TIMEOUT",
		"a timed-out test stays TIMEOUT when re-decided",
	)
	t.expect_eq(c.verdict.conclude(c, false), "TIMEOUT", "again")
	c.free()
