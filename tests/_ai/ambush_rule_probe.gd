extends RefCounted
## Shared helper for the tests of the defenders' ambush rule (`docs/leadership.md` LD29; not a test
## itself): `const AmbushRule := preload("res://tests/_ai/ambush_rule_probe.gd")`. A radio call
## placing a hostile, posted on the bus as a member's controller posts one, and the ambush order
## the squad gives on it, read off the bus through `order_probe.gd` (`Order.ambushes`).

const Order := preload("res://tests/_ai/order_probe.gd")


## Post a COMBAT callout of `faction` from `speaker` placing a hostile at `target` (its
## `target_pos`, what the ambush rule reads), wait two frames, and return the ambush order it gave
## rise to, or {}.
static func combat_call(
	t: TestContext,
	speaker: Node,
	faction: StringName,
	target: Vector2,
) -> Dictionary:
	var before := Order.ambushes(t).size()
	EventBus.post(&"callout", {
		"speaker": speaker, "faction": faction, "position": speaker.global_position,
		"status": "", "path": "combat/t_1/engage/here", "label": "COMBAT", "target_id": 0,
		"point": speaker.global_position, "target_pos": target,
	})
	await t.frames(2)
	var after := Order.ambushes(t)
	return after.back() if after.size() > before else {}
