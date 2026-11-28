extends GameTest
## A swinging door goes over what a walker goes over (#194, D20, `docs/stacked-items.md`
## SI4): a door opened wide shuts over a plate lying in its way (a walk-over item is no obstacle to
## the leaf, which is not scraped to a stop by it), still stops at a crate in its way, and still
## stops at a fallen door's leaf lying in its way (a leaf on the walk-over layer too, but a door,
## not an item).

const Probe := preload("res://tests/_objects/piece_probe.gd")
const WIDTH := 52.0
const JAMB := 20.0
## The doorways' rows (y) along the wall at x = 400.
const PLATE_ROW := 100.0
const CRATE_ROW := 300.0
const LEAF_ROW := 500.0
const FELLED_ROW := 700.0
## How far open (degrees) the leaf is when it is over what is in its way.
const OVER := 45.0
const SWING := 3.0


func describe() -> Dictionary:
	return {
		"name": "A door shuts over a plate but stops at a crate and at a fallen leaf",
		"description": "Three doors opened wide with something lying in the quarter circle "
			+ "they close through: the door with a plate shuts; the one with a crate, and the "
			+ "one with a fallen door's leaf lying there, stop short of shut.",
		"tags": ["door", "objects", "3d", "items", "stacking"],
		"timeout": 40.0,
	}


func _doorway(y: float, id: String) -> Dictionary:
	return {
		"pos": Vector2(400, y), "width": WIDTH,
		"door": {
			"name": id, "material": "hollow", "style": "flush",
			"hinge": Vector2(400, y - JAMB), "swing_into": Vector2.RIGHT,
		},
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 800) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 800) },
	], [
		_doorway(PLATE_ROW, "plated"),
		_doorway(CRATE_ROW, "crated"),
		_doorway(LEAF_ROW, "leafed"),
		_doorway(FELLED_ROW, "felled"),
	])
	s.switch(&"nav.rebake", false)
	s.von_down()


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var plated = t.object(&"plated")
	var crated = t.object(&"crated")
	var leafed = t.object(&"leafed")
	for door in [plated, crated, leafed]:
		door.open_fully(null)
	await t.seconds(DoorConfig.swing_time + 0.5)
	for door in [plated, crated, leafed]:
		t.require(
			door.angle() > 80.0,
			"premise: %s is open wide (%.0f)" % [door.name, door.angle()],
		)
	# a plate, a crate and a fallen leaf in the quarter circle each leaf will close through
	var parent: Node = plated.get_parent()
	ObjectFactory.spawn(WorldGen.object_definition("plate"), _over(plated), parent)
	ObjectFactory.spawn(WorldGen.object_definition("crate"), _over(crated), parent)
	var felled = t.object(&"felled")
	felled.take_blow(&"kick", 1000.0, Vector2.RIGHT * 4000.0, 40.0)
	t.require(felled.is_down(), "premise: the fourth door is felled")
	t.require(await Probe.settle(t, felled, 12.0), "premise: its leaf comes to rest")
	var slab: RigidBody3D = Probe.body(felled)
	t.require(Probe.top(felled) <= DoorFallConfig.step_over, "premise: the leaf lies flat")
	slab.global_position += PlanSpace.lift(_over(leafed) - Probe.middle(felled), 0.0)
	slab.linear_velocity = Vector3.ZERO
	slab.angular_velocity = Vector3.ZERO
	slab.sleeping = false
	t.require(await Probe.settle(t, felled, 6.0), "premise: the leaf rests where it was put")
	for door in [plated, crated, leafed]:
		door.toggle(null)
	await t.seconds(DoorConfig.swing_time + 1.0)
	t.check(
		plated.angle() < 1.0,
		"the door with a plate in its way shut (%.1f degrees)" % plated.angle(),
	)
	t.check(
		crated.angle() > SWING,
		"the door with a crate in its way stopped at it (%.1f)" % crated.angle(),
	)
	t.check(
		leafed.angle() > SWING,
		"the door with a fallen leaf in its way stopped at it (%.1f)" % leafed.angle(),
	)


## The middle of the leaf of `door` when it stands `OVER` degrees open.
func _over(door: Node2D) -> Vector2:
	return door.leaf_pose(OVER).origin
