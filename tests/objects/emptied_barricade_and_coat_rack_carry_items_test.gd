extends GameTest
## D21 unbake (#194, `docs/stacked-items.md` SI15): the security barricade gives up
## its sandbags and the coat rack its hat: both are free items (rule 9) set where the old drawing
## had them, the piece is left bare (its mesh is the slab, or the post with its coats). The coats
## stay drawn on the rack (a coat hangs from a hook: no rest, a pin the twin space does not
## carry, SI15). Each item rests asleep, a shove moves one alone, a sandbag is no taller than a
## step and a rack's hat sits on its top.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const SecurityMesh := preload("res://scenes/objects/art/security_mesh.gd")
const BARRICADE_AT := Vector2(300, 250)
const RACK_AT := Vector2(600, 250)
## More racks: a rack's hat is a colour of the coat palette picked by where the rack stands.
const MORE_RACKS := [Vector2(660, 250), Vector2(720, 250), Vector2(780, 250), Vector2(840, 250)]
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
	for i in MORE_RACKS.size():
		s.object(StringName("rack_%d" % i), "coat_rack", MORE_RACKS[i])
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
	_check_slab_share(t, barricade)
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
	_check_top_bags(t, bags)
	_check_own_colour(t, bags, hats[0]["node"])
	_check_hat_colours(t)
	await _shove_one(t, bags, hats[0]["node"])


## The slab is what covers: 84 of the barricade's 120 px across (12 % in from each end plus the 4
## px its sandbag stacks end at, 0.70). `furniture_commercial_mesh` holds the barricade's cover to
## 0.65 of its width for that reason; the ends are bags, no cover for a ducked head.
func _check_slab_share(t: TestContext, barricade: Node2D) -> void:
	var slab := SecurityMesh.slab_of(FurnitureSpec.of(barricade))
	var share := slab.size.x / float(barricade.size.x)
	t.check(
		share >= 0.65 and share <= 0.75, "the slab is 0.65 to 0.75 of the width (%.2f)" % share
	)
	t.expect_eq(slab.size.x, 84.0, "the slab is 84 px across")


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


## The two small bags on the middle bags: 10 px up, 11 by 4 and 6 high, one over each stack.
func _check_top_bags(t: TestContext, bags: Array) -> void:
	var tops: Array = bags.filter(
		func(c: Dictionary) -> bool: return (c["node"].rest as PieceRest).lift > 5.0
	)
	t.expect_eq(tops.size(), 2, "two small bags sit on the stacks' middle bags")
	for c: Dictionary in tops:
		var bag: Node2D = c["node"]
		t.check(
			absf((bag.rest as PieceRest).lift - 10.0) < 1.0,
			"a small bag rests 10 px up, on a bag (%.1f)" % (bag.rest as PieceRest).lift,
		)
		var size := Vector2(bag.size)
		t.check(size.is_equal_approx(Vector2(11, 4)), "a small bag is 11 by 4 px (%s)" % size)
		t.check(
			is_equal_approx(float(bag.look.art_opts.get("height", 0.0)), 6.0),
			"a small bag is 6 px high",
		)


## A sandbag and the hat are drawn in their own colour, as the barricade's bags and the rack's hat
## were, not in the run-down grade a catalogue colour gets (`plain`, `ObjectArt._color`): a
## graded bag was drawn about a third darker than the old one.
func _check_own_colour(t: TestContext, bags: Array, hat: Node2D) -> void:
	for c: Dictionary in bags:
		var plain := bool(c["node"].look.art_opts.get("plain", false))
		t.check(plain, "a sandbag is drawn in its own colour")
	t.check(bool(hat.look.art_opts.get("plain", false)), "the hat is drawn in its own colour")


## A hat is a colour of the coat palette as the old hat was, picked by where its rack stands: the
## racks side by side do not all wear one.
func _check_hat_colours(t: TestContext) -> void:
	var palette: Array = ObjectArtDecorConfig.prop_colors["coats"]
	var seen := {}
	var racks: Array[Node2D] = [t.object(&"coat_rack")]
	for i in MORE_RACKS.size():
		racks.append(t.object(StringName("rack_%d" % i)))
	for rack in racks:
		var placed := RoomItems.carry(
			rack, ObjectDefinitions.get_definition("coat_rack"), t.world, "test"
		)
		var colour: Color = placed[0]["node"].color
		t.check(palette.has(colour), "a rack's hat is a coat colour (%s)" % colour.to_html(false))
		seen[colour] = true
	t.check(seen.size() >= 2, "racks wear hats of more than one colour (%d)" % seen.size())


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
