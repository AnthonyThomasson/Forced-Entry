extends GameTest
## The reach of an interaction is asked of the 3D twin space, not the 2D footprint (#194 chars3d-b):
## with the footprint's own shapes off (what the 2D space's deletion leaves), a chair a character
## stands beside is still the thing in reach, the gap from the mouse to it is the plan distance to
## its 3D shapes, and a chair out of reach is still out of it.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const CHAIR_AT := Vector2(300, 200)
const FAR_AT := Vector2(300, 400)


func describe() -> Dictionary:
	return {
		"name": "A chair is in reach by its 3D body, with its 2D footprint shapes off",
		"description": "The reachable chair is found and its gap measured through the twin space; "
			+ "a chair out of the 46 px reach is not found.",
		"tags": ["interaction", "chair", "reach", "3d"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 600))
	s.object(&"chair", "chair", CHAIR_AT)
	s.object(&"far", "chair", FAR_AT)
	s.actor(&"you", &"puppet", CHAIR_AT + Vector2(0.0, 40.0))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	var chair := t.object(&"chair")
	var far := t.object(&"far")
	await Probe.settle(t, chair, 5.0)
	var you := t.actor(&"you")
	you.global_position = chair.global_position + Vector2(0.0, 40.0)
	await t.frames(2)
	var reach: Array = you.use.interactions_in_reach()
	var found := reach.filter(func(e: Dictionary) -> bool: return e["object"] == chair)
	t.check(
		not found.is_empty(),
		"the chair is in reach through its 3D body (%d entries)" % reach.size(),
	)
	t.check(
		not reach.any(func(e: Dictionary) -> bool: return e["object"] == far),
		"the chair 200 px off is not",
	)
	you.movement.aim_point = chair.global_position + Vector2(0.0, 60.0)
	var gap := float(you.use.interact_target().get("entry", {}).get("gap", -1.0))
	var south_edge := _south_edge(chair)
	t.expect_near(
		gap, you.movement.aim_point.y - south_edge, 1.5,
		"the gap from the mouse is the plan distance to the 3D shapes (%.1f)" % gap,
	)


## The plan y of the south edge of the chair's 3D shapes.
func _south_edge(chair: Node2D) -> float:
	var twin := TwinSpace.twin_for(chair)
	var edge := -INF
	for shape: Node in twin.find_children("*", "CollisionShape3D", true, false):
		var box := (shape as CollisionShape3D).shape as BoxShape3D
		var corner := (shape as CollisionShape3D).global_transform * (box.size * 0.5)
		for sign_x in [-1.0, 1.0]:
			for sign_z in [-1.0, 1.0]:
				var at := (shape as CollisionShape3D).global_transform * (
					box.size * 0.5 * Vector3(sign_x, 0.0, sign_z)
				)
				edge = maxf(edge, at.z)
		edge = maxf(edge, corner.z)
	return edge
