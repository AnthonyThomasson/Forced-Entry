extends GameTest
## D19 (#194, `docs/doors.md` DR11): a leaf is walk-over only while it lies flat (its top
## within a step over of the floor). One blown up or propped on its edge past that is a solid again:
## a walker meets it. The leaf lies flat in the open room: a line at shin height of the layers a
## walker is stopped by passes over it; stood on its edge it is met.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const DOORWAY := Vector2(400, 300)
const HINGE := Vector2(400, 280)
const LIES_AT := Vector2(1000, 500)
## The height (px) a walker's shin meets a thing at.
const SHIN := 3.0
## How far (px) the standing leaf's foot is lifted off the floor.
const FOOT := 1.0


func describe() -> Dictionary:
	return {
		"name": "A flat door stood on its edge again blocks a walker",
		"description": "A hollow door lying flat is walked over; the same leaf stood up past a "
			+ "step over is solid again: a walker's line meets it.",
		"tags": ["door", "objects", "3d", "walkover"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 800) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 1200, 800) },
	], [{
		"pos": DOORWAY, "width": 52.0,
		"door": {
			"name": "felled", "material": "hollow", "style": "flush",
			"hinge": HINGE, "swing_into": Vector2.RIGHT,
		},
	}])
	s.von_down()


func run(t: TestContext) -> void:
	await t.frames(3)
	var door = t.object(&"felled")
	door.take_blow(&"kick", 1000.0, Vector2.RIGHT * 2200.0, 30.0)
	t.require(door.is_down(), "premise: the kick fells the door")
	t.require(await Probe.settle(t, door, 12.0), "premise: it comes to rest")
	var lead := Probe.body(door)
	lead.global_position = PlanSpace.lift(LIES_AT, 4.0)
	lead.linear_velocity = Vector3.ZERO
	lead.angular_velocity = Vector3.ZERO
	lead.sleeping = false
	t.require(await Probe.settle(t, door, 12.0), "premise: it lies at rest in the open")
	var along := PhysicsLayers.TWIN_BLOCKS
	t.check(
		not _walker_meets(t, door, along),
		"the leaf lying flat is no obstacle: a walker's line passes over it",
	)
	# the leaf is stood on its edge: its top is far past a step over, and it tips back over
	# slowly enough for the frames the check takes
	lead.global_transform = Transform3D(Basis(), PlanSpace.lift(LIES_AT, FOOT))
	lead.linear_velocity = Vector3.ZERO
	lead.angular_velocity = Vector3.ZERO
	lead.sleeping = false
	await t.frames(2)
	t.require(
		Probe.top(door) > 40.0,
		"premise: the leaf stands (top %.0f px, layer %d)" % [
			Probe.top(door),
			lead.collision_layer,
		],
	)
	t.check(
		_walker_meets(t, door, along),
		"the leaf stood up past a step over is a solid again: a walker's line meets it (layer %d)"
			% lead.collision_layer,
	)


## Whether a line at a walker's shin height (`along`: the layers a walker is stopped by) across the
## leaf's middle meets `door`.
func _walker_meets(t: TestContext, door: Node2D, along: int) -> bool:
	var at: Vector2 = Probe.middle(door)
	var query := PhysicsRayQueryParameters3D.create(
		PlanSpace.lift(at + Vector2(0.0, 60.0), SHIN),
		PlanSpace.lift(at - Vector2(0.0, 60.0), SHIN),
		along,
	)
	var hit: Dictionary = t.world.twin_space().space().intersect_ray(query)
	return not hit.is_empty() and TwinSpace.owner_of(hit["collider"]) == door
