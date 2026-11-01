extends GameTest
## V10 (`docs/player-vision.md`): the test world's `vision.enabled` switch is off unless a test
## asks, so the tests and sandboxes that never mention it look as they do without a view. With it
## off and a `player` actor in the world there is no `PlayerView` and no SubViewport under the
## world, and `PlayerView.watch` itself builds none.
##
## It reads (tests/_vision/vision_probe.gd) the `PlayerView` nodes under the world.

const Probe := preload("res://tests/_vision/vision_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "The view is off unless a test switches it on",
		"description": "A player actor and the vision.enabled switch left alone: no PlayerView and "
			+ "no SubViewport under the world, and PlayerView.watch builds nothing.",
		"tags": ["vision"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	Probe.building(s, Vector2(150, 300))
	s.actor(&"you", &"player", Vector2(150, 450))


func run(t: TestContext) -> void:
	await t.frames(3)
	t.check(Probe.views(t).is_empty(), "no PlayerView under the world")
	t.check(
		t.world.find_children("*", "SubViewport", true, false).is_empty(),
		"no SubViewport under the world",
	)
	t.check(
		PlayerView.watch(t.world, t.actor(&"you")) == null,
		"PlayerView.watch builds nothing while the view is off",
	)
	t.check(Probe.views(t).is_empty(), "still no PlayerView after watch")
