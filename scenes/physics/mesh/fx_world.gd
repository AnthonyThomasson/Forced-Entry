class_name FxWorld
extends RefCounted
## Physics domain, what the 3D effects share about the world they lie in (#193 phase 2;
## `domain-physics/meshes.md`): how high the ground is under a spot, and a random source of their
## own. The ground is a `Callable` from a world point (2D px) to a height offset (px, 0 on the
## pavement the effects' heights count from): the one Main hands to `PhysicsMeshes.install`, built
## from the street's road rects (Objects' `StreetGround`), so a mark on the road lies a kerb lower;
## none means a flat ground. The random source is private: the 3D look draws its luck from it and
## never from the global one, so the 2D sim's random sequence is the same with or without 3D.

## The effects' own random numbers.
var rng := RandomNumberGenerator.new()
var _ground: Callable


## A world over `ground` (a `Callable(Vector2) -> float`; invalid for a flat one).
func _init(ground := Callable()) -> void:
	_ground = ground
	rng.randomize()


## The height of the ground at world `at` (px, 0 on the pavement).
func ground_at(at: Vector2) -> float:
	if not _ground.is_valid():
		return 0.0
	return float(_ground.call(at))
