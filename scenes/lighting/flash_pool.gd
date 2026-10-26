extends RefCounted
## Lighting domain (private): the flash pool, `WorldLighting`'s `_pool`. Its lights (the node's
## `Flash1..3`, `LightingConfig.flash_pool` of them) are lit at a `shot`'s muzzle and an
## `explosion`'s burst, each held at full energy for its row's `hold` (the stun's) and then falling
## off to dark over its `life`; and each frame a flash whose centre a living character stands within
## `LightingConfig.body_clear` of its radius leaves the characters out of its shadows. It holds the
## node (a Node, built once with it) for its tree's group `characters`.

## The pooled flash lights.
var lights: Array = []
## The WorldLighting node the flashes are under.
var _node: Node2D
## Each flash's energy as it was lit.
var _flash_energy := PackedFloat32Array()
## Each flash's hold at full energy (s).
var _flash_hold := PackedFloat32Array()
## Each flash's fall-off to dark after its hold (s).
var _flash_life := PackedFloat32Array()
## Each flash's time since it was lit (s).
var _flash_t := PackedFloat32Array()
## The pooled flash lit next.
var _next_flash := 0
## The world's characters (refreshed when the group's size changes).
var _bodies: Array[Node] = []
## The size of the group `characters` when `_bodies` was read.
var _body_count := -1
## This frame: each living character's position (INF for the dead and the gone).
var _body_at := PackedVector2Array()
## Its `body_clear` reach squared.
var _body_reach := PackedFloat32Array()


## The pool of `flashes` (disabled PointLight2Ds under `node`), none lit yet.
func _init(node: Node2D, flashes: Array) -> void:
	_node = node
	lights = flashes
	_flash_energy.resize(lights.size())
	_flash_hold.resize(lights.size())
	_flash_life.resize(lights.size())
	_flash_t.resize(lights.size())
	_flash_hold.fill(0.0)
	_flash_life.fill(0.0)
	_flash_t.fill(0.0)


## Fade every live flash by `delta`: its full energy through its hold, then `energy × left²`,
## disabled at the end of its hold + life.
func step(delta: float) -> void:
	for k in lights.size():
		if _flash_t[k] >= _flash_hold[k] + _flash_life[k]:
			continue
		_flash_t[k] += delta
		var left := 1.0 - clampf((_flash_t[k] - _flash_hold[k]) / _flash_life[k], 0.0, 1.0)
		var l: PointLight2D = lights[k]
		l.energy = _flash_energy[k] * left * left
		l.enabled = left > 0.0


## Light the pooled flash next in turn at world point `at` in `look` (a `LightingConfig.flashes`
## row), its pool at least `radius` × the row's `reach_per_radius` across, held at full energy for
## its `hold`, then falling off to dark over its `life`.
func flash(at: Vector2, look: Dictionary, radius: float) -> void:
	if lights.is_empty():
		return
	var k := _next_flash
	_next_flash = (_next_flash + 1) % lights.size()
	var l: PointLight2D = lights[k]
	var reach := maxf(float(look["reach"]), radius * float(look.get("reach_per_radius", 0.0)))
	l.global_position = at
	l.color = look["color"]
	l.energy = look["energy"]
	l.texture_scale = reach / float((LightingTextureConfig.textures[&"round"] as Vector2i).x)
	l.enabled = true
	_flash_energy[k] = look["energy"]
	_flash_hold[k] = float(look.get("hold", 0.0))
	_flash_life[k] = look["life"]
	_flash_t[k] = 0.0
	# This frame already: a blast at someone's feet must not black out the room it lights.
	clear_bodies()


# --- Characters -----------------------------------------------------------------------------------


## Leave the characters out of the shadows of every lit flash one of them stands in this frame (and
## put them back once none does): the flashes are the only lights the characters shadow. The
## character list is re-read only when the group's size changes, so a frame allocates nothing.
func clear_bodies() -> void:
	var tree := _node.get_tree()
	var count := tree.get_node_count_in_group(&"characters")
	if count != _body_count:
		_body_count = count
		_bodies.assign(tree.get_nodes_in_group(&"characters"))
		_body_at.resize(_bodies.size())
		_body_reach.resize(_bodies.size())
	for i in _bodies.size():
		var body := _bodies[i]
		if not is_instance_valid(body) or body.get(&"is_dead"):
			_body_at[i] = Vector2.INF
			continue
		_body_at[i] = (body as Node2D).global_position
		var reach := float(body.get(&"radius")) * LightingConfig.body_clear
		_body_reach[i] = reach * reach
	for l: PointLight2D in lights:
		_clear_flash(l)


## Flash `l`'s shadow mask: everything, without the characters while one stands within reach of its
## centre.
func _clear_flash(l: PointLight2D) -> void:
	if not l.enabled:
		return
	var mask := LightMasks.ALL_SHADOWS
	var at := l.global_position
	for i in _body_at.size():
		if at.distance_squared_to(_body_at[i]) < _body_reach[i]:
			mask &= ~LightMasks.CHARACTER
			break
	if l.shadow_item_cull_mask != mask:
		l.shadow_item_cull_mask = mask
