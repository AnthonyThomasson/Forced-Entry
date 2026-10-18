extends "res://tests/ai/entry/entry_held_by_forming_stack_keeps_slot_test.gd"

## The cap of `entry_held_by_forming_stack_keeps_slot` (ticket #65 round 2, `docs/tactical-entry.md` E2): the same map and stack, but the
## teammate in the gap radios its claim and never moves. The invader keeps its slot while held under the cap (`CAP` s from when the hold
## of its approach, no waypoint left, began), then the rule for a walk the stack seals holds: it takes the back of the stack (slot 4, behind
## the far teammate's 3).


func describe() -> Dictionary:
	return {
		"name": "A walk held by a teammate on its way keeps its slot only up to the cap",
		"description": "A teammate that has claimed a slot of the same stack stands for ever in the only gap on the way; the invader keeps its slot while held under the cap, then takes the back of the stack as a walk the stack seals does.",
		"tags": ["ai", "entry", "stack", "navigation", "scripted"],
		"timeout": 40.0,
	}


func steps_aside() -> bool:
	return false


func _judge(t: TestContext, st: Dictionary) -> void:
	var held_to_rise := float(st["rise_at"]) - float(st["held_bare_at"])
	t.check(st["rise_at"] != INF and int(st["slots"][st["slots"].size() - 1]) == 4,
		"past the cap it takes the back of the stack (claimed %s)" % [st["slots"]])
	t.check(held_to_rise >= CAP - 0.25 and held_to_rise <= CAP + 1.0,
		"it keeps its slot under the cap and takes the back soon after it (the slot rose %.2f s into the hold, the cap %.1f s)" % [held_to_rise, CAP])
