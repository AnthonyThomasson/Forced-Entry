extends GameTest
## R10 (ticket #61): shadows. Occluders stand on the walls and on solid pieces (a character has
## none:
## the 3D render shadows it). In one room with a lamp, a TV, a wardrobe, an armchair and a rug:
## - every wall run is covered by a casting LightOccluder2D (sampled along each `wall_segments()`
##   run);
## - each solid piece (the armchair, the wardrobe, the lamp, the TV) carries its own occluder over
##   its footprint, so it follows a shove; the rug, walk-over decor, carries none;
## - shadows by height (`docs/lighting.md` L6): the lamp's light hangs overhead, so only the walls
##   shadow it (its shadow mask meets the wall's occluder mask and not the wardrobe's, the
##   armchair's); the TV's light is low, so the walls and the wardrobe (a tall
##   piece) shadow it, and the armchair (a low piece) do not.
##
## It reads (tests/_lighting/lighting_probe.gd) `WorldLighting` in the group `world_lighting`
## with `lights()`; the lamp's light a PointLight2D under it. The occluders are plain
## LightOccluder2Ds anywhere under the world (a solid piece's under the piece).

const Probe := preload("res://tests/_lighting/lighting_probe.gd")
const ROOM := Rect2(0, 0, 900, 600)


func describe() -> Dictionary:
	return {
		"name": "Walls and solid pieces cast shadows",
		"description": "Casting occluders cover every wall run, sit on each solid piece (not on a "
			+ "rug); the overhead lamp is shadowed by the walls only, the low TV by the walls and "
			+ "the tall wardrobe only.",
		"tags": ["lighting"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()  # it reads the world's own occluders, not the picture's
	s.arena(ROOM)
	s.switch(&"nav.rebake", false)
	s.object(&"lamp", "lamp", Vector2(450, 120), { "neon": "" })
	s.object(&"armchair", "armchair", Vector2(450, 300), { "neon": "" })
	s.object(&"rug", "rug", Vector2(700, 200))
	s.object(&"wardrobe", "wardrobe", Vector2(150, 120), { "neon": "" })
	s.object(&"tv", "tv", Vector2(780, 330), { "neon": "" })


func run(t: TestContext) -> void:
	var wall_occluder := _check_walls(t)
	var piece_occluders := _check_pieces(t)

	# Shadows by height: the overhead lamp by the walls only, the low TV by the walls and the tall
	# wardrobe only.
	var lighting := Probe.require_lighting(t)
	if lighting == null:
		return
	var casters := { "wall": wall_occluder, "wardrobe": piece_occluders.get(&"wardrobe"),
		"armchair": piece_occluders.get(&"armchair") }
	_check_heights(t, lighting, casters)


## Walls: every run covered. A wall's occluder (null for none).
func _check_walls(t: TestContext) -> LightOccluder2D:
	var world: Node = t.world
	var wall_occluder: LightOccluder2D = null
	for wall in world.find_children("*", "Node2D", true, false).filter(
			func(n: Node) -> bool: return n.has_method(&"wall_segments"),
	):
		for seg: PackedVector2Array in wall.wall_segments():
			if seg[0].distance_to(seg[1]) < 1.0:
				continue
			for f in [0.25, 0.5, 0.75]:
				var p: Vector2 = (wall as Node2D).global_transform * seg[0].lerp(seg[1], f)
				var over := Probe.occluders_at(world, p)
				t.check(
					not over.is_empty(),
					"the wall %s is covered by an occluder at %s" % [wall.name, p.round()],
				)
				if not over.is_empty() and wall_occluder == null:
					wall_occluder = over[0]
	return wall_occluder


## Solid pieces: their own occluder over their footprint; walk-over decor none. Piece id -> its
## occluder.
func _check_pieces(t: TestContext) -> Dictionary:
	var piece_occluders := {}
	for id in [&"armchair", &"wardrobe", &"lamp", &"tv"]:
		var piece: Node2D = t.object(id)
		var own := Probe.own_occluders(piece).filter(
			func(o: LightOccluder2D) -> bool: return Probe.holds(o, piece.global_position),
		)
		t.check(not own.is_empty(), "the solid %s carries an occluder over its footprint" % id)
		if not own.is_empty():
			piece_occluders[id] = own[0]
	t.check(
		Probe.own_occluders(t.object(&"rug")).is_empty(),
		"the rug (walk-over decor) carries no occluder",
	)
	return piece_occluders


## The lamp's light is shadowed by the wall's occluder only, the TV's by the wall's and the
## wardrobe's only, of `casters` (name -> occluder, null for none found).
func _check_heights(t: TestContext, lighting: WorldLighting, casters: Dictionary) -> void:
	var shadowed_by := { &"lamp": ["wall"], &"tv": ["wall", "wardrobe"] }
	for id: StringName in shadowed_by:
		var own_lights := Probe.lights_of(lighting, t.object(id))
		if not t.require(not own_lights.is_empty(), "the %s has its light" % id):
			return
		var light: PointLight2D = own_lights[0]
		t.check(light.shadow_enabled, "the %s's light casts shadows" % id)
		for what: String in casters:
			var occ: LightOccluder2D = casters[what]
			if occ == null:
				continue
			var shadows := light.shadow_item_cull_mask & occ.occluder_light_mask != 0
			var wanted: bool = what in shadowed_by[id]
			t.check(
				shadows == wanted,
				"the %s %s the %s's light (mask %d, occluder %d)" % [
					what,
					"shadows" if wanted else "does not shadow",
					id,
					light.shadow_item_cull_mask,
					occ.occluder_light_mask,
				],
			)
