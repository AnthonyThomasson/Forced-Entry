extends GameTest
## A district's towers read as tall from above (#182): concrete podium segments with pillars (solid,
## anchored) line the outside of its exterior walls, broken at every front and exit doorway with the
## door clearance; and an awning and a glyph sign hang over its front door (the 3D render fades them
## while a character stands under them, `overhead_fade_test.gd`; the tower's shadow is the sun's).
## Read through the tower entries of `DistrictReads.get_towers` (`podium`, `awning`, `sign`).

const District := preload("res://tests/_worldgen/district_probe.gd")
const SEEDS := [1, 2, 3]
## A wall's half thickness (the plans' 12 px wall is centred on the room's edge).
const WALL_HALF := 6.0
## The podium's spec: no deeper than this past the wall's outer face, and clear of a doorway by
## its half width and this much each side.
const PODIUM_DEPTH := 24.0
## The band stands clear of a doorway by room for an entry stack's slots past the jamb: three
## bodies about 44 px apart along the wall (`docs/tactical-entry.md`), 132 px.
const DOOR_GAP := 132.0
## A segment is on a doorway's face when it stands out from the wall as a band does, give or take
## this much (px).
const ON_FACE := 14.0
## A sign hangs this far from the door's centre, at least and at most.
const SIGN_NEAR := 30.0
const SIGN_FAR := 120.0


func describe() -> Dictionary:
	return {
		"name": "A district's towers read as tall: podium band, awning and sign",
		"description": "Each tower has a solid anchored podium band along its exterior walls "
			+ "broken at the doorways, and an awning and a glyph sign over its front door.",
		"tags": ["worldgen", "district", "podium", "awning"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


## The world rect the overhang of `piece` covers (its `look.overhang_rect()` in the piece's frame).
func _drawn(piece: Node2D) -> Rect2:
	return piece.global_transform * (piece.look.overhang_rect() as Rect2)


## Whether `seg` stands in the way of the doorway `door`: on the same face of the tower (its centre
## one wall half thickness and half a band out from the door's wall line, give or take `ON_FACE`),
## and nearer along the wall than the door's half width plus the gap each side.
func _blocks_door(seg: Rect2, door: Dictionary) -> bool:
	var out: Vector2 = door["outward"][0]
	var pos: Vector2 = door["pos"]
	var out_of_wall := (seg.get_center() - pos).dot(out)
	if absf(out_of_wall - (WALL_HALF + PODIUM_DEPTH * 0.5)) > ON_FACE:
		return false
	var along := Vector2(absf(out.y), absf(out.x))
	var centre := pos.dot(along)
	var half: float = door["width"] * 0.5 + DOOR_GAP
	return seg.position.dot(along) < centre + half and seg.end.dot(along) > centre - half


## The podium band of `tower`: solid, anchored, outside the walls and against them, clear of the
## front and exit doorways, with some on every side.
func _check_podium(t: TestContext, label: String, tower: Dictionary) -> void:
	var segs: Array = tower.get("podium", [])
	if not t.require(not segs.is_empty(), "%s has podium segments" % label):
		return
	var rooms: Array = WorldGen.get_rooms(tower["node"])
	var doors := WorldGen.get_openings(tower["node"]).filter(
		func(o: Dictionary) -> bool: return o["front"] or o["exit"],
	)
	for seg: Node2D in segs:
		var piece := seg as Node2D
		var rect := _piece_rect(piece)
		t.check(
			piece.get("anchored") == true and piece.get("solid") == true,
			"%s: podium solid, anchored" % label,
		)
		t.check(_outside_rooms(rect, rooms), "%s: a podium segment sits in a wall" % label)
		t.check(_abuts_a_room(rect, rooms), "%s: a podium segment floats off the tower" % label)
		for door: Dictionary in doors:
			t.check(not _blocks_door(rect, door), "%s: podium in a doorway's way" % label)
	for side in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		t.check(_has_on_side(segs, tower["rect"], side), "%s: no podium on the %s" % [label, side])


## The world rect `piece` covers.
func _piece_rect(piece: Node2D) -> Rect2:
	var size: Vector2 = piece.get("size")
	return Rect2(piece.global_position - size * 0.5, size)


## Whether `rect` stands clear of every room's wall (a wall reaches `WALL_HALF` past a room's rect).
func _outside_rooms(rect: Rect2, rooms: Array) -> bool:
	for room: Dictionary in rooms:
		if rect.intersects((room["rect"] as Rect2).grow(WALL_HALF - 0.5)):
			return false
	return true


## Whether `rect` lies against some room's wall: within the wall and a podium's depth of it.
func _abuts_a_room(rect: Rect2, rooms: Array) -> bool:
	for room: Dictionary in rooms:
		if rect.intersects((room["rect"] as Rect2).grow(WALL_HALF + PODIUM_DEPTH)):
			return true
	return false


## Whether some segment of `segs` lies out past the `side` face of `bounds`.
func _has_on_side(segs: Array, bounds: Rect2, side: Vector2) -> bool:
	var face := bounds.end if side.x + side.y > 0.0 else bounds.position
	for seg: Node2D in segs:
		if _piece_rect(seg).get_center().dot(side) >= face.dot(side):
			return true
	return false


## The awning over the front door and the sign beside it.
func _check_hangings(t: TestContext, label: String, tower: Dictionary) -> void:
	var front: Dictionary = tower["front"]
	var door: Vector2 = front["pos"]
	var awning := tower.get("awning") as Node2D
	var sign_piece := tower.get("sign") as Node2D
	if not t.require(awning != null and sign_piece != null, "%s has an awning and a sign" % label):
		return
	var cover := _drawn(awning)
	t.check(
		cover.has_point(door + (front["outward"][0] as Vector2) * 12.0),
		"%s: awning over the door" % label,
	)
	var gap := (_drawn(sign_piece).get_center() - door).length()
	t.check(gap > SIGN_NEAR and gap < SIGN_FAR, "%s: sign beside the door (%.0f px)" % [label, gap])


func run(t: TestContext) -> void:
	for district_seed in SEEDS:
		var district := WorldGen.generate_district(district_seed, "", District.ENTRANCE, t.world)
		var towers := DistrictReads.get_towers(district)
		_check_towers(t, "seed %d" % district_seed, towers)
		district.queue_free()
		await t.frames(2)
	_check_every_front_dressed(t)
	# Whatever house or tower plan stands in the centre is dressed too: every front door has its
	# awning and its sign.
	for plan: String in HouseDefinitions.get_all() + TowerDefinitions.get_all():
		var district := WorldGen.generate_district(SEEDS[0], plan, District.ENTRANCE, t.world)
		var house: Dictionary = DistrictReads.get_towers(district)[District.HOUSE_BLOCK]
		_check_towers(t, "plan %s" % plan, [house])
		district.queue_free()
		await t.frames(2)


## Every tower plan, turned each of the four ways and dressed, has an awning over its front door and
## a sign beside it (the dressing leaves no front door bare whichever wall runs it has).
func _check_every_front_dressed(t: TestContext) -> void:
	for plan: String in TowerDefinitions.get_all():
		for turn in 4:
			var rng := RandomNumberGenerator.new()
			rng.seed = SEEDS[0]
			var node := HouseSpawner.spawn(
				plan,
				District.ENTRANCE,
				rng,
				t.world,
				{ "turn": turn, "street": false },
			)
			var rooms := WorldGen.get_rooms(node)
			var fronts := WorldGen.get_openings(node).filter(
				func(o: Dictionary) -> bool: return o["front"],
			)
			var dressing := TowerDressing.dress(
				{
					"plan": plan,
					"turn": turn,
					"node": node,
					"rect": WorldGen.bounds(rooms),
					"front": fronts[0],
				},
			)
			t.check(
				dressing.get("awning") != null and dressing.get("sign") != null,
				"%s turned %d: its front door has an awning and a sign" % [plan, turn],
			)
			node.queue_free()


## Every tower of `towers` reads as tall.
func _check_towers(t: TestContext, label: String, towers: Array) -> void:
	for tower: Dictionary in towers:
		var name := "%s tower %d" % [label, tower["block"]]
		_check_podium(t, name, tower)
		_check_hangings(t, name, tower)
