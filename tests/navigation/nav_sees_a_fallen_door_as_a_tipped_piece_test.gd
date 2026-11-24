extends GameTest
## A door knocked down is a free body the nav bake sees as a tipped piece (#194 doors3d, D18,
## `docs/doors.md` DR11, interface 9): lying flat it is walk-over and leaves the map open, standing
## on its edge (leaning, a footprint over `DoorFallConfig.step_over` high) it is a hole carved
## where it stands, which the re-bake lands.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const DOORWAY := Vector2(400, 300)
const HINGE := Vector2(400, 280)
## How far (deg) the lying leaf is stood up on its edge for the leaning case.
const STOOD := 60.0
## How far (px) it is held up off the floor, clear of it.
const LIFT := 60.0
const WAIT := 12.0


func describe() -> Dictionary:
	return {
		"name": "The nav sees a fallen door as a tipped piece",
		"description": "A door lying flat leaves the floor under it open in the nav map; stood "
			+ "up on its edge it is carved out of the re-baked map where it stands.",
		"tags": ["navigation", "rebake", "door", "tipping", "3d"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 600) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 600) },
	], [{
		"pos": DOORWAY, "width": 52.0,
		"door": {
			"name": "felled", "material": "hollow", "style": "flush",
			"hinge": HINGE, "swing_into": Vector2.RIGHT,
		},
	}])
	s.switch(&"nav.rebake", true)
	s.von_down()


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var region: NavigationRegion3D = t.world.find_children(
		"NavRegion", "NavigationRegion3D", true, false,
	)[0]
	var map := region.get_navigation_map()
	if not t.require(NavBuilder.ready(map), "premise: the map answers"):
		return
	var door = t.object(&"felled")
	door.take_blow(&"kick", 1000.0, Vector2.RIGHT * 2200.0, 40.0)
	t.require(door.is_down(), "premise: the door is felled")
	t.require(await Probe.settle(t, door, 12.0), "premise: it lies at rest")
	t.require(Probe.lean(door) > 70.0, "premise: it lies flat (%.0f degrees)" % Probe.lean(door))
	var under := Probe.middle(door)
	await t.seconds(2.0)
	t.check(door.fallen_footprint().is_empty(), "lying flat it has no obstacle footprint")
	t.check(
		NavBuilder.snap(map, under).distance_to(under) < 1.0,
		"and the floor under it is open in the map (%s)" % under,
	)
	await _stand_up(t, door)
	var ring: PackedVector2Array = door.fallen_footprint()
	if not t.require(not ring.is_empty(), "standing on its edge it is an obstacle"):
		return
	var middle := Vector2.ZERO
	for corner in ring:
		middle += corner / ring.size()
	t.check(
		await t.until(
			func() -> bool: return NavBuilder.snap(map, middle).distance_to(middle) > 5.0, WAIT,
		),
		"the floor it stands on is carved out of the re-baked map (%s)" % middle,
	)


## The lying leaf turned about its long axis through its middle, so it stands on an edge, and held
## there (no gravity, no sleep): a leaf leaning on a wall or lying on a bed is that, and the test
## has neither.
func _stand_up(t: TestContext, door: Node2D) -> void:
	Knockback.push(door, Vector2(0.0, 5.0), Vector2.ZERO, -1.0)
	await t.frames(3)
	var lead := Probe.body(door)
	var lying := lead.global_transform
	var middle := lying * lead.center_of_mass
	var turn := Transform3D(Basis(lying.basis.x.normalized(), deg_to_rad(STOOD)), middle)
	lead.gravity_scale = 0.0
	lead.can_sleep = false
	lead.global_transform = turn * Transform3D(Basis.IDENTITY, -middle) * lying
	lead.global_position += Vector3.UP * LIFT
	await t.seconds(1.0)
