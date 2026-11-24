extends GameTest
## The decision's throw-spot search (`SnapshotDemand.throw_search`, the throw piece of the job) is
## skipped when the NPC carries no grenade: it can make no throw, so `grenade_ready` is false
## without the scan of candidates, the rank and the routes (17 to 31 units a decision in a 10v10
## cost most of their share there). With a frag in the pack the same situation does search.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const NPC := Vector2(150, 250)


func describe() -> Dictionary:
	return {
		"name": "A decision with no grenade in the pack makes no throw search",
		"description": "An NPC that knows a hostile and carries no grenade has the fact "
			+ "grenade_ready false and no throw search to run; with a frag it gets one.",
		"tags": ["ai", "decision", "grenade", "scripted"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 400))
	s.von_script([])
	s.switch(&"ai.callouts", false)
	s.actor(&"d", &"defender", NPC, { "movement:speed": 0.0, "facing": Vector2.RIGHT })
	s.actor(
		&"h", &"puppet", Vector2(600, 250), { "faction": &"invader", "max_health": 1_000_000.0 }
	)


func run(t: TestContext) -> void:
	var brain := t.controller(&"d", &"debug_state")
	var seen := func() -> bool: return (
		(brain.debug_state().get("contacts", []) as Array).any(func(c): return c.get("hostile"))
	)
	if not t.require(await t.until(seen, 3.0), "set-up: the defender sees the hostile"):
		return
	var perception: Node = brain.get("_perception")
	var goal: String = brain.get("goal")
	var bare := _snapshot(perception, goal)
	t.check(bare["demand"].throw_search(16) == null, "no grenade carried: no throw search")
	t.check(not bare["demand"].fact("grenade_ready"), "... and grenade_ready is false")
	Probe.arm(t.actor(&"d"), 0, 1)
	var armed := _snapshot(perception, goal)
	t.check(armed["demand"].throw_search(16) != null, "with a frag in the pack: a throw search")


## A snapshot built whole from what the NPC knows now.
func _snapshot(perception: Node, goal: String) -> Dictionary:
	return perception.sense(goal, "", 0)
