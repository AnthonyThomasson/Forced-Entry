extends GameTest
## The streets of a district (#182): its floors are the street's (no sound surface, the street light
## layer, one shared tile grid); every arm of every junction has a worn zebra crossing with its stop
## line and, on the approach, a lane number and an arrow; street lamps stand along every sidewalk,
## every other one a neon sign, none within 140 px of any tower's front or exit doorway or in the
## strip straight out of one; and grimy-steel clutter lines the sidewalks (vending machines and
## benches solid and anchored, bins solid and pushable, drain grates and litter walk-over), none
## meeting a doorway zone, a lamp, a crossing or a tower. Read through `DistrictReads` and
## `WorldGen.get_streetlights` / `get_clutter` on the district root.

const SEEDS := [1, 2, 3]
const ENTRANCE := Vector2(6000, 6000)
const DIRS := [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
## The lamps' door rule and spacing (ticket #61): the spec's numbers.
const DOOR_CLEAR := 140.0
const STRIP_MARGIN := 32.0
const STRIP_REACH := 400.0
const LAMP_GAP_MIN := 160.0
## The sidewalk kept clear past a crossing's ends (at least this much) and a tower's body: its
## wall (6) and the podium band (20) round its rooms.
const SIDEWALK := 64.0
const TOWER_BODY := 26.0
## Clutter by catalogue key: solid, anchored.
const CLUTTER := {
	"vending_machine": [true, true],
	"street_bench": [true, true],
	"street_bin": [true, false],
	"drain_grate": [false, false],
	"litter": [false, false],
}


func describe() -> Dictionary:
	return {
		"name": "A district's streets: crossings, lane glyphs, lamps and sidewalk clutter",
		"description": "The street floors are the street's; every junction arm has a crossing and "
			+ "an approach glyph; lamps line the sidewalks clear of every doorway; clutter keeps "
			+ "off doorways, lamps, crossings and towers.",
		"tags": ["worldgen", "district", "street", "streetlight", "crossing", "clutter"],
		"timeout": 180.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


## The marks layer of street piece `piece`'s floor.
func _marks(piece: Dictionary) -> Node:
	return piece["node"].get_node_or_null("FloorVisuals/StreetMarks")


## The road piece of `streets` that touches `junction` on its side `d` (the piece lies that way).
func _arm(streets: Array, junction: Rect2, d: Vector2) -> Dictionary:
	for piece: Dictionary in streets:
		if piece["role"] != "road":
			continue
		var r: Rect2 = piece["rect"]
		var meets := (
			absf(r.end.x - junction.position.x) < 0.5 if d == Vector2.LEFT
			else absf(r.position.x - junction.end.x) < 0.5 if d == Vector2.RIGHT
			else absf(r.end.y - junction.position.y) < 0.5 if d == Vector2.UP
			else absf(r.position.y - junction.end.y) < 0.5
		)
		var level := (
			absf(r.position.y - junction.position.y) < 0.5 if d.x != 0.0
			else absf(r.position.x - junction.position.x) < 0.5
		)
		if meets and level:
			return piece
	return {}


## Whether `piece`'s marks hold an entry of `key` (`crossings` or `glyphs`) facing `side`.
func _has_mark(piece: Dictionary, key: String, side: Vector2) -> bool:
	var entries: Array = piece["node"].marks.get(key, [])
	return entries.any(func(e: Dictionary) -> bool: return e["side"] == side)


## The floors: the street's own, on one tile grid.
func _check_floors(t: TestContext, label: String, streets: Array) -> void:
	var origins := {}
	for piece: Dictionary in streets:
		var floor_node: Node2D = piece["node"]
		t.check(
			not floor_node.sound_surface and floor_node.light_layer == "street",
			"%s: %s is not a street floor (no sound surface, street light layer)"
				% [label, floor_node.name],
		)
		origins[floor_node.position - floor_node.tile_offset] = true
	t.check(
		origins.size() == 1,
		"%s: the street floors share %d tile grids" % [label, origins.size()],
	)


## Every arm of every junction: a crossing and an approach glyph, laid in the arm's road.
func _check_arms(t: TestContext, label: String, streets: Array) -> void:
	var arms := 0
	var junctions := streets.filter(func(s: Dictionary) -> bool: return s["role"] == "junction")
	for junction: Dictionary in junctions:
		for d: Vector2 in DIRS:
			var road := _arm(streets, junction["rect"], d)
			if road.is_empty():
				continue
			arms += 1
			var toward := -d
			var at := "%s: the arm %s of the junction at %s" % [
				label,
				d,
				(junction["rect"] as Rect2).position,
			]
			t.check(_has_mark(road, "crossings", toward), "%s has no crossing" % at)
			t.check(_has_mark(road, "glyphs", toward), "%s has no lane glyph" % at)
			_check_laid(t, at, road, toward)
	t.check(arms == 48, "%s: %d junction arms, not 48" % [label, arms])
	var crossings := 0
	for piece: Dictionary in streets:
		crossings += (piece["node"].marks.get("crossings", []) as Array).size()
	t.check(crossings == arms, "%s: %d crossings for %d arms" % [label, crossings, arms])


## The index of the entry of `key` in `piece`'s marks facing `side` (-1 for none).
func _entry(piece: Dictionary, key: String, side: Vector2) -> int:
	var entries: Array = piece["node"].marks.get(key, [])
	for i in entries.size():
		if entries[i]["side"] == side:
			return i
	return -1


## The road `road`'s marks layer drew the crossing and the glyph of its end facing `toward`: the
## glyph in the lane that approaches the junction (the right of the way to it), clear of the
## crossing. The layer lays its marks in the order of the road's marks.
func _check_laid(t: TestContext, at: String, road: Dictionary, toward: Vector2) -> void:
	var layer := _marks(road)
	if not t.check(layer != null, "%s: its road has no marks layer" % at):
		return
	var crossings: Array = layer.laid("crossing")
	var glyphs: Array = layer.laid("glyph")
	var i := _entry(road, "crossings", toward)
	var j := _entry(road, "glyphs", toward)
	if not t.check(
		i >= 0 and i < crossings.size() and j >= 0 and j < glyphs.size(),
		"%s: the layer laid %d crossings and %d glyphs" % [at, crossings.size(), glyphs.size()],
	):
		return
	var rect: Rect2 = road["rect"]
	var centre := rect.size * 0.5
	var glyph: Rect2 = glyphs[j]
	t.check(
		(glyph.get_center() - centre).dot(toward.rotated(PI * 0.5)) > 0.0,
		"%s: the glyph at %s is not in the approaching lane" % [at, glyph],
	)
	t.check(not glyph.intersects(crossings[i]), "%s: the glyph runs into the crossing" % at)
	t.check(
		(crossings[i] as Rect2).get_center().distance_to(centre)
			> glyph.get_center().distance_to(centre),
		"%s: the crossing is not nearer the junction than the glyph" % at,
	)


## The no-lamp zone of every front or exit doorway of every tower: `{ pos, strip }`.
func _door_zones(towers: Array) -> Array:
	var zones: Array = []
	for tower: Dictionary in towers:
		for door: Dictionary in WorldGen.get_openings(tower["node"]):
			if not (door["front"] or door["exit"]):
				continue
			var p: Vector2 = door["pos"]
			var out: Vector2 = door["outward"][0]
			var across := Vector2(out.y, out.x).abs()
			var half: float = door["width"] * 0.5 + STRIP_MARGIN
			zones.append({
				"pos": p,
				"strip": Rect2(p - across * half, Vector2.ZERO).expand(
					p + across * half + out * STRIP_REACH,
				),
			})
	return zones


## The crossings' zones in world space.
func _crossings(streets: Array) -> Array:
	var zones: Array = []
	for piece: Dictionary in streets:
		var layer := _marks(piece)
		if layer == null:
			continue
		for r: Rect2 in layer.laid("crossing"):
			var zone := Rect2((piece["rect"] as Rect2).position + r.position, r.size)
			zones.append(zone.grow_individual(SIDEWALK, 0, SIDEWALK, 0)
				if zone.size.x > zone.size.y
				else zone.grow_individual(0, SIDEWALK, 0, SIDEWALK))
	return zones


func _check_lamps(
	t: TestContext,
	label: String,
	district: Node2D,
	towers: Array,
	streets: Array,
) -> void:
	var lamps := WorldGen.get_streetlights(district)
	t.require(lamps.size() >= 20, "%s: only %d lamps" % [label, lamps.size()])
	var zones := _door_zones(towers)
	var crossings := _crossings(streets)
	var signs := 0
	for lamp: Dictionary in lamps:
		var p: Vector2 = lamp["pos"]
		var at := "%s: the lamp at %s" % [label, p.round()]
		t.check(_in(streets, p, "sidewalk"), "%s is not on a sidewalk" % at)
		var node := lamp["node"] as RigidBody2D
		t.check(node != null and node.freeze, "%s is not an anchored piece" % at)
		signs += 1 if node.object_name == "Neon sign" else 0
		var post := Rect2(p - node.size * 0.5, node.size)
		for zone: Dictionary in zones:
			var c: Vector2 = zone["pos"]
			t.check(
				p.distance_to(c) >= DOOR_CLEAR and not (zone["strip"] as Rect2).has_point(p),
				"%s breaks the door rule at the doorway %s" % [at, c],
			)
		for landing: Rect2 in crossings:
			t.check(not post.intersects(landing), "%s stands in a crossing %s" % [at, landing])
		for tower: Dictionary in towers:
			t.check(not post.intersects((tower["rect"] as Rect2).grow(TOWER_BODY)),
				"%s stands against a tower" % at)
	t.check(signs > 0 and signs < lamps.size(), "%s: %d of %d lamps are neon signs"
			% [label, signs, lamps.size()])
	_check_spacing(t, label, lamps)


## No two lamps closer than the jittered spacing allows.
func _check_spacing(t: TestContext, label: String, lamps: Array) -> void:
	for i in lamps.size():
		for j in range(i + 1, lamps.size()):
			var a: Vector2 = lamps[i]["pos"]
			var b: Vector2 = lamps[j]["pos"]
			t.check(
				a.distance_to(b) >= LAMP_GAP_MIN or _crosswise(a, b),
				"%s: lamps at %s and %s are %.0f px apart" % [
					label,
					a.round(),
					b.round(),
					a.distance_to(b),
				],
			)


## Whether `a` and `b` lie on different sides of a block (neither level in x nor in y): lamps round
## a corner may stand closer than the spacing along one side.
func _crosswise(a: Vector2, b: Vector2) -> bool:
	return absf(a.x - b.x) > 1.0 and absf(a.y - b.y) > 1.0


func _in(pieces: Array, p: Vector2, kind: String) -> bool:
	return pieces.any(
		func(piece: Dictionary) -> bool:
			return piece["kind"] == kind and (piece["rect"] as Rect2).grow(1.0).has_point(p),
	)


## The clutter: the kinds with their solidity, clear of doorways, lamps, crossings and towers.
func _check_clutter(
	t: TestContext,
	label: String,
	district: Node2D,
	world: Array,
	seen: Dictionary,
) -> void:
	var towers: Array = world[0]
	var streets: Array = world[1]
	var clutter := WorldGen.get_clutter(district)
	t.check(clutter.size() >= 10, "%s: only %d clutter pieces" % [label, clutter.size()])
	var zones := _door_zones(towers)
	var crossings := _crossings(streets)
	var around := {
		"zones": zones,
		"crossings": crossings,
		"lamps": WorldGen.get_streetlights(district),
		"towers": towers,
		"streets": streets,
	}
	for piece: Dictionary in clutter:
		var key: String = piece["key"]
		if t.check(CLUTTER.has(key), "%s: %s is not street clutter" % [label, key]):
			seen[key] = true
			_check_piece(t, label, piece, around)


## One clutter `piece` has its kind's solidity and keeps clear of what is `around` it.
func _check_piece(t: TestContext, label: String, piece: Dictionary, around: Dictionary) -> void:
	var node := piece["node"] as RigidBody2D
	var key: String = piece["key"]
	var at := "%s: the %s at %s" % [label, key, node.global_position.round()]
	t.check(node.solid == CLUTTER[key][0], "%s: solid is %s" % [at, node.solid])
	t.check(node.anchored == CLUTTER[key][1], "%s: anchored is %s" % [at, node.anchored])
	var rect := Rect2(node.global_position - node.size * 0.5, node.size)
	t.check(
		_in(around["streets"], node.global_position, "sidewalk"),
		"%s is off the sidewalks" % at,
	)
	for zone: Dictionary in around["zones"]:
		t.check(
			not rect.intersects(zone["strip"])
				and rect.get_center().distance_to(zone["pos"]) > 40.0,
			"%s meets the doorway %s" % [at, zone["pos"]],
		)
	for landing: Rect2 in around["crossings"]:
		t.check(not rect.intersects(landing), "%s meets the crossing %s" % [at, landing])
	for lamp: Dictionary in around["lamps"]:
		t.check(not rect.has_point(lamp["pos"]), "%s sits on a lamp" % at)
	for tower: Dictionary in around["towers"]:
		t.check(
			not rect.intersects((tower["rect"] as Rect2).grow(TOWER_BODY)),
			"%s stands against a tower" % at,
		)


func run(t: TestContext) -> void:
	var seen := {}
	for district_seed in SEEDS:
		var label := "seed %d" % district_seed
		var district := WorldGen.generate_district(district_seed, "", ENTRANCE, t.world)
		var towers := DistrictReads.get_towers(district)
		var streets := DistrictReads.get_district_street(district)
		_check_floors(t, label, streets)
		_check_arms(t, label, streets)
		_check_lamps(t, label, district, towers, streets)
		_check_clutter(t, label, district, [towers, streets], seen)
		district.queue_free()
		await t.frames(2)
	for key: String in CLUTTER:
		t.check(seen.has(key), "no %s in any of the districts" % key)
