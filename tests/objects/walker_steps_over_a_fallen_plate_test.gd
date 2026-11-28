extends GameTest
## A plate on the floor is walked over (#194, D20, `docs/stacked-items.md`): a puppet that
## walks straight along a lane over a plate and a cup passes them and they stay where they lay, not
## shoved; a crate in the next lane (taller than a step) is shoved by the same walk.

const LANE_FREE := 120.0
const LANE_CRATE := 300.0
const SPOT := Vector2(360, LANE_FREE)
const CRATE_AT := Vector2(360, LANE_CRATE)


func describe() -> Dictionary:
	return {
		"name": "A walker steps over a plate and does not push it",
		"description": "A plate and a cup lie on the floor in a puppet's lane: it walks through "
			+ "them to the far side and they have not moved; the same walk shoves a crate "
			+ "lying in its lane.",
		"tags": ["items", "stacking", "character", "pushable", "twins"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 450))
	s.object(&"plate", "plate", SPOT)
	s.object(&"cup", "cup", SPOT + Vector2(14, 1))
	s.object(&"crate", "crate", CRATE_AT)
	s.actor(&"walker", &"puppet", Vector2(200, LANE_FREE))
	s.actor(&"pusher", &"puppet", Vector2(200, LANE_CRATE))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.seconds(1.0)
	t.puppet(&"walker").walk_to(Vector2(540, LANE_FREE))
	t.puppet(&"pusher").walk_to(Vector2(540, LANE_CRATE))
	t.check(
		await t.until(func(): return t.actor(&"walker").global_position.x > 440.0, 8.0),
		"the walker reached the far side of the plate and cup (x %.0f)"
			% t.actor(&"walker").global_position.x,
	)
	t.check(
		t.object(&"plate").global_position.distance_to(SPOT) < 0.5,
		"the plate stayed where it lay (%.2f px)"
			% t.object(&"plate").global_position.distance_to(SPOT),
	)
	t.check(
		t.object(&"cup").global_position.distance_to(SPOT + Vector2(14, 1)) < 0.5,
		"and so did the cup",
	)
	await t.seconds(2.0)
	t.check(
		t.object(&"crate").global_position.distance_to(CRATE_AT) > 4.0,
		"the crate in the other lane was shoved (%.1f px)"
			% t.object(&"crate").global_position.distance_to(CRATE_AT),
	)
