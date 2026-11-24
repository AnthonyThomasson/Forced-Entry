extends GameTest
## A living character at rest is carved out of the steering map like a piece of furniture: a path
## across the arena detours around a puppet standing on the straight line, the hole goes when it
## walks off (a walker leaves none), and a character that dies leaves no hole behind (a corpse is
## walked over). The world's own map, which the AI plans with, never has the characters in it.

## How far (px) a character's centre is, at the least, from the path across the arena: a character
## the path goes round is off it by a body's width and more.
const OFF_THE_LINE := 20.0
## The path's length (px) a path round a character is not shorter than: the straight line is 480,
## and the unoptimised path zigzags through the polygons' edges, so its length cannot tell a detour
## (a straight run measured 480 to 491.9, 493.8 round a character on the merged mesh, the ranges
## overlap): `OFF_THE_LINE` alone carries the detour, and this half only rules out no path (0) or
## one shorter than the line.
const BENT := 480.0


func describe() -> Dictionary:
	return {
		"name": "Characters are holes in the nav map",
		"description": "A puppet stands on the straight line: the nav path bends around it, "
			+ "straightens once it walks off (a walking character is no hole), and bends again "
			+ "around a second puppet that is then killed and leaves no hole.",
		"tags": ["navigation", "bake", "rebake", "character"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 300))
	s.switch(&"nav.rebake", true)
	s.actor(&"blocker", &"puppet", Vector2(300, 150))
	s.actor(&"victim", &"puppet", Vector2(300, 40), { "max_health": 10.0 })


func _path_length(t: TestContext, steering := true) -> float:
	var path := _path(t, steering)
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	return length


func _path(t: TestContext, steering := true) -> PackedVector2Array:
	var map := t.world.get_world_2d().navigation_map
	if steering:
		map = NavBuilder.steering_map(map)
	return NavPlan.path(map, Vector2(60, 150), Vector2(540, 150), false)


func _clearance(t: TestContext, at: Vector2) -> float:
	var path := _path(t)
	var least := INF
	for i in range(1, path.size()):
		var near := Geometry2D.get_closest_point_to_segment(at, path[i - 1], path[i])
		least = minf(least, near.distance_to(at))
	return least


func run(t: TestContext) -> void:
	var detours := func():
		var length := _path_length(t)
		t.trace("path_length", length)
		return length > BENT and _clearance(t, Vector2(300, 150)) > OFF_THE_LINE
	var straight := func():
		var length := _path_length(t)
		t.trace("path_length", length)
		return length > 0.0 and length < 500.0

	# The blocker stands on the straight line from the first frame; the updater carves it on its
	# first tick.
	t.check(
		await t.until(detours, 5.0),
		"the path detours around the standing character (%.1f px; 480 is straight)"
			% _path_length(t),
	)
	t.check(
		_path_length(t, false) < 500.0,
		"the planning map still runs straight through it (%.1f px)" % _path_length(t, false),
	)

	var blocker := t.puppet(&"blocker")
	blocker.walk_to(Vector2(300, 270))
	await t.seconds(0.3)
	t.expect_eq(
		NavBuilder.character_holes(t.world).size(),
		1,
		"only the standing character is a hole while the other walks",
	)
	t.check(
		await t.until(straight, 10.0),
		"the path straightens once the character has walked off the line (%.1f px)"
			% _path_length(t),
	)

	# A second character steps onto the line, then dies there: its body is no obstacle.
	var victim := t.puppet(&"victim")
	victim.walk_to(Vector2(300, 150))
	await t.until(victim.has_arrived, 5.0, "the second character never reached the line")
	t.check(
		await t.until(detours, 5.0),
		"the path detours around the second character (%.1f px)" % _path_length(t),
	)
	t.actor(&"victim").take_damage(100.0)
	t.check(t.actor(&"victim").is_dead, "the second character died")
	t.check(
		await t.until(straight, 10.0),
		"a dead character leaves no hole in the nav map (%.1f px)" % _path_length(t),
	)
