extends GameTest
## #193 phase 3 (L2, L3 in 3D): a generated house is lit in the 3D render by its pieces. Every
## light a piece declares (`get_lights()`) becomes an `OmniLight3D` at the piece's place (and its
## declared height: low for a screen, a tube, overhead for a lamp) in its colour and energy, as far
## as its pool (the declared radius times `Lighting3DConfig.range_scale`), carrying the room it
## stands in and whether it is a street light; a room no piece lights gets a ceiling fixture at its
## centre, overhead, the only light that may cast a shadow.
##
## It reads (tests/_lighting/lighting_3d_probe.gd) `WorldLighting3D`: `lights()`, `fixtures()`; a
## light's metas `piece`, `index`, `room` and `shadowable`; a piece's `get_lights()`.

const Probe := preload("res://tests/_lighting/lighting_3d_probe.gd")
const Lights2D := preload("res://tests/_lighting/lighting_probe.gd")
const SEED := 1


func describe() -> Dictionary:
	return {
		"name": "A house is lit in 3D by a light per light-giving piece and per room fixture",
		"description": "Each declared light is an OmniLight3D at its piece's place, at its height, "
			+ "in its colour, reaching its pool, in its room; unlit rooms get a fixture at their "
			+ "centre, and only a fixture may cast a shadow.",
		"tags": ["lighting", "3d"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.house(SEED)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var lighting := Probe.light(t, t.rooms)
	if lighting == null:
		return
	var placed := 0
	var declared := 0
	for piece in Lights2D.pieces(t.world.house):
		var wanted := Lights2D.declared(piece)
		declared += wanted.size()
		var own := Probe.lights_of(lighting, piece)
		t.check(
			own.size() == wanted.size(),
			"%s: %d lights declared, %d placed" % [piece.name, wanted.size(), own.size()],
		)
		placed += own.size()
		_check_piece(t, piece, own)
	t.check(
		declared > 0 and placed > 0,
		"the house declares and places lights (%d, %d)" % [declared, placed],
	)
	_check_fixtures(t, lighting)


## Each placed light of `piece` stands over the declared place of its light, at the height of its
## kind, with a colour, a range and an energy.
func _check_piece(t: TestContext, piece: Node2D, own: Array) -> void:
	var specs := Lights2D.declared(piece)
	for l: OmniLight3D in own:
		var spec: Dictionary = specs[int(l.get_meta(&"index"))]
		var at: Vector2 = piece.global_transform * (spec["offset"] as Vector2)
		t.check(
			Probe.ground_of(l).distance_to(at) < 0.5,
			"%s stands over its piece's light" % l.name,
		)
		var kind: StringName = &"street" if spec.get(
			"street",
			false,
		) else spec.get("height", &"low")
		t.expect_near(
			l.position.y, Lighting3DConfig.height_of(kind) * RenderConfig.unit, 0.01,
			"%s hangs at the height of a %s light" % [l.name, kind],
		)
		t.check(l.light_color == spec["colour"], "%s is in its declared colour" % l.name)
		t.expect_near(
			Probe.floor_reach(l), float(spec["radius"]) * Lighting3DConfig.range_scale, 0.5,
			"%s's pool reaches the declared radius on the floor" % l.name,
		)
		t.expect_eq(
			Probe.room_of(l), Probe.room_at(t.rooms, at), "%s knows the room it stands in" % l.name
		)
		t.expect_eq(
			Probe.street_of(l), bool(spec.get("street", false)),
			"%s knows whether it is a street light" % l.name
		)
		t.check(not l.get_meta(&"shadowable"), "%s casts no shadow: it is a piece's" % l.name)
		t.check(
			l.light_energy <= float(spec["energy"]) + 0.001,
			"%s is at most its energy" % l.name,
		)


## Every fixture is an overhead light at the centre of its room, and every room is lit by a kept
## room light or a fixture.
func _check_fixtures(t: TestContext, lighting: WorldLighting3D) -> void:
	for f: Dictionary in lighting.fixtures():
		var rect := Rect2()
		for room: Dictionary in t.rooms:
			if room["key"] == f["room"]:
				rect = room["rect"]
		var l: OmniLight3D = f["light"]
		t.check(
			Probe.ground_of(l).distance_to(rect.get_center()) < 0.5,
			"the fixture of room %s is at its centre" % f["room"],
		)
		t.expect_near(
			l.position.y, Lighting3DConfig.overhead_height * RenderConfig.unit, 0.01,
			"the fixture of room %s is overhead" % f["room"],
		)
		t.check(l.get_meta(&"shadowable"), "the fixture of room %s may cast a shadow" % f["room"])
	t.check(not lighting.fixtures().is_empty(), "some room has a fixture")
