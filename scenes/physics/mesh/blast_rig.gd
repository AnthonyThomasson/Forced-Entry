class_name BlastRig
extends RefCounted
## Physics domain, one grenade burst's parts in the 3D render (`BlastFx`): a flash
## (two glowing discs), a shock ring, a fireball (a body, a core and a ring of lobes: spheres) and
## the puffs of smoke (flat discs wearing the stepped puff: a round body and a lighter patch), each
## a unit mesh scaled by `update`, made once and shown or hidden as a burst starts and ends. Each
## part follows its look row's timing and size (`PhysicsExplosionConfig.looks`
## row: a flash fading fast as it swells, a fireball swelling and cooling, smoke drifting out and
## thinning), in stepped tones: the fireball takes the colour of
## the third of its life it is in, and a fade is a dither of the picture's pixels in a few steps,
## so a part is written only when its step changes.

## The share of its life a puff thins out over, at the end: until then it is whole (a flat cloud,
## not a stipple of the floor).
const SMOKE_THIN := 0.35
## The puff's lighter patch, where it sits (a share of the puff's
## radius), how big, how much brighter than the smoke and how opaque.
const PATCH_AT := Vector2(-0.2, -0.2)
const PATCH_SIZE := 0.55
const PATCH_LIFT := 0.1
const PATCH_ALPHA := 0.8

## The puff art, by smoke colour: one texture each, painted once.
static var _puff_art: Dictionary = {}

## The parts: the flash's two discs, the ring, the fireball (body, core, the lobes) and the puffs.
var flash: Array[MeshInstance3D] = []
var ring: MeshInstance3D
var fire: Array[MeshInstance3D] = []
var puffs: Array[MeshInstance3D] = []
## Whether a burst is showing, where it is (px), its look row and how long it has been (s).
var live := false
var at := Vector2.ZERO
var look := {}
var age := 0.0
## The burst's own luck, drawn as it starts: each lobe's (direction, size share), each puff's
## place and drift (px from the burst) and (size share, delay share).
var lobes := PackedVector2Array()
var puff_at := PackedVector2Array()
var puff_drift := PackedVector2Array()
var puff_look := PackedVector2Array()
## The ground the burst lies on (the road a kerb lower) and its height at the burst's place.
var _world: FxWorld
var _ground := 0.0


## The parts under `parent`, hidden, over the ground of `world`.
func _init(parent: Node3D, world: FxWorld) -> void:
	_world = world
	var sphere := _unit("blast_sphere")
	var disc := _unit("blast_disc")
	for i in 2:
		flash.append(_part(parent, disc))
	ring = _part(parent, _unit("blast_ring"))
	for i in 2 + PhysicsExplosionConfig.lobes:
		fire.append(_part(parent, sphere))
	for i in _most_puffs():
		puffs.append(_part(parent, disc, false))


## Paint every burst's smoke and copy it into the toon's atlas ahead of the first burst.
static func warm() -> void:
	for row: Dictionary in PhysicsExplosionConfig.looks.values():
		MeshNodes.warm_textured(_puff_texture(row.get("smoke_color", Color.GRAY)))


## Begin showing a burst of `row` (a `PhysicsExplosionConfig.looks` row) at world `place`.
func start(place: Vector2, row: Dictionary) -> void:
	at = place
	look = row
	age = 0.0
	live = true
	_ground = _world.ground_at(place)
	_draw_lobes()
	_draw_puffs()
	_dress_puffs()
	update(0.0)


## Move the burst on `delta` s: every part's place, size, tone and fade at its age. The burst ends
## when its longest part's life is out.
func update(delta: float) -> void:
	age += delta
	_flash()
	_ring()
	_fireball()
	_smoke()
	var longest := maxf(_life("flash_time"), maxf(_life("fireball_time"), _life("smoke_time")))
	if age >= longest:
		hide_all()


## Hide every part: the burst is over.
func hide_all() -> void:
	live = false
	for part in flash:
		part.visible = false
	for part in fire:
		part.visible = false
	for part in puffs:
		part.visible = false
	ring.visible = false


## A part's life (s): the row's `key`, 0 when it has none.
func _life(key: String) -> float:
	return float(look.get(key, 0.0))


## How far (0..1) through the row's `key` life the burst is.
func _progress(key: String) -> float:
	return clampf(age / maxf(_life(key), 0.001), 0.0, 1.0)


## Draw the fireball's lumps: each a direction round the burst and a size share.
func _draw_lobes() -> void:
	lobes.resize(PhysicsExplosionConfig.lobes)
	var turn := _world.rng.randf() * TAU
	for i in PhysicsExplosionConfig.lobes:
		var way := turn + TAU * float(i) / float(PhysicsExplosionConfig.lobes)
		way += _world.rng.randf_range(-0.3, 0.3)
		lobes[i] = Vector2(way, _world.rng.randf_range(0.5, 0.7))


## Draw the smoke's puffs: where each starts, where it drifts to, how big and how late.
func _draw_puffs() -> void:
	var count := mini(int(look.get("smoke_puffs", 0)), puffs.size())
	var radius := float(look.get("smoke_radius", 0.0))
	puff_at.resize(count)
	puff_drift.resize(count)
	puff_look.resize(count)
	for i in count:
		var way := Vector2.from_angle(_world.rng.randf() * TAU)
		puff_at[i] = way * radius * _world.rng.randf_range(0.2, 0.9)
		puff_drift[i] = (
			way * radius * _world.rng.randf_range(
				0.3,
				0.8,
			) + Vector2(_world.rng.randf_range(-6.0, 6.0), -10.0)
		)
		puff_look[i] = Vector2(_world.rng.randf_range(0.6, 1.0), _world.rng.randf_range(0.0, 0.12))


## Put the burst's smoke on the puffs: the 2D puff painted in its colour, a clear texel cut out.
func _dress_puffs() -> void:
	var art := _puff_texture(look.get("smoke_color", Color.GRAY))
	for part in puffs:
		MeshNodes.textured(
			part,
			art,
			Rect2(-1.0, -1.0, 2.0, 2.0),
			{ "tint": Color.WHITE, "cutout": true },
		)
		MeshNodes.glow(part, Color.BLACK, 0.0)


## The stepped puff in `tint` (a disc and a lighter patch toward the
## upper left, drawn at the 2D look's own pixel), `PhysicsExplosionConfig.pixel` px a texel at the
## biggest puff, a clear texel outside the disc; held by colour.
static func _puff_texture(tint: Color) -> Texture2D:
	if _puff_art.has(tint):
		return _puff_art[tint]
	var step := maxf(PhysicsExplosionConfig.pixel, 1.0)
	var most := 0.0
	for row: Dictionary in PhysicsExplosionConfig.looks.values():
		most = maxf(most, float(row.get("smoke_radius", 0.0)))
	var half := maxi(ceili(most / step), 1)
	var image := Image.create(2 * half, 2 * half, false, Image.FORMAT_RGBA8)
	var lit := Color(tint.r + PATCH_LIFT, tint.g + PATCH_LIFT, tint.b + PATCH_LIFT)
	lit = tint.lerp(lit, PATCH_ALPHA)
	_fill_disc(image, Vector2.ZERO, float(half), Color(tint.r, tint.g, tint.b))
	_fill_disc(image, PATCH_AT * half, PATCH_SIZE * half, lit)
	var art := ImageTexture.create_from_image(image)
	_puff_art[tint] = art
	return art


## `image`'s texels inside the stepped disc of `radius` texels at `centre` (texels from the
## middle), `color`.
static func _fill_disc(image: Image, centre: Vector2, radius: float, color: Color) -> void:
	var half := image.get_width() >> 1
	for row: Array in ExplosionFx.disc_rows(radius, 1.0):
		var y := half + int(round(centre.y)) + int(row[0])
		var cells := roundi(float(row[2]))
		for x in range(half + int(round(centre.x)) - cells, half + int(round(centre.x)) + cells):
			if x >= 0 and x < image.get_width() and y >= 0 and y < image.get_height():
				image.set_pixel(x, y, color)


## The flash: a pale disc over a white one, fading fast, swelling a little.
func _flash() -> void:
	var radius := float(look.get("flash_radius", 0.0))
	var t := _progress("flash_time")
	var fade := pow(1.0 - t, 1.5) if age < _life("flash_time") else 0.0
	var size := radius * (0.7 + 0.3 * t)
	var up := PhysicsBlastMeshConfig.flash_height
	_disc(flash[0], size, look.get("flash_color", Color.WHITE), 0.55 * fade, up)
	_disc(flash[1], size * 0.6, Color.WHITE, fade, up + 0.1)


## The shock ring: a thin ring that runs out past the fireball as it burns, fading.
func _ring() -> void:
	var radius := float(look.get("fireball_radius", 0.0))
	var t := _progress("fireball_time")
	var fade := 1.0 - t if age < _life("fireball_time") else 0.0
	var reach := radius * lerpf(0.4, PhysicsBlastMeshConfig.ring_reach, 1.0 - pow(1.0 - t, 2.0))
	var up := PhysicsBlastMeshConfig.ring_height
	var lift := PhysicsBlastMeshConfig.ring_lift + up * 0.5
	_tone(ring, PhysicsBlastMeshConfig.ring_color, PhysicsBlastMeshConfig.glow)
	_shape(ring, Vector3(at.x, lift, at.y), Vector3(reach, up, reach), fade)


## The fireball: lumps round a body and a core, cooling from a yellow core to deep red in steps,
## a dome that dithers away over its life.
func _fireball() -> void:
	var radius := float(look.get("fireball_radius", 0.0))
	var t := _progress("fireball_time")
	var swell := radius * (1.0 - pow(1.0 - t, 2.5)) * 0.9 + 6.0
	var alpha := 0.0
	if radius > 0.0 and age < _life("fireball_time"):
		alpha = minf(clampf((1.0 - t) / 0.45, 0.0, 1.0), PhysicsBlastMeshConfig.fire_opacity)
	var body := PhysicsBlastMeshConfig.fire_body
	var centre := Vector3(at.x, swell * PhysicsBlastMeshConfig.fire_height, at.y)
	_blob(
		fire[0],
		centre,
		swell * body,
		_heat(PhysicsExplosionConfig.fire_mid, PhysicsExplosionConfig.fire_edge, t),
		alpha,
	)
	_blob(fire[1], centre, swell * (0.5 - 0.3 * t) * body / 0.85,
		_heat(PhysicsExplosionConfig.fire_core, PhysicsExplosionConfig.fire_mid, t), alpha)
	for i in PhysicsExplosionConfig.lobes:
		var reach := PhysicsExplosionConfig.lobe_reach
		var out := Vector2.from_angle(lobes[i].x) * swell * reach * body / 0.85
		var place := centre + Vector3(out.x, 0.0, out.y)
		_blob(
			fire[2 + i],
			place,
			swell * lobes[i].y * body / 0.85,
			PhysicsExplosionConfig.fire_edge,
			alpha,
		)


## The smoke: puffs that drift out, swell, rise and thin out.
func _smoke() -> void:
	var life := _life("smoke_time")
	var t := _progress("smoke_time")
	for i in puffs.size():
		if i >= puff_at.size() or age >= life:
			puffs[i].visible = false
			continue
		_puff(puffs[i], i, t)


## Puff `i` at `t` (0..1) through the smoke's life.
func _puff(part: MeshInstance3D, i: int, t: float) -> void:
	var radius := float(look.get("smoke_radius", 0.0))
	var own := clampf((t - puff_look[i].y) / maxf(1.0 - puff_look[i].y, 0.001), 0.0, 1.0)
	var place := puff_at[i] + puff_drift[i] * (1.0 - pow(1.0 - own, 2.0))
	var size := radius * puff_look[i].x * (0.4 + 0.6 * sqrt(own))
	var rise := PhysicsBlastMeshConfig.smoke_rise * own
	var tall := PhysicsBlastMeshConfig.smoke_squash
	var fade := minf(own / 0.1, 1.0) * minf((1.0 - own) / SMOKE_THIN, 1.0)
	fade = minf(fade, float(look.get("smoke_alpha", 1.0)))
	_shape(
		part,
		Vector3(at.x + place.x, rise + size * tall, at.y + place.y),
		Vector3(size, size * tall, size),
		fade,
	)


## The tone between `hot` and `cool` at `t` through the fireball's life, in `fire_steps` steps.
func _heat(hot: Color, cool: Color, t: float) -> Color:
	var steps := maxi(PhysicsBlastMeshConfig.fire_steps, 1)
	var step := mini(int(t * steps), steps - 1)
	return hot.lerp(cool, float(step) / float(maxi(steps - 1, 1)))


## A flat disc of `radius` px, glowing `tint`, thinning by `fade`, `up` px up.
func _disc(part: MeshInstance3D, radius: float, tint: Color, fade: float, up: float) -> void:
	_tone(part, tint, PhysicsBlastMeshConfig.glow)
	_shape(part, Vector3(at.x, up, at.y), Vector3(radius, 1.0, radius), fade)


## A glowing ball of fire of `radius` px at `place` (px: x, up, y), in `tint`, thinned by `alpha`.
func _blob(part: MeshInstance3D, place: Vector3, radius: float, tint: Color, alpha: float) -> void:
	_tone(part, tint, PhysicsBlastMeshConfig.glow)
	var wide := maxf(radius, 0.01)
	_shape(part, place, Vector3(wide, wide * PhysicsBlastMeshConfig.fire_squash, wide), alpha)


## `part` at `place` (px: x, up, y) scaled by `size`, thinned to `amount` (0: hidden).
func _shape(part: MeshInstance3D, place: Vector3, size: Vector3, amount: float) -> void:
	var levels := float(maxi(PhysicsBlastMeshConfig.fade_levels, 1))
	var step := ceilf(clampf(amount, 0.0, 1.0) * levels) / levels
	part.visible = step > 0.0
	if not part.visible:
		return
	var lifted := Vector3(place.x, place.y + _ground, place.z)
	part.transform = Transform3D(Basis.from_scale(size), lifted * RenderConfig.unit)
	if part.get_meta(&"fx_step", -1.0) != step:
		part.set_meta(&"fx_step", step)
		MeshNodes.fade(part, step)


## `part`'s colour: it glows `tint` by `glow` (a glowing part has no lit colour of its own, so the
## step of its tone is what shows), or is lit `tint` when `glow` is 0; written only when it changed.
func _tone(part: MeshInstance3D, tint: Color, glow: float) -> void:
	if part.get_meta(&"fx_tint", Color.TRANSPARENT) == tint:
		return
	part.set_meta(&"fx_tint", tint)
	MeshNodes.base_color(part, Color.BLACK if glow > 0.0 else tint)
	MeshNodes.glow(part, tint, glow)


## How many puffs the biggest look row has.
func _most_puffs() -> int:
	var most := 0
	for row: Dictionary in PhysicsExplosionConfig.looks.values():
		most = maxi(most, int(row.get("smoke_puffs", 0)))
	return most


## A part under `parent`: `mesh` in the shared toon material, no shadow, hidden; `figured` draws its
## silhouette only, no crease lines.
func _part(parent: Node3D, mesh: Mesh, figured := true) -> MeshInstance3D:
	var part := MeshNodes.instance(mesh, Color.WHITE, false)
	part.visible = false
	MeshNodes.figure(part, figured)
	MeshNodes.moving(part)  # a blast is never remembered: drawn only inside the cone
	parent.add_child(part)
	return part


## The unit mesh named `id` (a sphere, a disc or a ring one px across), scaled by each part.
func _unit(id: String) -> Mesh:
	var key := MeshCache.key(id, Vector2.ONE, Color.WHITE)
	return MeshCache.fetch(key, func() -> Mesh: return _solid(id).build())


## The kit holding the unit solid `id`.
func _solid(id: String) -> MeshKit:
	var kit := MeshKit.new()
	if id == "blast_sphere":
		return kit.sphere(Vector3.ZERO, 1.0, Color.WHITE)
	if id == "blast_disc":
		return kit.cylinder(Vector3.ZERO, 1.0, 1.0, Color.WHITE)
	var profile := PackedVector2Array([
		Vector2(0.92, -0.5), Vector2(1.0, -0.5), Vector2(1.0, 0.5), Vector2(0.92, 0.5),
		Vector2(0.92, -0.5),
	])
	return kit.revolve(profile, Vector3.ZERO, Color.WHITE)
