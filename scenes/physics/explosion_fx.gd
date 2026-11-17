class_name ExplosionFx
## Physics System: a grenade's burst (`Physics.spawn_explosion`). A frag is a bright flash, a
## fireball puff that swells and cools, smoke that drifts off and fades, and a scorch left on the
## floor; a stun is thin smoke only (its white flash is the Lighting domain's flash light, lit by
## the `explosion` event: `docs/lighting.md` L9). The 3D render shows the flash, fireball and smoke
## (`PhysicsFxHook.blast_made`, `blast_rig.gd`); the scorch is a mark in the world's `ScorchDecals`
## layer. Looks and timings: `PhysicsExplosionConfig.looks`.


## Put the burst of `kind` at `at` under `world`.
static func spawn(world: Node, at: Vector2, kind: StringName) -> void:
	var look: Dictionary = PhysicsExplosionConfig.looks.get(kind, {})
	if look.is_empty():
		return
	PhysicsFxHook.blast_made(at, look)
	if float(look.get("scorch_radius", 0.0)) > 0.0:
		ScorchDecals.layer(world).burn(at, float(look["scorch_radius"]))


## The rows a disc of `radius` px is drawn in, `step` px each, top to bottom: `[j, y, half]` per
## row, `j` its index (its top `j * step` px off the centre), `y` its middle and `half` how far the
## disc reaches each way along it. The burst's discs (`blast_rig.gd`) and the scorch marks
## (`ScorchDecals`, which jitters the edge) are both stepped by it.
static func disc_rows(radius: float, step: float) -> Array:
	var out := []
	var rows := int(ceil(radius / step))
	for j in range(-rows, rows):
		var y := (float(j) + 0.5) * step
		out.append([j, y, sqrt(maxf(radius * radius - y * y, 0.0))])
	return out
