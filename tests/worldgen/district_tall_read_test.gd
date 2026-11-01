extends GameTest
## A district's towers read as tall from above (#182): each throws a long hard shadow across the
## street (dragged away from the art light, on the street's light layer, beneath characters);
## concrete podium segments with pillars (solid, anchored) line the outside of its exterior walls,
## broken at every front and exit doorway with the door clearance; and an awning and a glyph sign
## hang over its front door and fade while a character stands under them. Read through the tower
## entries of `DistrictReads.get_towers` (`shadow`, `podium`, `awning`, `sign`).

const SEEDS := [1, 2, 3]
const ENTRANCE := Vector2(6000, 6000)
## A wall's half thickness (the plans' 12 px wall is centred on the room's edge).
const WALL_HALF := 6.0
## The podium's spec: no deeper than this past the wall's outer face, and clear of a doorway by
## its half width and this much each side.
const PODIUM_DEPTH := 24.0
const DOOR_GAP := 20.0
## The shadow: at least this far beyond the tower along each axis, and its opacity there.
const SHADOW_REACH := 100.0
const SHADOW_ALPHA_MIN := 0.3
## The awning fade: the spec's numbers.
const FADED_ALPHA := 0.25
const ALPHA_SLACK := 0.04
## A sign hangs this far from the door's centre, at least and at most.
const SIGN_NEAR := 30.0
const SIGN_FAR := 120.0
## Where the walker waits, clear of every tower's awning.
const AWAY := Vector2(100, 100)


func describe() -> Dictionary:
	return {
		"name": "A district's towers read as tall: shadow, podium band, awning and sign",
		"description": "Each tower has a long street shadow beyond its footprint, a solid anchored "
			+ "podium band along its exterior walls broken at the doorways, and an awning and a "
			+ "glyph sign over its front door that fade under a character.",
		"tags": ["worldgen", "district", "shadow", "podium", "awning"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.actor(&"walker", &"puppet", AWAY)


## The opacity `overhang` is drawn at: its own alpha times its ancestors' up to the world root.
func _alpha(overhang: CanvasItem) -> float:
	var alpha := 1.0
	var node: Node = overhang
	while node is CanvasItem:
		alpha *= (node as CanvasItem).modulate.a * (node as CanvasItem).self_modulate.a
		node = node.get_parent()
	return alpha


## The `Overhang` child of `piece`.
func _overhang(piece: Node) -> CanvasItem:
	return piece.find_child("Overhang", true, false) as CanvasItem


## The world rect `overhang` draws.
func _drawn(overhang: CanvasItem) -> Rect2:
	return overhang.get_global_transform() * (overhang as Object).call("get_rect") as Rect2


## The shadow sprite of `tower`: dark beyond the footprint on the away side, clear on it.
func _check_shadow(t: TestContext, label: String, tower: Dictionary) -> void:
	var sprite := tower.get("shadow") as Sprite2D
	if not t.require(sprite != null, "%s has a shadow sprite" % label):
		return
	var rect: Rect2 = tower["rect"]
	var image := sprite.texture.get_image()
	var scale := Vector2(image.get_size()) / sprite.texture.get_size()
	var area := Rect2(sprite.global_position, sprite.texture.get_size())
	t.check(area.end.x >= rect.end.x + SHADOW_REACH, "%s: shadow reaches past the tower" % label)
	t.check(area.end.y >= rect.end.y + SHADOW_REACH, "%s: shadow reaches down the street" % label)
	var far := rect.end + Vector2.ONE * 50.0
	var near := rect.get_center()
	t.check(_alpha_at(image, scale, area, far) >= SHADOW_ALPHA_MIN, "%s: dark beyond" % label)
	t.check(_alpha_at(image, scale, area, near) == 0.0, "%s: the footprint is clear" % label)
	t.check(sprite.light_mask == LightMasks.STREET, "%s: shadow on the street layer" % label)
	t.check(sprite.z_index < DrawLayers.STANDING, "%s: shadow beneath characters" % label)
	t.check(sprite.z_index > DrawLayers.FLOOR, "%s: shadow over the street floors" % label)


## The shadow's opacity at the world point `world` (0 outside its canvas).
func _alpha_at(image: Image, scale: Vector2, area: Rect2, world: Vector2) -> float:
	var at := Vector2i((world - area.position) * scale)
	if at.x < 0 or at.y < 0 or at.x >= image.get_width() or at.y >= image.get_height():
		return 0.0
	return image.get_pixelv(at).a


## Whether `seg` meets the open box of the doorway `door` on the outside: a wall's width plus the
## gap each side, a wall and a band deep.
func _blocks_door(seg: Rect2, door: Dictionary) -> bool:
	var out: Vector2 = door["outward"][0]
	var pos: Vector2 = door["pos"]
	var half: float = door["width"] * 0.5 + DOOR_GAP
	var span := Vector2(absf(out.y), absf(out.x)) * half + Vector2(absf(out.x), absf(out.y)) * 40.0
	var box := Rect2(pos + out * 20.0 - span, span * 2.0)
	return seg.intersects(box)


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
	var cover := _drawn(_overhang(awning))
	t.check(
		cover.has_point(door + (front["outward"][0] as Vector2) * 12.0),
		"%s: awning over the door" % label,
	)
	var gap := (_drawn(_overhang(sign_piece)).get_center() - door).length()
	t.check(gap > SIGN_NEAR and gap < SIGN_FAR, "%s: sign beside the door (%.0f px)" % [label, gap])


## A character stood under the awning of `tower` dims it, and it comes back when they leave.
func _check_fade(t: TestContext, tower: Dictionary) -> void:
	var overhang := _overhang(tower["awning"])
	var walker := t.actor(&"walker")
	t.check(
		absf(_alpha(overhang) - 1.0) <= ALPHA_SLACK,
		"the awning is opaque with no one under it",
	)
	walker.global_position = _drawn(overhang).get_center()
	await t.seconds(0.5)
	t.check(
		absf(_alpha(overhang) - FADED_ALPHA) <= ALPHA_SLACK,
		"the awning fades under a character",
	)
	walker.global_position = AWAY
	await t.seconds(0.5)
	t.check(absf(_alpha(overhang) - 1.0) <= ALPHA_SLACK, "the awning returns after they leave")


func run(t: TestContext) -> void:
	for district_seed in SEEDS:
		var district := WorldGen.generate_district(district_seed, "", ENTRANCE, t.world)
		var towers := DistrictReads.get_towers(district)
		_check_towers(t, "seed %d" % district_seed, towers)
		if district_seed == SEEDS[0]:
			await _check_fade(t, towers[DistrictLayout.HOUSE_BLOCK])
		district.queue_free()
		await t.frames(2)
	# Whatever house plan stands in the centre is dressed too.
	for plan: String in HouseDefinitions.get_all():
		var district := WorldGen.generate_district(SEEDS[0], plan, ENTRANCE, t.world)
		var house: Dictionary = DistrictReads.get_towers(district)[DistrictLayout.HOUSE_BLOCK]
		_check_towers(t, "plan %s" % plan, [house])
		district.queue_free()
		await t.frames(2)


## Every tower of `towers` reads as tall.
func _check_towers(t: TestContext, label: String, towers: Array) -> void:
	for tower: Dictionary in towers:
		var name := "%s tower %d" % [label, tower["block"]]
		_check_shadow(t, name, tower)
		_check_podium(t, name, tower)
		_check_hangings(t, name, tower)
