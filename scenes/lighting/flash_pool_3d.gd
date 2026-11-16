extends RefCounted
## Lighting domain (private): the 3D flash pool, `WorldLighting3D`'s.
## `Lighting3DConfig.flash_lights` `OmniLight3D`s, lit at a `shot`'s muzzle and an `explosion`'s
## burst from the 2D flash looks (`LightingConfig.flashes`: colour, energy, pool, `hold`, `life`),
## each held at full energy for its row's `hold` (the stun's) and then falling off to dark over its
## `life` (`energy x left^2`, as 2D). The pool is the cap: a new flash takes a dark light, else the
## oldest lit one. A flash is not cast (no shadow, outside the shadow cap) and stays in its room by
## the room code its caller gives (`docs/lighting.md` L9-3D); the vision mask dims it where the
## player does not see, as every light. A row with a `wash` lifts the toon cap while it is lit
## (`wash()`), so a stun whitens what it reaches.

## The pooled flash lights.
var lights: Array[OmniLight3D] = []
## The cap lift (`wash()`) last written to the toon light.
var lifted := 0.0
## Each flash's energy as it was lit, its hold and life (s), its wash and its time since lit (s;
## a flash is lit while this is under hold + life).
var _energy := PackedFloat32Array()
var _hold := PackedFloat32Array()
var _life := PackedFloat32Array()
var _wash := PackedFloat32Array()
var _t := PackedFloat32Array()
## The order each was lit in (the lowest is the oldest) and the next number.
var _order := PackedInt32Array()
var _next := 0


## `count` unlit flash lights under `parent`.
func _init(parent: Node3D, count: int) -> void:
	for k in count:
		var l := OmniLight3D.new()
		l.name = "Flash%d" % (k + 1)
		l.visible = false
		l.shadow_enabled = false
		l.omni_attenuation = 0.0
		l.set_meta(&"flash", true)
		parent.add_child(l)
		lights.append(l)
	_energy.resize(count)
	_hold.resize(count)
	_life.resize(count)
	_wash.resize(count)
	_t.resize(count)
	_order.resize(count)
	_t.fill(INF)


## Light the pooled flash a new one takes (a dark one, else the oldest) at `at` (the 3D point, px
## x and z, the height `Lighting3DConfig.flash_height`) in `look` (a `LightingConfig.flashes` row),
## its pool at least `radius` x the row's `reach_per_radius` across, in the room `room_code` says
## (`WorldLighting3D._room_code`). Returns the light, null for an empty pool.
func flash(at: Vector2, look: Dictionary, radius: float, room_code: int) -> OmniLight3D:
	if lights.is_empty():
		return null
	var k := _slot()
	var reach := maxf(float(look["reach"]), radius * float(look.get("reach_per_radius", 0.0)))
	var l := lights[k]
	var unit := RenderConfig.unit
	var height := Lighting3DConfig.flash_height
	l.position = Vector3(at.x * unit, height * unit, at.y * unit)
	l.light_color = look["color"]
	l.light_energy = look["energy"]
	l.omni_range = Vector2(
		reach * 0.5 * Lighting3DConfig.range_scale,
		height,
	).length() * unit
	l.light_specular = (Lighting3DConfig.low_slope + 4.0 * float(room_code)) * 0.5
	l.set_meta(&"room", room_code >> 1)
	l.set_meta(&"at", at)
	l.visible = true
	_energy[k] = look["energy"]
	_hold[k] = float(look.get("hold", 0.0))
	_life[k] = look["life"]
	_wash[k] = float(look.get("wash", 0.0))
	_t[k] = 0.0
	_order[k] = _next
	_next += 1
	return l


## Fade every live flash by `delta`: its full energy through its hold, then `energy x left^2`, dark
## (hidden) at the end of its hold and life.
func step(delta: float) -> void:
	for k in lights.size():
		if _t[k] >= _hold[k] + _life[k]:
			continue
		_t[k] += delta
		var l := lights[k]
		var left := 1.0 - clampf((_t[k] - _hold[k]) / maxf(_life[k], 0.001), 0.0, 1.0)
		var energy := _energy[k] * left * left
		if energy != l.light_energy:
			l.light_energy = energy
		if left <= 0.0:
			l.visible = false


## How many flashes are lit now.
func lit_count() -> int:
	var n := 0
	for l in lights:
		if l.visible:
			n += 1
	return n


## How much the toon cap is lifted now: the largest of the lit flashes' `wash` times what is left
## of their energy.
func wash() -> float:
	var most := 0.0
	for k in lights.size():
		if lights[k].visible and _wash[k] > 0.0:
			most = maxf(most, _wash[k] * lights[k].light_energy / maxf(_energy[k], 0.001))
	return most


## The slot the next flash takes: a dark one, else the oldest.
func _slot() -> int:
	var oldest := 0
	for k in lights.size():
		if not lights[k].visible:
			return k
		if _order[k] < _order[oldest]:
			oldest = k
	return oldest
