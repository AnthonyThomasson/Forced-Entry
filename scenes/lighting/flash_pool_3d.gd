extends RefCounted
## Lighting domain (private): the 3D flash pool, `WorldLighting3D`'s.
## `Lighting3DConfig.flash_lights` `OmniLight3D`s, lit at a `shot`'s muzzle and an `explosion`'s
## burst from the 2D flash looks (`LightingConfig.flashes`: colour, energy, pool, `hold`, `life`),
## each held at full energy for its row's `hold` (the stun's) and then falling off to dark over its
## `life` (`energy x left^2`, as 2D). The pool is the cap: a new flash takes a dark light, else the
## lit one with the least left to run. A flash is not cast (no shadow, outside the shadow cap) and
## stays in its room by the room code its caller gives (`docs/lighting.md` L9-3D); the vision mask
## dims it where the player does not see, as every light. A flash is coded in its `light_specular`
## (a tinted flash or, for a row with a `wash`, a white-out), so the toon light adds it apart from
## the dusk's cap.

## The pooled flash lights.
var lights: Array[OmniLight3D] = []
## Each flash's energy as it was lit, its hold and life (s) and its time since lit (s;
## a flash is lit while this is under hold + life).
var _energy := PackedFloat32Array()
var _hold := PackedFloat32Array()
var _life := PackedFloat32Array()
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
	# Every flash's pool is flat to its middle (the overhead slope), as a ceiling light's: the kind
	# says how the toon light adds it (a tint, or for a row with a `wash` a white-out).
	var washes: bool = look.get("wash", false)
	var kind := 0.5 if washes else 0.25
	l.light_specular = (Lighting3DConfig.overhead_slope + kind + 4.0 * float(room_code)) * 0.5
	l.set_meta(&"room", room_code >> 1)
	l.set_meta(&"at", at)
	l.visible = true
	_energy[k] = look["energy"]
	_hold[k] = float(look.get("hold", 0.0))
	_life[k] = look["life"]
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


## The slot the next flash takes: a dark one, else the lit one with the least left to run (a shot's
## 0.07 s goes before a blast's half second or the stun's 0.78), the oldest among equals.
func _slot() -> int:
	var steal := 0
	var least := INF
	for k in lights.size():
		if not lights[k].visible:
			return k
		var left := _hold[k] + _life[k] - _t[k]
		if left < least or (left == least and _order[k] < _order[steal]):
			steal = k
			least = left
	return steal
