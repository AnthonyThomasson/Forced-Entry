class_name WorldLighting3D
extends Node3D
## The Lighting domain's 3D dusk (#193 phase 3, `docs/lighting.md`, "The 3D lighting"): the
## lights of the 3D render, built under the 3D view's world from the 2D world the sim runs in. It
## reads the world as `WorldLighting` does, duck-typed: Objects' floors (the group `floors`), the
## lights a piece declares (`get_lights()`) and the rooms `WorldGen` gives, and builds
##   - the dusk: `LightingConfig.ambient_color` as the toon shaders' ambient (`ToonLight`), and one
##     `DirectionalLight3D`, the sky, in `sky_color` from the south-west at
##     `Lighting3DConfig.sun_elevation` with hard shadows, reaching only the street's floors (a
##     texture of them is the sky mask): a house is lit from within, as in 2D, and the walls'
##     shadows on the street are short;
##   - an `OmniLight3D` per light a piece declares, at the height of its kind (`overhead`, `low`,
##     `street`), in its colour and energy, as far as its pool's radius; and a ceiling fixture in
##     every room no `room_light` lights: placed within the same per-floor budget as the 2D lights
##     (`Budget`);
##   - the cost: the nearest `shadow_lights` overhead lights to the view's focus cast a shadow and
##     at most `max_lights` are on (`LightingCostConfig`), chosen again as the view moves.
## A light follows its piece (a shoved lamp), flickers in the rhythm `light_rhythm.gd` seeds for it
## and goes with its piece. In the group `world_lighting_3d`. The flashes of a shot and a burst are
## the light-fx job's.

## A piece's light changed its rhythm's level: the piece (a 2D node) and how much of its glow shows
## now (0.3 to 1.1), for whoever shows the piece's glow (Main, which holds both worlds).
signal glow_changed(piece: Node, level: float)

const Rhythm := preload("res://scenes/lighting/light_rhythm.gd")
const Budget := preload("res://scenes/lighting/light_budget.gd")
const GROUP := &"world_lighting_3d"
## The lights run after the bodies they follow (and the mirror that shows them).
const PRIORITY := 20
## The sun mask's most texels on a side.
const SKY_TEXELS := 2048

## The 2D world the lights read, the world's seed (the rhythms') and what says where the view is
## (`focus`: `Callable() -> Vector2`, world px; none: every light stays on).
var _world: Node2D
var _seed := 0
var _focus := Callable()
var _sun: DirectionalLight3D
## Every kept light.
var _lit: Array[Lit] = []
var _fixtures: Array = []
var _dropped: Array = []
## The refresh clock and the focus it was last made for.
var _since := 0.0
var _focused := Vector2(INF, INF)
var _shadowed := 0
var _on := 0
## Test reads: rhythms advance every frame, but only a changed energy is written.
var rhythm_steps := 0
var energy_writes := 0


func _exit_tree() -> void:
	ToonLight.clear()


func _process(delta: float) -> void:
	_since += delta
	for lit in _lit:
		lit.follow()
		if lit.rhythm != null:
			var energy := lit.energy * lit.rhythm.step(delta)
			rhythm_steps += 1
			if energy != lit.light.light_energy:
				lit.light.light_energy = energy
				energy_writes += 1
				if lit.fixed == null and is_instance_valid(lit.piece):
					glow_changed.emit(lit.piece, clampf(0.3 + 0.7 * energy / lit.energy, 0.0, 1.1))
	if _since >= LightingCostConfig.refresh or _focus_moved():
		_since = 0.0
		choose()


## Light the 3D world under `parent` (a node of the 3D view's world) for the 2D world `world`:
## `seed_value` seeds the rhythms, `rooms` are its `WorldGen.get_rooms` (world-space `{ key, rect
## }`; none: no fixtures), `focus` says where the view is looking (`Callable() -> Vector2`, px).
## Null while `LightingConfig.enabled` is off (nothing is built).
static func light(
	parent: Node, world: Node2D, seed_value: int, rooms: Array = [], focus := Callable()
) -> WorldLighting3D:
	var node := WorldLighting3D.new()
	node.name = "WorldLighting3D"
	node.process_priority = PRIORITY
	node._world = world
	node._seed = seed_value
	node._focus = focus
	node.add_to_group(GROUP)
	parent.add_child(node)
	if LightingConfig.enabled:
		node._build(rooms)
	else:
		node._flat()
	return node


## Every piece and fixture light kept (the flashes are not among them).
func lights() -> Array:
	var out: Array = []
	for lit in _lit:
		out.append(lit.light)
	return out


## `{ room, light }` per room fixture.
func fixtures() -> Array:
	return _fixtures


## The sky: the one directional light.
func sun() -> DirectionalLight3D:
	return _sun


## `{ per_floor, dropped }`: the most lights one floor may be reached by, and `{ piece, index }` per
## declared light the budget left out.
func budget() -> Dictionary:
	return { "per_floor": LightingConfig.per_floor(), "dropped": _dropped }


## How many lights cast a shadow now, and how many are on.
func shadowed_count() -> int:
	return _shadowed


## How many lights are on.
func on_count() -> int:
	return _on


# --- Building -------------------------------------------------------------------------------------


## Light the art flat (`LightingConfig.enabled` off): the white ambient and a sun that adds nothing.
func _flat() -> void:
	ToonLight.set_ambient(Color.WHITE)
	_sun = DirectionalLight3D.new()
	_sun.name = "Sky"
	_sun.light_energy = 0.01
	_sun.shadow_enabled = false
	add_child(_sun)


## Build the lights, the dusk and the sky for `rooms`.
func _build(rooms: Array) -> void:
	ToonLight.set_ambient(LightingConfig.ambient_color)
	_sky(_world)
	var floors := Budget.new()
	for ground: Node2D in _world.get_tree().get_nodes_in_group(&"floors"):
		if _world.is_ancestor_of(ground):
			floors.add_floor(ground)
	var lit_rooms := {}
	_place(_candidates(rooms, lit_rooms), rooms, floors, lit_rooms)
	choose()


## `[piece, index, spec, order]` per light a piece under the world declares, marking in `lit_rooms`
## the room a piece's `room_light` stands in.
func _candidates(rooms: Array, lit_rooms: Dictionary) -> Array:
	var candidates: Array = []
	for node in _world.find_children("*", "", true, false):
		if node.has_method(&"get_lights"):
			var specs: Array = node.call(&"get_lights")
			for i in specs.size():
				candidates.append([node, i, specs[i], candidates.size()])
				if (specs[i] as Dictionary).get("room_light", false):
					lit_rooms[_room_of(rooms, (node as Node2D).global_position)] = true
	return candidates


## The 2D placement: a room's own fixture first (counted whatever), then the candidates strongest
## first within the floors' budget, then the fixture of a room whose every room light was dropped.
func _place(candidates: Array, rooms: Array, floors: Budget, lit_rooms: Dictionary) -> void:
	for room: Dictionary in rooms:
		if not lit_rooms.has(room["key"]):
			_fixture(room, floors, true)
	candidates.sort_custom(func(a: Array, b: Array) -> bool:
		var ea := float((a[2] as Dictionary).get("energy", 0.0))
		var eb := float((b[2] as Dictionary).get("energy", 0.0))
		return ea > eb if ea != eb else int(a[3]) < int(b[3]))
	var kept_rooms := {}
	for c: Array in candidates:
		if _piece_light(c[0], c[1], c[2], floors) and (c[2] as Dictionary).get("room_light", false):
			kept_rooms[_room_of(rooms, (c[0] as Node2D).global_position)] = true
	for room: Dictionary in rooms:
		if lit_rooms.has(room["key"]) and not kept_rooms.has(room["key"]):
			_fixture(room, floors, false)


## The sky: the directional sun, shining where the street's floors are (`ToonLight`'s sky mask).
func _sky(world: Node2D) -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "Sky"
	_sun.light_color = LightingConfig.sky_color
	_sun.light_energy = LightingConfig.sky_energy
	var toward := -LightingConfig.sky_from.normalized()  # the way the light travels, on the ground
	var up := deg_to_rad(Lighting3DConfig.sun_elevation)
	var travel := Vector3(toward.x * cos(up), -sin(up), toward.y * cos(up))
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = Lighting3DConfig.shadow_max_distance
	_sun.shadow_bias = Lighting3DConfig.shadow_bias
	_sun.shadow_normal_bias = Lighting3DConfig.shadow_normal_bias
	_sun.light_angular_distance = 0.0
	add_child(_sun)
	_sun.basis = Basis.looking_at(travel, Vector3.UP)
	_sky_mask(world)


## Where the sun reaches: the street's floors, less every house floor drawn over them (a tower
## stands on street floors; its rooms are lit from within) and the walls round it. A house or an
## arena has no street: the sun reaches nothing there, as the 2D sky is on the street only.
func _sky_mask(world: Node2D) -> void:
	var streets: Array[Rect2] = []
	var houses: Array[Rect2] = []
	for ground: Node2D in world.get_tree().get_nodes_in_group(&"floors"):
		if world.is_ancestor_of(ground):
			_sort_floor(ground, streets, houses)
	var bounds := Rect2()
	for k in streets.size():
		bounds = streets[k] if k == 0 else bounds.merge(streets[k])
	var cell := maxf(1.0, ceilf(maxf(bounds.size.x, bounds.size.y) / float(SKY_TEXELS)))
	var wide := maxi(1, ceili(bounds.size.x / cell))
	var tall := maxi(1, ceili(bounds.size.y / cell))
	var image := Image.create(wide, tall, false, Image.FORMAT_L8)
	_paint(image, streets, bounds.position, cell, Color.WHITE)
	_paint(image, houses, bounds.position, cell, Color.BLACK)
	var rect := Rect2(bounds.position, Vector2(wide, tall) * cell)
	ToonLight.set_sky(ImageTexture.create_from_image(image), rect)


## File `ground`'s rectangle under the street's floors or the others' (grown by `floor_reach`); a
## floor with no size is skipped.
static func _sort_floor(ground: Node2D, streets: Array[Rect2], houses: Array[Rect2]) -> void:
	var size: Variant = ground.get("size")
	if not size is Vector2:
		return
	var mask := ground.light_mask
	for item in ground.find_children("*", "CanvasItem", true, false):
		mask |= (item as CanvasItem).light_mask
	var covers := Rect2(ground.global_position, size as Vector2)
	if mask & LightMasks.STREET != 0:
		streets.append(covers)
	else:
		houses.append(covers.grow(LightingConfig.floor_reach))


## Fill each of `rects` (world px) into `image`, whose texels are `cell` px from `origin`.
static func _paint(
	image: Image,
	rects: Array[Rect2],
	origin: Vector2,
	cell: float,
	c: Color,
) -> void:
	for r in rects:
		var from := ((r.position - origin) / cell).floor()
		var to := ((r.end - origin) / cell).ceil()
		image.fill_rect(Rect2i(Vector2i(from), Vector2i(to - from)), c)


## Give `piece` its declared light `index` if the floors it reaches have room; whether it did.
func _piece_light(piece: Node2D, index: int, spec: Dictionary, floors: Budget) -> bool:
	var street: bool = spec.get("street", false)
	var item_mask := LightMasks.HOUSE | (LightMasks.STREET if street else 0)
	var kind: StringName = &"street" if street else spec.get("height", &"low")
	var radius := float(spec.get("radius", 100.0))
	var at: Vector2 = piece.global_transform * (spec.get("offset", Vector2.ZERO) as Vector2)
	if not floors.take(Budget.box_at(at, radius * Lighting3DConfig.range_scale), item_mask):
		_dropped.append({ "piece": piece, "index": index })
		return false
	var lit := Lit.new()
	lit.piece = piece
	lit.offset = spec.get("offset", Vector2.ZERO)
	lit.light = _omni(
		spec.get("colour", Color.WHITE), float(spec.get("energy", 1.0)), radius, kind
	)
	lit.energy = lit.light.light_energy
	lit.light.name = "Light%d_%s" % [index + 1, piece.name]
	lit.light.set_meta(&"piece", piece)
	lit.light.set_meta(&"index", index)
	add_child(lit.light)
	lit.place()
	var seed_value := hash([_seed, Vector2i(piece.global_position.round()), index])
	_rhythm(lit, spec.get("rhythm", []), seed_value)
	_lit.append(lit)
	return true


## A ceiling fixture at the centre of `room` (`{ key, rect }`): an overhead light spanning the room;
## `always` counts it against the budget whatever. Whether it was placed.
func _fixture(room: Dictionary, floors: Budget, always: bool) -> bool:
	var rect: Rect2 = room["rect"]
	var reach := clampf(
		maxf(rect.size.x, rect.size.y) * LightingFixtureConfig.reach_scale
			+ LightingFixtureConfig.reach_pad,
		LightingFixtureConfig.reach_range.x, LightingFixtureConfig.reach_range.y,
	)
	var radius := reach * 0.5
	var box := Budget.box_at(rect.get_center(), radius * Lighting3DConfig.range_scale)
	if not floors.take(box, LightMasks.HOUSE, always):
		return false
	var lit := Lit.new()
	lit.light = _omni(
		LightingFixtureConfig.color, LightingFixtureConfig.energy, radius, &"overhead"
	)
	lit.light.name = "Fixture_%s" % room["key"]
	lit.energy = lit.light.light_energy
	lit.fixed = rect.get_center()
	add_child(lit.light)
	lit.place()
	_rhythm(lit, LightingFixtureConfig.rhythms, hash([_seed, "fixture", room["key"]]))
	_lit.append(lit)
	_fixtures.append({ "room": room["key"], "light": lit.light })
	return true


## Draw the light's rhythm from `kinds` with an RNG seeded by `seed_value` (none when it draws
## steady).
func _rhythm(lit: Lit, kinds: Array, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mode := Rhythm.pick(kinds, rng)
	lit.rhythm = null if mode == &"steady" else Rhythm.new(mode, rng.randi())


## An omni light of `colour` at `energy` whose pool is `radius` px out on the floor (the 2D pool's),
## hung at the height of its `kind` (`overhead`, `low` or `street`); an overhead or street one pools
## flat (`Lighting3DConfig.overhead_slope`), a low one fades from its middle. Only an overhead
## light may cast a shadow (`choose`).
static func _omni(colour: Color, energy: float, radius: float, kind: StringName) -> OmniLight3D:
	var height := Lighting3DConfig.height_of(kind)
	var overhead := kind != &"low"
	var l := OmniLight3D.new()
	l.light_color = colour
	l.light_energy = energy
	l.omni_range = Vector2(
		radius * Lighting3DConfig.range_scale,
		height,
	).length() * RenderConfig.unit
	l.omni_attenuation = 0.0
	# The toon light reads this as the slope of the pool's fall-off (`SPECULAR_AMOUNT` is twice it).
	l.light_specular = (
		Lighting3DConfig.overhead_slope if overhead else Lighting3DConfig.low_slope
	) * 0.5
	l.shadow_enabled = false
	l.set_meta(&"height", height * RenderConfig.unit)
	l.set_meta(&"shadowable", kind == &"overhead")
	return l


## The key of the room in `rooms` holding world point `p` ("" for none).
static func _room_of(rooms: Array, p: Vector2) -> String:
	for room: Dictionary in rooms:
		if (room["rect"] as Rect2).has_point(p):
			return String(room["key"])
	return ""


# --- The cost: which lights are on and which cast a shadow ---------------------------------------


## Where the view is looking (px); null while nothing says.
func _focus_point() -> Variant:
	if not _focus.is_valid():
		return null
	return _focus.call()


## Whether the focus moved far enough since the last choice to make it again.
func _focus_moved() -> bool:
	var at: Variant = _focus_point()
	return at != null and (at as Vector2).distance_to(_focused) > LightingCostConfig.refocus


## How far (px) from the focus a light still reaches the view: half the camera's diagonal.
func _reach() -> float:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null or camera.projection != Camera3D.PROJECTION_ORTHOGONAL:
		return INF
	var size := get_viewport().get_visible_rect().size
	return 0.5 * camera.size * Vector2(size.x / maxf(size.y, 1.0), 1.0).length() / RenderConfig.unit


## Choose which lights are on (the nearest `max_lights` that reach the view) and which of those cast
## a shadow (the nearest `shadow_lights`, a light keeping its shadow unless a rival is
## `keep_margin` times nearer). With no focus every light stays on and none casts a shadow.
func choose() -> void:
	var at: Variant = _focus_point()
	_shadowed = 0
	_on = _lit.size()
	if at == null:
		for lit in _lit:
			_show(lit, not lit.gone)
		return
	_focused = at
	var reach := _reach()
	var near: Array[Lit] = []
	for lit in _lit:
		lit.dist = (lit.world_point() - (at as Vector2)).length()
		if not lit.gone and lit.dist <= reach + lit.light.omni_range / RenderConfig.unit:
			near.append(lit)
	near.sort_custom(func(a: Lit, b: Lit) -> bool: return a.dist < b.dist)
	if near.size() > LightingCostConfig.max_lights:
		near.resize(LightingCostConfig.max_lights)
	_on = near.size()
	for lit in _lit:
		lit.on = false
	for lit in near:
		lit.on = true
	for lit in _lit:
		_show(lit, lit.on)
	# The shadows go to the nearest `shadow_lights` of the ones that may (a room's overhead lights:
	# the walls keep them in their rooms), a light keeping its shadow unless a rival is
	# `keep_margin` times nearer.
	var casters: Array[Lit] = []
	for lit in near:
		if lit.light.get_meta(&"shadowable"):
			casters.append(lit)
	var most := LightingCostConfig.shadow_lights
	var cutoff := casters[most - 1].dist if most > 0 and casters.size() >= most else INF
	for lit in casters:
		var wants := lit.dist <= cutoff
		if lit.light.shadow_enabled and lit.dist <= cutoff / LightingCostConfig.keep_margin:
			wants = true
		lit.light.shadow_enabled = wants and _shadowed < most
		_shadowed += 1 if lit.light.shadow_enabled else 0


## Show or hide `lit`'s light (written only when it changes); a light hidden casts no shadow.
func _show(lit: Lit, on: bool) -> void:
	if lit.light.visible == on:
		return
	lit.light.visible = on
	if not on:
		lit.light.shadow_enabled = false


## One kept light: its node, the piece it follows and where in the piece's frame (a fixture: a place
## in the world), its full energy and its rhythm (null: steady).
class Lit:
	var light: OmniLight3D
	var piece: Variant
	var offset := Vector2.ZERO
	var fixed: Variant = null
	var energy := 1.0
	var rhythm: Rhythm
	var dist := 0.0
	## Whether the cost cap keeps it on, and whether its piece is gone (freed: it stays off).
	var on := true
	var gone := false
	var _xf := Transform2D()

	## Where the light is in the 2D world (px).
	func world_point() -> Vector2:
		if fixed != null:
			return fixed
		if not is_instance_valid(piece):
			return Vector2.ZERO
		return (piece as Node2D).global_transform * offset

	## Put the light at its place (and remember the piece's transform).
	func place() -> void:
		var at := world_point()
		var unit := RenderConfig.unit
		light.position = Vector3(at.x * unit, float(light.get_meta(&"height")), at.y * unit)
		if fixed == null and is_instance_valid(piece):
			_xf = (piece as Node2D).global_transform

	## Follow the piece when it moved (a shove), and go when it is freed.
	func follow() -> void:
		if fixed != null:
			return
		if not is_instance_valid(piece):
			gone = true
			light.visible = false
			light.shadow_enabled = false
			return
		if (piece as Node2D).global_transform != _xf:
			place()
