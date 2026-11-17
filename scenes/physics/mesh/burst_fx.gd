class_name BurstFx
extends RefCounted
## Physics domain, the hit particles of the 3D render (`domain-physics/meshes.md`):
## a burst `HitParticles` makes is a handful of small cubes, each a part of a batch (one of the
## bits, one of the sparks: a spark is the metal style's own "spark" tint, lit whatever the light,
## no
## real light). The burst's own dict says how many, how fast, how wide, how long, what size
## and what colour (the 2D style tables are read again, not copied); each bit is flung off the
## surface at the hit's height, pulled down by `PhysicsMeshConfig.bit_gravity`, slowed by the
## style's damping, lies on the floor if it lands before its life is out and shrinks away over the
## last of it. A bit is a piece of a pool, taken and given back, so nothing is allocated as bursts
## come and go; a burst past the pool shows what fits.

## The cube every bit is, one px across.
var _bits: FxBatch
var _sparks: FxBatch
## The bits and sparks alive.
var _live: Array[FxPiece] = []
## The ground the bits fall to (the road a kerb lower) and the random numbers they are thrown by.
var _world: FxWorld


## Batches under `parent` (the 3D world's frame), over the ground of `world`.
func _init(parent: Node3D, world: FxWorld) -> void:
	_world = world
	var cube := _cube()
	_bits = FxBatch.new(cube, PhysicsMeshConfig.bit_capacity)
	_bits.node.name = "Bits"
	_sparks = FxBatch.new(
		cube, PhysicsMeshConfig.spark_capacity, PhysicsMeshConfig.spark_color,
		PhysicsMeshConfig.spark_glow,
	)
	_sparks.node.name = "Sparks"
	# What flies off a hit is never remembered: drawn only inside the cone the player sees.
	MeshNodes.moving(_bits.node)
	MeshNodes.moving(_sparks.node)
	parent.add_child(_bits.node)
	parent.add_child(_sparks.node)


## How many bits and sparks are alive.
func shown() -> int:
	return _live.size()


## The batch of the bits.
func bits() -> FxBatch:
	return _bits


## The batch of the sparks.
func sparks() -> FxBatch:
	return _sparks


## The pieces alive, oldest first (a list of the caller's own).
func pieces() -> Array[FxPiece]:
	return _live.duplicate()


## A burst: `made` is the dict `HitParticles.spawn` made (its amount, direction, spread, speeds,
## damping, sizes, life, colour and place), flung off a surface at its `height` (0..100, negative:
## the floor).
func burst(made: Dictionary) -> void:
	var batch := _sparks if made["spark"] else _bits
	var color: Color = made["color"]
	var lift := maxf(float(made["height"]), 0.0) * PhysicsMeshConfig.height_scale
	for _i in int(made["amount"]):
		var piece := batch.take(color)
		if piece == null:
			return
		_throw(piece, made, lift)
		_live.append(piece)
		_write(piece)


## Move the bits on `delta` s; a bit whose life is out is given back. True while any is alive.
func process(delta: float) -> bool:
	var i := _live.size() - 1
	while i >= 0:
		var piece := _live[i]
		piece.age += delta
		if piece.age >= piece.life:
			_live[i] = _live[_live.size() - 1]
			_live.pop_back()
			piece.batch.give(piece)
		else:
			_move(piece, delta)
			_write(piece)
		i -= 1
	return not _live.is_empty()


## Set `piece` flying as one particle of `made` does: a random heading within its spread, a speed
## and a size and a life within its ranges.
func _throw(piece: FxPiece, made: Dictionary, lift: float) -> void:
	var spread := deg_to_rad(float(made["spread"]))
	var way := (made["direction"] as Vector2).rotated(_world.rng.randf_range(-spread, spread))
	var speed := _world.rng.randf_range(float(made["speed_min"]), float(made["speed_max"]))
	piece.at = made["at"]
	piece.velocity = way * speed
	piece.rise = speed * PhysicsMeshConfig.bit_lift
	piece.height = lift
	piece.damping = _world.rng.randf_range(float(made["damping_min"]), float(made["damping_max"]))
	var side := _world.rng.randf_range(float(made["size_min"]), float(made["size_max"]))
	piece.size = Vector2(side, side)
	piece.turn = _world.rng.randf() * TAU
	piece.age = 0.0
	piece.life = float(made["life"]) * (1.0 - float(made["life_random"]) * _world.rng.randf())


## One step of a bit's flight: slowed along its heading, falling under gravity, stopped by the
## floor.
func _move(piece: FxPiece, delta: float) -> void:
	var speed := piece.velocity.length()
	if speed > 0.0:
		piece.velocity *= maxf(speed - piece.damping * delta, 0.0) / speed
	piece.at += piece.velocity * delta
	piece.rise -= PhysicsMeshConfig.bit_gravity * delta
	piece.height += piece.rise * delta
	if piece.height <= 0.0:
		piece.height = 0.0
		piece.rise = 0.0


## Write the bit's frame: its place, its height over the floor, its size (shrinking out at the end).
func _write(piece: FxPiece) -> void:
	var left := 1.0 - piece.age / piece.life
	var shrink := clampf(left / PhysicsMeshConfig.bit_shrink, 0.0, 1.0)
	var side := piece.size.x * shrink
	var base := PhysicsMeshConfig.rest_height + piece.height + _world.ground_at(piece.at)
	var basis := Basis(Vector3.UP, piece.turn) * Basis.from_scale(Vector3.ONE * side)
	var origin := Vector3(piece.at.x, base, piece.at.y) * RenderConfig.unit
	piece.batch.place(piece, Transform3D(basis, origin))


## The mesh of a bit: a cube a px across.
func _cube() -> Mesh:
	var key := MeshCache.key("bit", Vector2.ONE, Color.WHITE)
	return MeshCache.fetch(key, func() -> Mesh:
		var box := AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE)
		return MeshKit.new().box(box, Color.WHITE).build()
	)
