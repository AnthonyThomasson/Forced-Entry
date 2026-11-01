extends GameTest
## V8 (`docs/player-vision.md`): in a played match the view is built for the human only. A declared
## match with a human (a `player` actor joined to the defenders) has one view, built for that
## human: not one per NPC, not one for the match; the match handle names it.
##
## It reads (tests/_vision/vision_probe.gd) the `PlayerView` nodes under the world: `viewer()`; the
## match handle's `view`. The switch is the `vision.enabled` row of the Testing domain's table.

const Probe := preload("res://tests/_vision/vision_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A played match has one view, built for the human",
		"description": "A declared match with a human has exactly one view, of that human, and "
			+ "the match's NPCs have none.",
		"tags": ["vision", "match"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	Probe.building(s, Vector2(150, 300))
	s.actor(&"you", &"player", Vector2(150, 450))
	s.switch(&"vision.enabled", true)
	s.von_down()
	s.declared_match({
		"defenders": { "count": 1, "at": [Vector2(900, 250)] },
		"invaders": { "count": 2, "at": [Vector2(800, 100), Vector2(800, 400)] },
		"human": { "actor": &"you", "side": &"defender" },
	})


func run(t: TestContext) -> void:
	await t.frames(3)
	var found := Probe.views(t)
	if not t.require(found.size() == 1, "one view in the match (%d found)" % found.size()):
		return
	var human := t.actor(&"you")
	t.check(found[0].viewer() == human, "the view is built for the human")
	var handle: Dictionary = t.world.match_handle
	t.check(handle.get("view") == found[0], "the match handle names the view")
	t.check(
		(handle.get("combatants", []) as Array).size() == 4,
		"premise: the match has the human and three NPCs (%d combatants)"
			% (handle.get("combatants", []) as Array).size(),
	)
