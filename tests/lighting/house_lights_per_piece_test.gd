extends GameTest
## R10 (ticket #61): a generated house is lit by its pieces. Every light-giving piece (lamps,
## screens, neon tubes, streetlights) declares its lights (`get_lights()`), and the lighting gives
## each declared light a PointLight2D parented to the piece (so it moves with it), unless the floor
## budget dropped it; a room with no piece of its own lighting it gets a ceiling fixture. No floor
## is reached by more than 12 of those lights, so with the 3 flashes no floor's canvas item has more
## than the 15 point lights Godot 4.4 lights an item with.
##
## It reads (tests/_lighting/lighting_probe.gd) `WorldLighting` in the group `world_lighting`
## with `lights()`, `fixtures()`, `flashes()` and `budget()`; a light-giving piece's `get_lights()`
## with `room_light` on the light that lights its room.

const Probe := preload("res://tests/_lighting/lighting_probe.gd")
const SEED := 4


func describe() -> Dictionary:
	return {
		"name": "A house has a light per light-giving piece and per room fixture, within the floor "
			+ "budget",
		"description": "Lamps, screens, neon tubes and streetlights each get their declared "
			+ "PointLight2Ds under the piece (or a budget drop); unlit rooms get a fixture; no "
			+ "floor is reached by more than 12 lights, 15 with the flashes.",
		"tags": ["lighting"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.house(SEED)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var house: Node2D = t.world.house
	if not _check_kinds(t, house):
		return

	var lighting := Probe.require_lighting(t)
	if lighting == null:
		return
	var lights: Array = lighting.lights()
	var flashes: Array = lighting.flashes()
	var budget: Dictionary = lighting.budget()
	var per_floor := int(budget.get("per_floor", -1))
	t.check(
		per_floor > 0 and per_floor <= Probe.PER_FLOOR,
		"the budget is at most %d lights a floor (%d)" % [Probe.PER_FLOOR, per_floor],
	)
	t.check(not flashes.is_empty(), "there is a flash pool")

	var placed := {}
	var room_lit := {}
	_check_declared(t, lighting, placed, room_lit)
	_check_lights(t, lights)
	_check_owned(t, lighting, placed, room_lit)
	_check_floors(t, lights, flashes, per_floor)


## Check that `house` holds a piece of every light-giving kind and that each declares its light;
## false when a kind is missing (the test has failed).
func _check_kinds(t: TestContext, house: Node2D) -> bool:
	var by_kind := {}
	for piece in Probe.pieces(house):
		var kind := Probe.light_kind(piece)
		if kind != "":
			by_kind[kind] = by_kind.get(kind, []) + [piece]
	var kinds := ["lamp", "screen", "neon tube", "streetlight"]
	if not t.require(
			kinds.all(func(k: String) -> bool: return by_kind.has(k)),
			"the house (seed %d) holds a lamp, a screen, a neon tube and a streetlight (found: %s)"
				% [SEED, by_kind.keys()],
	):
		return false
	for kind in kinds:
		for piece: Node in by_kind[kind]:
			t.check(
				not Probe.declared(piece).is_empty(),
				"the %s %s declares its light (get_lights())" % [kind, piece.name],
			)
	return true


## Each declared light is a PointLight2D under its piece, or a budget drop: marks each placed light
## in `placed` and the room each kept room light lights in `room_lit`.
func _check_declared(t: TestContext, lighting: WorldLighting, placed: Dictionary,
		room_lit: Dictionary) -> void:
	for piece in Probe.pieces(t.world.house):
		var wanted := Probe.declared(piece)
		var own := Probe.lights_of(lighting, piece)
		var dropped := Probe.dropped_of(lighting, piece)
		t.check(
			own.size() + dropped.size() == wanted.size(),
			"%s: %d lights declared, %d placed under it and %d dropped"
				% [piece.name, wanted.size(), own.size(), dropped.size()],
		)
		for l in own:
			placed[l] = true
		var dropped_at := dropped.map(func(d: Dictionary) -> int: return int(d.get("index", -1)))
		for i in wanted.size():
			if (wanted[i] as Dictionary).get("room_light", false) and not dropped_at.has(i):
				room_lit[_room_of(t.rooms, (piece as Node2D).global_position)] = true


## Every one of `lights` is a shadowed PointLight2D with a texture.
func _check_lights(t: TestContext, lights: Array) -> void:
	for l in lights:
		t.check(l is PointLight2D, "lights() holds only PointLight2Ds (%s)" % [l])
		if l is PointLight2D:
			t.check(
				(l as PointLight2D).texture != null,
				"%s has a light texture" % (l as Node).name,
			)
			t.check((l as PointLight2D).shadow_enabled, "%s casts shadows" % (l as Node).name)


## Every fixture lies in its room, every light is a piece's (`placed`) or a fixture's, and every
## room is lit by a piece's room light (`room_lit`) or a fixture.
func _check_owned(t: TestContext, lighting: WorldLighting, placed: Dictionary,
		room_lit: Dictionary) -> void:
	var fixtures: Array = lighting.fixtures()
	var fixture_lights := {}
	for f: Dictionary in fixtures:
		fixture_lights[f.get("light")] = true
		var rect: Rect2 = _rect_of(t.rooms, String(f.get("room", "")))
		t.check(
			f.get("light") is PointLight2D
				and rect.has_point((f["light"] as Node2D).global_position),
			"the fixture of room %s is a PointLight2D inside it" % f.get("room", ""),
		)
	for l in lighting.lights():
		t.check(
			placed.has(l) or fixture_lights.has(l),
			"every light is a piece's or a fixture's (%s)" % (l as Node).name,
		)
	for room: Dictionary in t.rooms:
		t.check(
			room_lit.has(room["key"])
				or fixtures.any(func(f: Dictionary) -> bool: return f.get("room") == room["key"]),
			"room %s is lit: by a piece's room light or by a fixture" % room["key"],
		)


## No floor is reached by more than the budget, nor by more than 15 with every flash.
func _check_floors(t: TestContext, lights: Array, flashes: Array, per_floor: int) -> void:
	for ground: Node2D in Probe.floors(t.world.house):
		var n := lights.filter(
			func(l: Variant) -> bool: return l is PointLight2D and Probe.reaches(l, ground),
		).size()
		t.check(
			n <= per_floor,
			"floor %s is reached by %d lights (at most %d)" % [ground.name, n, per_floor],
		)
		t.check(
			n + flashes.size() <= Probe.ITEM_LIGHTS,
			"floor %s takes %d lights with the %d flashes (at most %d)"
				% [ground.name, n + flashes.size(), flashes.size(), Probe.ITEM_LIGHTS],
		)


## The key of the room in `rooms` holding world point `p` ("" for none).
func _room_of(rooms: Array, p: Vector2) -> String:
	for room: Dictionary in rooms:
		if (room["rect"] as Rect2).has_point(p):
			return String(room["key"])
	return ""


## The rect of room `key` in `rooms` (empty for none).
func _rect_of(rooms: Array, key: String) -> Rect2:
	for room: Dictionary in rooms:
		if String(room["key"]) == key:
			return room["rect"]
	return Rect2()
