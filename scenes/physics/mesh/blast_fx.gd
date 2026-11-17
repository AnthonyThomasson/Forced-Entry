class_name BlastFx
extends RefCounted
## Physics domain, the explosions of the 3D render (`domain-physics/meshes.md`): a
## burst `ExplosionFx.spawn` tells (a flash, a fireball, smoke) is shown by a rig of
## solid shapes (`BlastRig`) taken from a small pool (`PhysicsBlastMeshConfig.rigs`), made with the
## layer; a burst past the pool takes the oldest rig. Its scorch is the ink layer's. The look rows,
## sizes and times are `PhysicsExplosionConfig.looks`'s; the rigs idle, hidden, when no blast is on.

## The rigs, in the order they were made.
var _rigs: Array[BlastRig] = []


## The rigs, as parts of `parent`, in `world`.
func _init(parent: Node3D, world: FxWorld) -> void:
	for i in PhysicsBlastMeshConfig.rigs:
		_rigs.append(BlastRig.new(parent, world))


## How many blasts are showing.
func shown() -> int:
	var count := 0
	for rig in _rigs:
		count += 1 if rig.live else 0
	return count


## The rigs (a test reads their parts).
func rigs() -> Array[BlastRig]:
	return _rigs


## A burst of `row` (a `PhysicsExplosionConfig.looks` row) went off at `at`: take a rig (an idle
## one, else the oldest) and start it.
func burst(at: Vector2, row: Dictionary) -> void:
	if _rigs.is_empty():
		return
	var pick: BlastRig = _rigs[0]
	for rig in _rigs:
		if not rig.live:
			pick = rig
			break
		if rig.age > pick.age:
			pick = rig
	pick.start(at, row)


## Move the blasts on `delta` s. Whether any is still showing.
func process(delta: float) -> bool:
	var busy := false
	for rig in _rigs:
		if rig.live:
			rig.update(delta)
			busy = busy or rig.live
	return busy
