extends GameTest
## #194 rule 5 (docs/gaze-and-fire.md W2): an NPC aims at where it last knew its target, not where
## the target is. The gate to fire reads `SightRay.aim_at(viewer, eye, target, at)` with `at` the
## last-known point, so it cannot leak the body's real position. A standing target 300 px from the
## viewer, in the open, shows all of itself (the aim is the middle of its three points); the point
## 200 px away, behind a 60 px table, shows only the head (the aim is the head's height), whichever
## of the two the body stands at. And a shooter that fires from a pose risen over cover aims from
## the eye of that pose.

const Hiding := preload("res://tests/_ai/hiding_piece.gd")
const VIEWER := Vector2(100, 300)
const TABLE := Vector2(300, 300)
const BEHIND_TABLE := Vector2(500, 300)
const IN_THE_OPEN := Vector2(500, 450)


func describe() -> Dictionary:
	return {
		"name": "An NPC's aim comes from where it last knew the target, not where it stands",
		"description": "aim_at for a point behind a low table is the head's height while the body "
			+ "stands in the open elsewhere (aim_height there is the middle of all three points).",
		"tags": ["ai", "perception", "aim", "heights", "3d"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.switch(&"nav.rebake", false)
	s.object(&"table", Hiding.low_cover("coffee_table", 60.0), TABLE)
	s.actor(&"viewer", &"puppet", VIEWER)
	s.actor(&"target", &"puppet", IN_THE_OPEN)


func run(t: TestContext) -> void:
	await t.frames(3)
	var viewer := t.actor(&"viewer")
	var target := t.actor(&"target")
	var points := BodyHeights.sight_points(BodyHeights.STAND)
	var eye := BodyHeights.eye(BodyHeights.STAND)
	var middle := 0.0
	for height in points:
		middle += height / points.size()
	t.expect_near(
		SightRay.aim_height(viewer, target),
		middle,
		0.5,
		"in the open the real body shows all its points: the aim is their middle",
	)
	t.expect_near(
		SightRay.aim_at(viewer, eye, target, BEHIND_TABLE),
		points[0],
		0.5,
		"from the last-known point behind the table only the head shows: the aim is the head's",
	)
	t.expect_near(
		SightRay.aim_at(viewer, eye, target, IN_THE_OPEN),
		middle,
		0.5,
		"and from the point it stands at, the middle again",
	)
	t.expect_near(
		SightRay.aim_at(viewer, BodyHeights.eye(BodyHeights.DUCK), target, BEHIND_TABLE),
		points[1],
		0.5,
		"a ducked eye sees none of it over the table: the aim is the chest, from the eye it has",
	)
