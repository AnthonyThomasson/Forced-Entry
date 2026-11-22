extends GameTest
## D21 unbake (#194 17i `unbake-d`, `docs/stacked-items.md` SI15): the security barricade gives up
## its sandbags and the coat rack its hat: both are free items (rule 9) set where the old drawing
## had them, the piece is left bare (its mesh is the slab, or the post with its coats). The coats
## stay drawn on the rack (a coat hangs from a hook: no rest, a pin the twin space does not
## carry, SI15). Each item rests asleep, a shove moves one alone, a sandbag is no taller than a
## step and a rack's hat sits on its top.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const BARRICADE_AT := Vector2(300, 250)
const RACK_AT := Vector2(600, 250)
## Where the old painter put each bag: px from the barricade's centre, the front toward +y (the
## bags' rect centres: `security_painter.gd`: `at + (k % 2) * 3`, `1 + k * 8`, 15 by 8).
const BAGS := [
	Vector2(-52.5, -9), Vector2(-49.5, -1), Vector2(-52.5, 7),
	Vector2(51.5, -9), Vector2(54.5, -1), Vector2(51.5, 7),
]


func describe() -> Dictionary:
	return {
		"name": "An emptied barricade carries its sandbags and a coat rack its hat as items",
		"description": "The barricade is the bare slab and carries eight sandbag items where the "
			+ "painter drew them (two stacks of three, a small bag on each middle one); the coat "
			+ "rack's mesh has no hat and carries a hat item on its top; all rest asleep.",
		"tags": ["furniture", "3d", "items", "stacking", "unbake"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.object(&"barricade", "barricade", BARRICADE_AT)
	s.object(&"coat_rack", "coat_rack", RACK_AT)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var barricade: Node2D = t.object(&"barricade")
	var rack: Node2D = t.object(&"coat_rack")
	t.check(
		_mesh_of(barricade).get_aabb().size.x < barricade.size.x - 20.0,
		"the barricade's mesh is the bare slab, no sandbag at its ends",
	)
	t.check(
		absf(_mesh_of(rack).get_aabb().end.y - ObjectMeshDecorConfig.coat_rack_height) < 0.5,
		"the coat rack's mesh stops at its post, no hat on it",
	)
	var bags := RoomItems.carry(
		barricade, ObjectDefinitions.get_definition("barricade"), t.world, "test"
	)
	t.expect_eq(bags.size(), 8, "the barricade carries eight sandbags")
	var hats := RoomItems.carry(
		rack, ObjectDefinitions.get_definition("coat_rack"), t.world, "test"
	)
	t.expect_eq(
		hats.map(func(c: Dictionary) -> String: return c["key"]), ["hat"], "the rack carries a hat"
	)
	await t.seconds(2.5)
	_check_bags(t, bags)
	_check_hat(t, hats[0]["node"])
	await _shove_one(t, bags, hats[0]["node"])


## Every bag asleep, no higher than a step on the floor, and one stands at each drawn spot.
func _check_bags(t: TestContext, bags: Array) -> void:
	t.check(
		ObjectMeshStockItemConfig.sandbag_height <= DoorFallConfig.step_over,
		"a sandbag on the floor is no higher than a step (a walker steps over it)",
	)
	for c: Dictionary in bags:
		t.expect_eq(c["key"], "sandbag", "a barricade carries sandbags only")
		t.check(Probe.asleep(c["node"]), "a sandbag rests asleep")
	for want: Vector2 in BAGS:
		var found := false
		for c: Dictionary in bags:
			var at := (c["node"] as Node2D).global_position - BARRICADE_AT
			found = found or at.distance_to(want) < 1.5
		t.check(found, "a sandbag stands where the painter drew one (%s)" % want)


## The hat asleep on the post's top, over its centre.
func _check_hat(t: TestContext, hat: Node2D) -> void:
	var top := ObjectMeshDecorConfig.coat_rack_height
	t.check(Probe.asleep(hat), "the hat rests asleep")
	t.check(
		Probe.centre(hat) > top - 0.5 and Probe.centre(hat) < top + 6.0,
		"the hat rests on the rack's top (%.1f over %.1f)" % [Probe.centre(hat), top],
	)
	t.check(
		hat.global_position.distance_to(RACK_AT) < 2.0, "the hat is on the post (over its centre)"
	)


## A shove on one bag moves that bag alone: the other bags and the hat stay.
func _shove_one(t: TestContext, bags: Array, hat: Node2D) -> void:
	var first: Node2D = bags[0]["node"]
	var before: Array = bags.map(func(c: Dictionary) -> Vector2: return c["node"].global_position)
	var at_hat := hat.global_position
	Knockback.push(first, Vector2(0.0, -900.0), Vector2.ZERO, 5.0)
	await t.seconds(0.6)
	t.check(first.global_position.distance_to(before[0]) > 3.0, "the shoved sandbag moved")
	for i in range(1, bags.size()):
		var node: Node2D = bags[i]["node"]
		t.check(node.global_position.distance_to(before[i]) < 0.5, "sandbag %d stayed" % i)
	t.check(hat.global_position.distance_to(at_hat) < 0.5, "the hat did not move with it")


## The mesh the piece's rig builds, unshown: the body mesh.
func _mesh_of(piece: Node2D) -> ArrayMesh:
	var rig: FurnitureRig = ObjectMeshes.BUILDERS[piece.look.art].build(piece)
	var mesh := rig.body.mesh as ArrayMesh
	rig.free()
	return mesh
