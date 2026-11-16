extends GameTest
## #193 phase 3 (L2, L3, L4 in 3D): a generated house is lit in the 3D render by its pieces. Every
## light a piece declares (`get_lights()`) becomes an `OmniLight3D` at the piece's place (and its
## declared height: low for a screen, a tube, overhead for a lamp) in its colour and energy, as far
## as its pool, unless the per-floor budget dropped it; a room no piece lights gets a ceiling
## fixture at its centre, overhead; and no floor is reached by more than the budget.
##
## It reads (tests/_lighting/lighting_3d_probe.gd) `WorldLighting3D`: `lights()`, `fixtures()`,
## `budget()`; a piece's `get_lights()`.

const Probe := preload("res://tests/_lighting/lighting_3d_probe.gd")
const Lights2D := preload("res://tests/_lighting/lighting_probe.gd")
const SEED := 1


func describe() -> Dictionary:
	return {
		"name": "A house is lit in 3D by a light per light-giving piece and per room fixture",
		"description": "Each declared light is an OmniLight3D at its piece's place, at its height, "
			+ "in "
			+ "its colour, reaching its pool (or a budget drop); unlit rooms get a fixture at "
			+ "their centre; no floor is reached by more than the budget.",
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
		var dropped := (lighting.budget()["dropped"] as Array).filter(
			func(d: Dictionary) -> bool: return d["piece"] == piece
		)
		var own := Probe.lights_of(lighting, piece)
		t.check(
			own.size() + dropped.size() == wanted.size(),
			"%s: %d lights declared, %d placed and %d dropped" % [
				piece.name, wanted.size(), own.size(), dropped.size(),
			],
		)
		placed += own.size()
		_check_piece(t, piece, own)
	t.check(
		declared > 0 and placed > 0,
		"the house declares and places lights (%d, %d)" % [declared, placed],
	)
	_check_fixtures(t, lighting)
	_check_floors(t, lighting)


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
			Probe.floor_reach(l), float(spec["radius"]), 0.5,
			"%s's pool reaches the declared radius on the floor" % l.name,
		)
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
	t.check(not lighting.fixtures().is_empty(), "some room has a fixture")


## No floor is reached by more of the lights than the budget says.
func _check_floors(t: TestContext, lighting: WorldLighting3D) -> void:
	var per_floor := int(lighting.budget()["per_floor"])
	for ground: Node2D in Lights2D.floors(t.world.house):
		var rect := Lights2D.floor_rect(ground).grow(LightingConfig.floor_reach)
		var n := lighting.lights().filter(
			func(l: OmniLight3D) -> bool:
				var reach := Vector2.ONE * Probe.floor_reach(l)
				return rect.intersects(Rect2(Probe.ground_of(l) - reach, reach * 2.0))
		).size()
		t.check(
			n <= per_floor,
			"floor %s is reached by %d lights (at most %d)" % [ground.name, n, per_floor],
		)
