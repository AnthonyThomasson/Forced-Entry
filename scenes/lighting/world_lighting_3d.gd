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
##     every room no `room_light` lights. A light carries the room it stands in (a texture of the
##     rooms is `ToonLight`'s room map): it lights its own room and no other, so a pool never
##     crosses a wall, with no shadow spent on it;
##   - the cost: at most `max_lights` lights are on, the ones nearest the view's focus, fading in
##     and out, and the `shadow_lights` nearest ceiling fixtures cast a shadow
##     (`LightingCostConfig`),
##     chosen again as the view moves.
##   - the flashes: a `shot` lights a muzzle flash and an `explosion` a blast's (a stun's white) as
##     a short-lived `OmniLight3D` from a small pool (`flash_pool_3d.gd`,
##     `Lighting3DConfig.flash_lights`, the oldest dropped), driven by the 2D flash looks
##     (`LightingConfig.flashes`), unshadowed and kept to the room it is in (the street when it
##     is in none);
##   - a bulb at each ceiling fixture (an emissive sphere over the walls, the 2D glyph's).
## A light follows its piece (a shoved lamp), flickers in the rhythm `light_rhythm.gd` seeds for it
## and goes with its piece. In the group `world_lighting_3d`.

## A piece's light changed its rhythm's level: the piece (a 2D node) and how much of its glow shows
## now (0.3 to 1.1), for whoever shows the piece's glow (Main, which holds both worlds).
signal glow_changed(piece: Node, level: float)

const Rhythm := preload("res://scenes/lighting/light_rhythm.gd")
const FlashPool := preload("res://scenes/lighting/flash_pool_3d.gd")
const GROUP := &"world_lighting_3d"
## The lights run after the bodies they follow (and the mirror that shows them).
const PRIORITY := 20
## The masks' most texels on a side.
const MASK_TEXELS := 2048

## How many of these are in the tree: the dusk's globals are cleared when the last one leaves, so a
## new world built before the old one is freed keeps its own.
static var _alive := 0

## The 2D world the lights read, the world's seed (the rhythms') and what says where the view is
## (`focus`: `Callable() -> Vector2`, world px; none: every light stays on).
var _world: Node2D
var _seed := 0
var _focus := Callable()
var _sun: DirectionalLight3D
## Every kept light.
var _lit: Array[Lit] = []
var _fixtures: Array = []
## The flash pool.
var _pool: FlashPool
## The rooms (`{ key, rect }`): a room's id, the number in the room map, is its index plus one.
var _rooms: Array = []
## The refresh clock and the view it was last made for: the focus (x, y) and how far it reached.
var _since := 0.0
var _seen := Vector3(INF, INF, INF)
## What the last choice made: x the lights casting a shadow, y on, z reaching the view.
var _counts := Vector3i.ZERO
## Test reads: rhythms advance every frame, but only a changed energy is written.
var rhythm_steps := 0
var energy_writes := 0


func _enter_tree() -> void:
	_alive += 1


func _exit_tree() -> void:
	if EventBus.posted.is_connected(_on_posted):
		EventBus.posted.disconnect(_on_posted)
	_alive -= 1
	if _alive <= 0:
		ToonLight.clear()


func _process(delta: float) -> void:
	_since += delta
	if _pool != null:
		_pool.step(delta)
	var gone: Array[Lit] = []
	for lit in _lit:
		lit.follow()
		if lit.gone:
			gone.append(lit)
		else:
			_advance(lit, delta)
	for lit in gone:
		_lit.erase(lit)
		lit.light.queue_free()
	if _since >= LightingCostConfig.refresh or _focus_moved():
		_since = 0.0
		choose()


## Light the 3D world under `parent` (a node of the 3D view's world) for the 2D world `world`:
## `seed_value` seeds the rhythms, `rooms` are its `WorldGen.get_rooms` (world-space `{ key, rect
## }`; none: no fixtures and no room clipping), `focus` says where the view is looking
## (`Callable() -> Vector2`, px). With `LightingConfig.enabled` off no light is built and the art is
## shown as painted.
static func light(
	parent: Node, world: Node2D, seed_value: int, rooms: Array = [], focus := Callable()
) -> WorldLighting3D:
	var node := WorldLighting3D.new()
	node.name = "WorldLighting3D"
	node.process_priority = PRIORITY
	node._world = world
	node._seed = seed_value
	node._focus = focus
	node._rooms = rooms
	node.add_to_group(GROUP)
	parent.add_child(node)
	if LightingConfig.enabled:
		node._build()
	else:
		node._flat()
	return node


## Every piece and fixture light kept (the flashes are not among them).
func lights() -> Array:
	var out: Array = []
	for lit in _lit:
		out.append(lit.light)
	return out


## The pooled flash lights (lit or not).
func flashes() -> Array:
	return [] if _pool == null else _pool.lights


## How many flashes are lit now.
func flash_count() -> int:
	return 0 if _pool == null else _pool.lit_count()


## `{ room, light }` per room fixture.
func fixtures() -> Array:
	return _fixtures


## The sky: the one directional light.
func sun() -> DirectionalLight3D:
	return _sun


## How many lights cast a shadow now.
func shadowed_count() -> int:
	return _counts.x


## How many lights the cost cap keeps on.
func on_count() -> int:
	return _counts.y


## How many lights reach the view (before the cap keeps `max_lights` of them).
func in_view_count() -> int:
	return _counts.z


# --- Building -------------------------------------------------------------------------------------


## Light the art flat (`LightingConfig.enabled` off): the white ambient and a sun that adds nothing.
func _flat() -> void:
	ToonLight.set_ambient(Color.WHITE, 1.0)
	_sun = DirectionalLight3D.new()
	_sun.name = "Sky"
	_sun.light_energy = 0.01
	_sun.shadow_enabled = false
	add_child(_sun)


## Build the lights, the dusk and the sky.
func _build() -> void:
	ToonLight.set_ambient(LightingConfig.ambient_color)
	_sky(_world)
	_room_mask()
	var lit_rooms := {}
	var candidates := _candidates(lit_rooms)
	for room: Dictionary in _rooms:
		if not lit_rooms.has(room["key"]):
			_fixture(room)
	for c: Array in candidates:
		_piece_light(c[0], c[1], c[2])
	_pool = FlashPool.new(self, Lighting3DConfig.flash_lights)
	EventBus.posted.connect(_on_posted)
	choose(true)


## `[piece, index, spec]` per light a piece under the world declares, marking in `lit_rooms` the
## room a piece's `room_light` stands in.
func _candidates(lit_rooms: Dictionary) -> Array:
	var candidates: Array = []
	for node in _world.find_children("*", "", true, false):
		if node.has_method(&"get_lights"):
			var specs: Array = node.call(&"get_lights")
			for i in specs.size():
				candidates.append([node, i, specs[i]])
				if (specs[i] as Dictionary).get("room_light", false):
					lit_rooms[_room_key((node as Node2D).global_position)] = true
	return candidates


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


## Where the sun reaches: the street's floors (an Objects `Floor`'s `is_street()`), less every
## house floor drawn over them (a tower stands on street floors; its rooms are lit from within) and
## the walls round it. A house or an arena has no street: the sun reaches nothing there, as the 2D
## sky is on the street only.
func _sky_mask(world: Node2D) -> void:
	var streets: Array[Rect2] = []
	var houses: Array[Rect2] = []
	for ground: Node2D in world.get_tree().get_nodes_in_group(&"floors"):
		if world.is_ancestor_of(ground):
			_sort_floor(ground, streets, houses)
	var bounds := _bounds(streets)
	var cell := _cell(bounds)
	var image := _blank(bounds, cell, Image.FORMAT_L8)
	_paint(image, streets, bounds.position, cell, Color.WHITE)
	_paint(image, houses, bounds.position, cell, Color.BLACK)
	ToonLight.set_sky(image, Rect2(bounds.position, cell * Vector2(image.get_size())))


## File `ground`'s rectangle under the street's floors or the others' (grown by `floor_reach`); a
## floor with no size is skipped.
static func _sort_floor(ground: Node2D, streets: Array[Rect2], houses: Array[Rect2]) -> void:
	var size: Variant = ground.get("size")
	if not size is Vector2:
		return
	var covers := Rect2(ground.global_position, size as Vector2)
	if ground.has_method(&"is_street") and ground.call(&"is_street"):
		streets.append(covers)
	else:
		houses.append(covers.grow(LightingConfig.floor_reach))


## The room map: each room's id (red the low byte, green the high) over its rect, so a light knows
## which spots are its room's. None while there are no rooms (nothing is clipped).
func _room_mask() -> void:
	if _rooms.is_empty():
		return
	var rects: Array[Rect2] = []
	for room: Dictionary in _rooms:
		rects.append(room["rect"])
	var bounds := _bounds(rects)
	var cell := _cell(bounds)
	var image := _blank(bounds, cell, Image.FORMAT_RG8)
	for k in _rooms.size():
		var id := k + 1
		var colour := Color(float(id & 255) / 255.0, float(id >> 8) / 255.0, 0.0)
		var one: Array[Rect2] = [rects[k]]
		_paint(image, one, bounds.position, cell, colour)
	ToonLight.set_rooms(image, Rect2(bounds.position, cell * Vector2(image.get_size())))


## The rect holding every one of `rects` (empty for none).
static func _bounds(rects: Array[Rect2]) -> Rect2:
	var bounds := Rect2()
	for k in rects.size():
		bounds = rects[k] if k == 0 else bounds.merge(rects[k])
	return bounds


## The px a mask's texel covers over `bounds`: at most `MASK_TEXELS` texels on a side, a whole px.
static func _cell(bounds: Rect2) -> float:
	return maxf(1.0, ceilf(maxf(bounds.size.x, bounds.size.y) / float(MASK_TEXELS)))


## A zeroed image of `format` covering `bounds` in texels of `cell` px.
static func _blank(bounds: Rect2, cell: float, format: Image.Format) -> Image:
	var wide := maxi(1, ceili(bounds.size.x / cell))
	var tall := maxi(1, ceili(bounds.size.y / cell))
	return Image.create(wide, tall, false, format)


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


## Give `piece` its declared light `index`.
func _piece_light(piece: Node2D, index: int, spec: Dictionary) -> void:
	var street: bool = spec.get("street", false)
	var kind: StringName = &"street" if street else spec.get("height", &"low")
	var radius := float(spec.get("radius", 100.0))
	var at: Vector2 = piece.global_transform * (spec.get("offset", Vector2.ZERO) as Vector2)
	# Where the glowing part of the piece is (its declared `lift`, px above the floor), else the
	# height its kind hangs at.
	var lift := float(spec.get("lift", 0.0))
	var lit := Lit.new()
	lit.piece = piece
	lit.offset = spec.get("offset", Vector2.ZERO)
	lit.radius = radius * Lighting3DConfig.range_scale
	lit.light = _omni(
		spec.get("colour", Color.WHITE),
		float(spec.get("energy", 1.0)),
		Vector2(radius, lift if lift > 0.0 else Lighting3DConfig.height_of(kind)),
		kind,
		_room_code(at, street),
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


## A ceiling fixture at the centre of `room` (`{ key, rect }`): an overhead light spanning the room,
## the one kind of light that casts a shadow.
func _fixture(room: Dictionary) -> void:
	var rect: Rect2 = room["rect"]
	var reach := clampf(
		maxf(rect.size.x, rect.size.y) * LightingFixtureConfig.reach_scale
			+ LightingFixtureConfig.reach_pad,
		LightingFixtureConfig.reach_range.x, LightingFixtureConfig.reach_range.y,
	)
	var radius := reach * 0.5
	var lit := Lit.new()
	lit.radius = radius * Lighting3DConfig.range_scale
	lit.light = _omni(
		LightingFixtureConfig.color,
		LightingFixtureConfig.energy,
		Vector2(radius, Lighting3DConfig.fixture_height),
		&"overhead",
		_room_code(rect.get_center(), false),
	)
	lit.light.name = "Fixture_%s" % room["key"]
	lit.light.set_meta(&"shadowable", true)
	lit.light.shadow_opacity = Lighting3DConfig.fixture_shadow_opacity
	lit.energy = lit.light.light_energy
	lit.fixed = rect.get_center()
	add_child(lit.light)
	lit.place()
	lit.bulb = _bulb(rect.get_center(), LightingFixtureConfig.color)
	add_child(lit.bulb)
	_rhythm(lit, LightingFixtureConfig.rhythms, hash([_seed, "fixture", room["key"]]))
	_lit.append(lit)
	_fixtures.append({ "room": room["key"], "light": lit.light })


## The bulb of a ceiling fixture at `at` (px): a small sphere glowing `colour` lightened, over the
## walls' tops (the 2D glyph is drawn over everything), casting no shadow. Its glow follows its
## light's rhythm (`Lit.bulb`).
static func _bulb(at: Vector2, colour: Color) -> MeshInstance3D:
	var unit := RenderConfig.unit
	var ball := SphereMesh.new()
	ball.radius = LightingFixtureConfig.bulb_radius * unit
	ball.height = ball.radius * 2.0
	ball.radial_segments = 8
	ball.rings = 4
	var glowing := colour.lightened(LightingFixtureConfig.bulb_lighten)
	var node := MeshNodes.instance(ball, glowing, false)
	node.name = "Bulb"
	node.position = Vector3(at.x, LightingFixtureConfig.bulb_height, at.y) * unit
	MeshNodes.glow(node, glowing, LightingFixtureConfig.bulb_glow)
	node.set_meta(&"glow", glowing)
	return node


## Draw the light's rhythm from `kinds` with an RNG seeded by `seed_value` (none when it draws
## steady).
func _rhythm(lit: Lit, kinds: Array, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mode := Rhythm.pick(kinds, rng)
	lit.rhythm = null if mode == &"steady" else Rhythm.new(mode, rng.randi())


## An omni light of `colour` at `energy` whose pool (`pool`: x its radius, px out on the floor, the
## 2D pool's; y the height it hangs at, px up); an overhead or street one (`kind`) pools flat
## (`Lighting3DConfig.overhead_slope`), a low one fades from its middle. `room_code` is the room it
## stands in and whether it is a street light (`_room_code`). The toon has no specular, so
## `light_specular` carries the slope, the room and the height over the pool's rim to its `light()`
## (`ToonLight.specular`), which shapes the pool on the floor from them: the pool is the same
## whatever the height the light hangs at.
static func _omni(
	colour: Color, energy: float, pool: Vector2, kind: StringName, room_code: int
) -> OmniLight3D:
	var radius := pool.x
	var height := pool.y
	var overhead := kind != &"low"
	var slope := Lighting3DConfig.overhead_slope if overhead else Lighting3DConfig.low_slope
	var rim := radius * Lighting3DConfig.range_scale
	var unit := RenderConfig.unit
	var l := OmniLight3D.new()
	l.light_color = colour
	l.light_energy = energy
	l.omni_range = Vector2(rim, height).length() * unit
	l.omni_attenuation = 0.0
	l.light_specular = ToonLight.specular(slope, 0, room_code, height * unit, rim * unit)
	l.shadow_enabled = false
	l.set_meta(&"height", height * RenderConfig.unit)
	l.set_meta(&"room", room_code >> 1)
	l.set_meta(&"shadowable", false)
	return l


## The room a light at `at` stands in (its id, 0 for none) times two, plus one for a street light.
func _room_code(at: Vector2, street: bool) -> int:
	return _room_id(at) * 2 + (1 if street else 0)


## The id (index plus one) of the room holding `p`, 0 for none.
func _room_id(p: Vector2) -> int:
	for k in _rooms.size():
		if (_rooms[k]["rect"] as Rect2).has_point(p):
			return k + 1
	return 0


## The key of the room holding world point `p` ("" for none).
func _room_key(p: Vector2) -> String:
	var id := _room_id(p)
	return "" if id == 0 else String(_rooms[id - 1]["key"])


# --- The flashes ---------------------------------------------------------------------------------


## Light a flash for a `shot` at its muzzle or an `explosion` at its burst (EventBus).
func _on_posted(topic: StringName, data: Dictionary) -> void:
	if _pool == null or not data.has("position"):
		return
	match topic:
		&"shot":
			_flash(data["position"], LightingConfig.flashes[&"shot"], 0.0)
		&"explosion":
			var kind: StringName = &"stun" if data.get("kind", &"frag") == &"stun" else &"frag"
			_flash(data["position"], LightingConfig.flashes[kind], float(data.get("radius", 0.0)))


## Light the next pooled flash at world point `at` in `look`, in the room it stands in (the street
## in none), unless its pool is out of the view's reach: a light nobody sees takes no slot.
func _flash(at: Vector2, look: Dictionary, radius: float) -> void:
	var reach := maxf(float(look["reach"]), radius * float(look.get("reach_per_radius", 0.0)))
	var focus: Variant = _focus_point()
	if focus != null:
		var rim := reach * 0.5 * Lighting3DConfig.range_scale
		if (focus as Vector2).distance_to(at) - rim > _reach():
			return
	_pool.flash(at, look, radius, _flash_code(at))


## The room code (`_room_code`) of a flash at `at`: the room holding it, else the room it is within
## `flash_room_slack` px outside (a muzzle in a doorway or against a wall), else the street's.
func _flash_code(at: Vector2) -> int:
	if _rooms.is_empty():
		return 0
	var id := _room_id(at)
	var slack := Lighting3DConfig.flash_room_slack
	for k in _rooms.size():
		if id != 0:
			break
		if (_rooms[k]["rect"] as Rect2).grow(slack).has_point(at):
			id = k + 1
	return id * 2 + (1 if id == 0 else 0)


# --- The cost: which lights are on and which cast a shadow ---------------------------------------


## Where the view is looking (px); null while nothing says.
func _focus_point() -> Variant:
	if not _focus.is_valid():
		return null
	return _focus.call()


## Whether the view moved far enough since the last choice (the focus `refocus` px, or the camera
## zoomed) to make it again.
func _focus_moved() -> bool:
	var at: Variant = _focus_point()
	if at == null:
		return false
	var moved := (at as Vector2).distance_to(Vector2(_seen.x, _seen.y))
	return moved > LightingCostConfig.refocus or absf(_reach() - _seen.z) > 1.0


## How far (px) from the focus a light's pool still reaches the view: half the camera's diagonal.
func _reach() -> float:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null or camera.projection != Camera3D.PROJECTION_ORTHOGONAL:
		return INF
	var size := get_viewport().get_visible_rect().size
	return 0.5 * camera.size * Vector2(size.x / maxf(size.y, 1.0), 1.0).length() / RenderConfig.unit


## Choose which lights are on (the `max_lights` whose pools come nearest the view, ranked by the
## distance to the focus less the pool's radius) and which of those cast a shadow (the
## `shadow_lights` nearest ceiling fixtures, a light keeping its shadow while it is within
## `1 / keep_margin` times the cutoff). A light fades in and out over `fade_time`; `snap` puts every
## light at its end at once. With no focus every light stays on and none casts a shadow.
func choose(snap := false) -> void:
	var at: Variant = _focus_point()
	_counts = Vector3i.ZERO
	if at == null:
		_counts = Vector3i(0, _lit.size(), _lit.size())
		for lit in _lit:
			_switch(lit, true, snap)
		return
	var reach := _reach()
	_seen = Vector3((at as Vector2).x, (at as Vector2).y, reach)
	var near: Array[Lit] = []
	for lit in _lit:
		lit.dist = (lit.world_point() - (at as Vector2)).length()
		lit.key = lit.dist - lit.radius
		if lit.key <= reach:
			near.append(lit)
	_counts.z = near.size()
	near.sort_custom(func(a: Lit, b: Lit) -> bool: return a.key < b.key)
	if near.size() > LightingCostConfig.max_lights:
		near.resize(LightingCostConfig.max_lights)
	_counts.y = near.size()
	for lit in _lit:
		_switch(lit, near.has(lit), snap)
	_cast(near)


## Give the shadows to the nearest `shadow_lights` of `near`'s ceiling fixtures: first the ones
## already casting that are still within `1 / keep_margin` times the cutoff (the last one's
## distance), then the nearest of the rest.
func _cast(near: Array[Lit]) -> void:
	var casters: Array[Lit] = near.filter(
		func(l: Lit) -> bool: return l.light.get_meta(&"shadowable")
	)
	casters.sort_custom(func(a: Lit, b: Lit) -> bool: return a.dist < b.dist)
	var most := LightingCostConfig.shadow_lights
	var cutoff := casters[most - 1].dist if most > 0 and casters.size() >= most else INF
	var chosen: Array[Lit] = []
	for lit in casters:
		if lit.light.shadow_enabled and lit.dist <= cutoff / LightingCostConfig.keep_margin:
			if chosen.size() < most:
				chosen.append(lit)
	for lit in casters:
		if chosen.size() < most and not chosen.has(lit):
			chosen.append(lit)
	for lit in casters:
		lit.light.shadow_enabled = chosen.has(lit)
	_counts.x = chosen.size()


## Make `lit` on or off: it fades toward it (`snap`: it is there now).
func _switch(lit: Lit, on: bool, snap: bool) -> void:
	lit.on = on
	if snap:
		lit.fade = 1.0 if on else 0.0
		_show(lit)
	elif not on and lit.fade <= 0.0:
		_show(lit)


## Show `lit`'s light while it has any fade (written only when it changes); a light hidden casts no
## shadow.
func _show(lit: Lit) -> void:
	var shown := lit.fade > 0.0
	if lit.light.visible == shown:
		return
	lit.light.visible = shown
	if lit.bulb != null:
		lit.bulb.visible = shown
	if not shown:
		lit.light.shadow_enabled = false


## Step `lit`: it fades toward its on or off, and an on light's rhythm sets its energy (written
## only when it changes; an off light costs nothing).
func _advance(lit: Lit, delta: float) -> void:
	var target := 1.0 if lit.on else 0.0
	if lit.fade != target:
		lit.fade = move_toward(lit.fade, target, delta / maxf(LightingCostConfig.fade_time, 0.001))
		_show(lit)
	if lit.fade <= 0.0 and not lit.on:
		if lit.light.light_energy != 0.0:
			lit.light.light_energy = 0.0
		return
	var level := 1.0
	if lit.rhythm != null:
		level = lit.rhythm.step(delta)
		rhythm_steps += 1
	var energy := lit.energy * level * lit.fade
	if energy != lit.light.light_energy:
		lit.light.light_energy = energy
		energy_writes += 1
		if lit.fixed == null and is_instance_valid(lit.piece):
			glow_changed.emit(lit.piece, clampf(0.3 + 0.7 * level, 0.0, 1.1))
		elif lit.bulb != null:
			MeshNodes.glow(
				lit.bulb,
				lit.bulb.get_meta(&"glow"),
				LightingFixtureConfig.bulb_glow * clampf(0.3 + 0.7 * level, 0.0, 1.1) * lit.fade,
			)


## One kept light: its node, the piece it follows and where in the piece's frame (a fixture: a place
## in the world), its full energy and its rhythm (null: steady), the ground reach of its pool, how
## far it is from the focus (`dist`) and how near its pool comes to the view (`key`), whether the
## cost cap keeps it on and how far it has faded in (`fade`, 0 to 1).
class Lit:
	var light: OmniLight3D
	var piece: Variant
	var offset := Vector2.ZERO
	var fixed: Variant = null
	var energy := 1.0
	var rhythm: Rhythm
	var radius := 0.0
	var dist := 0.0
	var key := 0.0
	var on := true
	var fade := 1.0
	## A fixture's bulb (null for a piece's light), glowing with the light.
	var bulb: MeshInstance3D
	## Its piece is freed: the light goes with it.
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
			return
		if (piece as Node2D).global_transform != _xf:
			place()
