extends GameTest
## `SightRay.visible_parts(viewer, target)` and `visible_centre` (interface 11, #194 D9): which of a
## target's body points (head, chest, hips at its posture) the viewer's eye sees, the query the aim
## reads (a shot goes for the middle of the part that shows). A standing viewer looks at a ducked
## body behind a kitchen counter (38 px): its head (32 px, at the eye), chest (24 px) and hips (18
## px) clear the counter's shadow one after the other as it stands further behind it (the eye is 69
## px up and 350 px from the counter's far face, so the head shows from 66 px behind it, the chest
## from 156 and the hips from 225); a standing body in the open shows all three, at 69, 51 and 38
## px.

const VIEWER_AT := Vector2(200, 250)
const COUNTER_AT := Vector2(500, 250)
## The counter's far face (east), and how far behind it the target stands: none, the head, the head
## and chest, all three of a ducked body.
const FAR_FACE := 550.0
const BEHIND := [30.0, 110.0, 190.0, 290.0]
const SEEN := [0, 1, 2, 3]
## The heights (px) of a ducked body's points (0.76 m eye, a torso from 0.42 to 0.72 m, 42.3 px a
## metre) and of a standing one's (1.64 m, 0.90 to 1.52 m).
const DUCKED := [32.2, 24.1, 17.8]
const STANDING := [69.4, 51.2, 38.1]


func describe() -> Dictionary:
	return {
		"name": "A viewer sees the points of a body its eye has a clear line to",
		"description": "A ducked body behind a counter shows none, the head, the head and chest, "
			+ "then all three of its points as it stands further behind it; a standing body in the "
			+ "open shows head, chest and hips; the centre is the mean of what shows.",
		"tags": ["vision", "ai", "heights", "posture", "3d"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 500))
	s.switch(&"nav.rebake", false)
	s.object(&"counter", "kitchen_counter", COUNTER_AT)
	s.actor(&"viewer", &"puppet", VIEWER_AT)
	s.actor(&"target", &"puppet", Vector2(FAR_FACE + 30.0, 250))


func run(t: TestContext) -> void:
	var viewer := t.actor(&"viewer")
	var target := t.actor(&"target")
	t.require(
		await t.until(func(): return target.movement.set_posture(&"crouch"), 3.0),
		"premise: the target can duck",
	)
	await t.frames(3)
	for i in BEHIND.size():
		target.global_position = Vector2(FAR_FACE + BEHIND[i], 250)
		await t.frames(2)
		var seen := SightRay.visible_parts(viewer, target)
		t.check(
			seen.size() == SEEN[i],
			"%d px behind the counter %d of the ducked body's points show (%d)"
			% [BEHIND[i], SEEN[i], seen.size()],
		)
		for k in seen.size():
			t.expect_near(seen[k], DUCKED[k], 0.5, "the point %d is at its posture's height" % k)
	t.check(
		SightRay.visible_centre(viewer, target) > 0.0,
		"the middle of what shows is a height above the floor",
	)
	target.global_position = Vector2(FAR_FACE + BEHIND[0], 250)
	await t.frames(2)
	t.expect_near(SightRay.visible_centre(viewer, target), -1.0, 0.001, "hidden: no centre")
	target.global_position = Vector2(FAR_FACE + BEHIND[2], 250)
	await t.frames(2)
	t.expect_near(
		SightRay.visible_centre(viewer, target), 0.5 * (DUCKED[0] + DUCKED[1]), 0.5,
		"the middle of the head and the chest",
	)
	await _standing_in_the_open(t, viewer, target)


## A standing body away from the counter shows head, chest and hips.
func _standing_in_the_open(t: TestContext, viewer: Node2D, target: Node2D) -> void:
	t.require(
		await t.until(func(): return target.movement.set_posture(&"stand"), 3.0),
		"premise: the target stands up",
	)
	target.global_position = Vector2(300, 150)
	await t.frames(3)
	var seen := SightRay.visible_parts(viewer, target)
	t.check(seen.size() == 3, "a standing body in the open shows all three points")
	for k in mini(seen.size(), 3):
		t.expect_near(seen[k], STANDING[k], 0.5, "the point %d is at the standing height" % k)
