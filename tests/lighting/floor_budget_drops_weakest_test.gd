extends GameTest
## R10 (ticket #61): at most 12 piece lights per floor (Godot 4.4 lights a canvas item with at most
## 15 point lights; 3 are kept for the flashes), and a room over budget drops its weakest. One room
## holds ten lamps and six neon tubes, sixteen declared lights over one floor: the floor is reached
## by exactly the budget, every declared light is either placed under its piece or listed as
## dropped, and no dropped light is brighter (declared `energy`) than any light kept.
##
## It reads (tests/_lighting/lighting_probe.gd) `WorldLighting` in the group `world_lighting`
## with `lights()`, `flashes()` and `budget()` (`per_floor`, `dropped`: `{ piece, index }`); a
## light-giving piece's `get_lights()` with each light's `energy`.

const Probe := preload("res://tests/_lighting/lighting_probe.gd")
const ROOM := Rect2(0, 0, 900, 600)
const LAMPS := 10
const TUBES := 6


func describe() -> Dictionary:
	return {
		"name": "A floor over its light budget drops its weakest lights",
		"description": "Ten lamps and six neon tubes in one room: the floor is reached by exactly "
			+ "12 lights (15 with the flashes), and every dropped light is no brighter than one "
			+ "kept.",
		"tags": ["lighting"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(ROOM)
	s.switch(&"nav.rebake", false)
	for i in LAMPS:
		s.object(
			StringName("lamp_%d" % i),
			"lamp",
			Vector2(90.0 + 80.0 * i, 120.0 if i % 2 == 0 else 480.0),
			{ "neon": "" },
		)
	for i in TUBES:
		s.object(StringName("tube_%d" % i), "neon_tube", Vector2(130.0 + 130.0 * i, 300.0))


func run(t: TestContext) -> void:
	var pieces := _pieces(t)
	var declared_total := _declared_total(t, pieces)

	var lighting := Probe.require_lighting(t)
	if lighting == null:
		return
	if not t.require(
			declared_total > Probe.PER_FLOOR,
			"the room declares more lights than the budget (%d)" % declared_total,
	):
		return
	if not _check_floor(t, lighting):
		return
	_check_weakest_dropped(t, lighting, pieces, declared_total)


## The lamps, then the tubes.
func _pieces(t: TestContext) -> Array:
	var pieces: Array = []
	for i in LAMPS:
		pieces.append(t.object(StringName("lamp_%d" % i)))
	for i in TUBES:
		pieces.append(t.object(StringName("tube_%d" % i)))
	return pieces


## How many lights `pieces` declare, checking each declares one.
func _declared_total(t: TestContext, pieces: Array) -> int:
	var declared_total := 0
	for piece: Node in pieces:
		var n := Probe.declared(piece).size()
		t.check(n > 0, "%s declares its light (get_lights())" % piece.name)
		declared_total += n
	return declared_total


## Check the budget and that the arena's one floor is reached by exactly it (and within Godot's
## limit with the flashes); false when the arena has not one floor (the test has failed).
func _check_floor(t: TestContext, lighting: WorldLighting) -> bool:
	var budget: Dictionary = lighting.budget()
	var per_floor := int(budget.get("per_floor", -1))
	t.check(
		per_floor > 0 and per_floor <= Probe.PER_FLOOR,
		"the budget is at most %d lights a floor (%d)" % [Probe.PER_FLOOR, per_floor],
	)
	var flashes: Array = lighting.flashes()
	var lights: Array = lighting.lights()
	var floors := Probe.floors(t.world.house)
	if not t.require(floors.size() == 1, "the arena has one floor (%d)" % floors.size()):
		return false
	var ground: Node2D = floors[0]
	var reaching := lights.filter(
		func(l: Variant) -> bool: return l is PointLight2D and Probe.reaches(l, ground),
	)
	t.check(
		reaching.size() == per_floor,
		"the floor is reached by exactly the budget, %d lights (%d)" % [per_floor, reaching.size()],
	)
	t.check(
		reaching.size() + flashes.size() <= Probe.ITEM_LIGHTS,
		"with the %d flashes the floor takes %d lights (at most %d)"
			% [flashes.size(), reaching.size() + flashes.size(), Probe.ITEM_LIGHTS],
	)
	return true


## Each declared light of `pieces` is placed under its piece or dropped; the dropped ones are the
## weakest.
func _check_weakest_dropped(t: TestContext, lighting: WorldLighting, pieces: Array,
		declared_total: int) -> void:
	var kept_energy: Array[float] = []
	var dropped_energy: Array[float] = []
	for piece: Node in pieces:
		_sort_energies(t, lighting, piece, kept_energy, dropped_energy)
	t.check(
		not dropped_energy.is_empty(),
		"the budget dropped some of the %d lights" % declared_total,
	)
	if not dropped_energy.is_empty() and not kept_energy.is_empty():
		t.check(
			dropped_energy.max() <= kept_energy.min(),
			"the dropped lights are the weakest (dropped up to %.2f, kept from %.2f)"
				% [dropped_energy.max(), kept_energy.min()],
		)


## Check that each light `piece` declares is placed under it or dropped, appending its declared
## energy to `kept_energy` or `dropped_energy`.
func _sort_energies(t: TestContext, lighting: WorldLighting, piece: Node,
		kept_energy: Array[float], dropped_energy: Array[float]) -> void:
	var wanted := Probe.declared(piece)
	var own := Probe.lights_of(lighting, piece)
	var dropped := Probe.dropped_of(lighting, piece)
	t.check(
		own.size() + dropped.size() == wanted.size(),
		"%s: %d lights declared, %d placed under it and %d dropped"
			% [piece.name, wanted.size(), own.size(), dropped.size()],
	)
	var dropped_at := dropped.map(func(d: Dictionary) -> int: return int(d.get("index", -1)))
	for i in wanted.size():
		var energy := float((wanted[i] as Dictionary).get("energy", -1.0))
		if dropped_at.has(i):
			dropped_energy.append(energy)
		else:
			kept_energy.append(energy)
