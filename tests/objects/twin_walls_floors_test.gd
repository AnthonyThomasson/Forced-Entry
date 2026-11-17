extends GameTest
## The 3D twins of the structure (`ObjectTwins`, interface 29): a wall stands 96 px tall (the
## render's wall), so a ray flown level at 90 px strikes it and one at 100 px passes over; a ray
## dropped on its top lands at 96 and maps back to the wall. The floor is a slab at the ground a ray
## dropped in the room lands on, and maps back to the floor.

const Probe := preload("res://tests/_general/twin_probe.gd")
const ARENA := Rect2(0, 0, 800, 500)
## A wall stands this high (px).
const WALL_TOP := 96.0


func describe() -> Dictionary:
	return {
		"name": "A wall's twin is 96 px tall and a floor's a slab at the ground",
		"description": "A level ray at 90 px hits the arena's wall, one at 100 px clears it; a "
			+ "ray dropped on the wall's top lands at 96 and names the wall; one dropped in the "
			+ "room lands on the floor.",
		"tags": ["twins", "3d", "heights", "walls", "floors"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(ARENA)


func run(t: TestContext) -> void:
	await t.frames(3)
	var wall := _wall(t)
	if not t.require(wall != null, "premise: the arena has a wall"):
		return
	var shape := _shape_of(wall)
	var at := shape.global_position
	var inward := (ARENA.get_center() - at).normalized()
	var top := Probe.down(t, at)
	t.check(top.get("owner") == wall, "a ray dropped on the wall finds the wall")
	t.expect_near(Probe.top_at(t, at), WALL_TOP, 0.5, "the wall's top is 96 px up")
	var low := Probe.level(t, at + inward * 60.0, at - inward * 60.0, 90.0)
	t.check(low.get("owner") == wall, "a ray at 90 px strikes the wall")
	var high := Probe.level(t, at + inward * 60.0, at - inward * 60.0, 100.0)
	t.check(high.is_empty(), "a ray at 100 px passes over the wall")
	var floor_hit := Probe.down(t, ARENA.get_center())
	t.check(
		floor_hit.get("owner") != null and (floor_hit["owner"] as Node).is_in_group(&"floors"),
		"a ray dropped in the room lands on the floor",
	)
	t.expect_near(Probe.top_at(t, ARENA.get_center()), 0.0, 0.5, "the floor is at the ground")


## The first wall of the arena.
func _wall(t: TestContext) -> Node2D:
	for node in t.world.find_children("*", "StaticBody2D", true, false):
		if node.get("wall_thickness") != null:
			return node
	return null


## The first rectangle collider of `wall`.
func _shape_of(wall: Node2D) -> CollisionShape2D:
	for child in wall.get_children():
		if child is CollisionShape2D:
			return child
	return null
