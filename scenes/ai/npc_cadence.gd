extends RefCounted
## AI orchestrator: the controller's decide cadence, a data leaf it builds once in its `_ready` and
## holds as `_cadence`. When the next decision is allowed, whether one is forced and why, the walks
## started and why the latest one began, an order awaiting its decision, the salient key about
## hostiles, and what the last snapshot held (its facts, global sections and option groups), kept
## for the observers' `debug_*` reads. The controller drives it; it decides nothing itself.

## Seconds until the next decision is allowed.
var decide_timer := 0.0
## Force a decision now (task resolved or salient event).
var forced := false
## Why `forced` was last raised, kept (with `force_ms`) for the brain overlay.
var force_reason := ""
## When `force_reason` was raised (game msec, `GameClock.msec()`).
var force_ms := 0
## Decision walks started so far (`debug_state()["decisions"]`).
var decisions := 0
## Why the latest walk was started: the force reason, or "cadence"
## (`debug_state()["decision_reason"]`).
var decision_reason := ""
## `decisions` when an order was last taken, while its decision has not landed (-1: none awaited);
## see `Behavior.await_order`.
var order_from := -1
## Known-hostile set + engaged contact's inside state, for edge detection.
var salient_key := ""
## Whether `salient_key` has been seeded.
var salient_init := false
## The facts of the last decision snapshot, retained for `debug_state()`.
var last_facts := {}
## The state sections of the last decision snapshot (the global ones: `goal`, `order`, ...), the
## text Von reads in any question of the walk, retained for `debug_state()`.
var last_sections := {}
## The option groups of the last snapshot, retained for `debug_zones()`.
var last_options := {}


## Raise the force-decide flag and remember why, for the brain debug overlay.
func force(reason: String) -> void:
	forced = true
	force_reason = reason
	force_ms = GameClock.msec()


## Count the decide timer down by `delta` (s): whether the decide cadence has elapsed.
func due(delta: float) -> bool:
	decide_timer -= delta
	return decide_timer <= 0.0
