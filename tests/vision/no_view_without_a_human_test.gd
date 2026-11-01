extends GameTest
## V8 (`docs/player-vision.md`): Watch and Endless have no human, so the view is not built and
## everything is drawn as today. A declared match with no human, the view switched on, has no view
## and its handle names none.
##
## It reads (tests/_vision/vision_probe.gd) the `PlayerView` nodes under the world and the match
## handle's `view`.

const Probe := preload("res://tests/_vision/vision_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A match with no human has no view",
		"description": "A declared match with only NPCs, the view switched on, builds no view.",
		"tags": ["vision", "match"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	Probe.building(s, Vector2(150, 300))
	s.switch(&"vision.enabled", true)
	s.von_down()
	s.declared_match({
		"defenders": { "count": 1, "at": [Vector2(900, 250)] },
		"invaders": { "count": 1, "at": [Vector2(800, 100)] },
	})


func run(t: TestContext) -> void:
	await t.frames(3)
	var handle: Dictionary = t.world.match_handle
	if not t.require((handle.get("combatants", []) as Array).size() == 2, "premise: two NPCs"):
		return
	t.check(Probe.views(t).is_empty(), "no view in the match (%d found)" % Probe.views(t).size())
	t.check(handle.get("view") == null, "the match handle names no view")
