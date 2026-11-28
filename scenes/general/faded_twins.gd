class_name FadedTwins
extends RefCounted
## General domain, which twins the wall fade holds faded (interfaces 26 and 27): the fade dithers
## only a piece's or a wall's MESH, its twin (`TwinSpace`) stays solid, so the player's aim
## (`Pointer.aim_hit`) must look through what the fade has made see-through, not aim at its face.
## Art's `FadeUnit` writes the registry (`hold` when it is more than half faded, `release` when it
## is not, or is gone) and Pointer reads it (`holds`): Art to General only, General knows no Art.
##
## A held entry is a footprint on the floor plan: a thing the fade fades is one unit, a piece or one
## segment of a wall (a wall body has many, only some faded), so what is held is a body (its
## instance id) and a unit index of it, with the footprint (a rectangle turned about up) it stands
## in. A twin of a held body is looked through only where the ray's point is inside one of them.

## How far (px) outside a footprint a point still counts as on it: a ray's point on a face is on
## the footprint's edge.
const PAD := 2.0

## Body instance id -> { unit index -> `[centre, axis, half]` }, the footprint in plan px.
static var _held: Dictionary = {}


## The unit `index` of body `key` is held faded, standing in the rectangle at `centre` whose local x
## axis is `axis` (a unit vector on the plan) with half sizes `half`, all in plan px. Called again,
## it moves the footprint.
static func hold(key: int, index: int, centre: Vector2, axis: Vector2, half: Vector2) -> void:
	if not _held.has(key):
		_held[key] = {}
	(_held[key] as Dictionary)[index] = [centre, axis, half]


## The unit `index` of body `key` is not held faded (any more).
static func release(key: int, index: int) -> void:
	if not _held.has(key):
		return
	var units: Dictionary = _held[key]
	units.erase(index)
	if units.is_empty():
		_held.erase(key)


## Whether the body `key` is held faded where the plan point `plan` is.
static func holds(key: int, plan: Vector2) -> bool:
	var units: Dictionary = _held.get(key, {})
	for index: int in units:
		var box: Array = units[index]
		var offset := plan - (box[0] as Vector2)
		var axis: Vector2 = box[1]
		var half: Vector2 = box[2]
		if (
			absf(offset.dot(axis)) <= half.x + PAD
			and absf(offset.dot(Vector2(-axis.y, axis.x))) <= half.y + PAD
		):
			return true
	return false


## How many units are held (a test reads it).
static func count() -> int:
	var total := 0
	for key: int in _held:
		total += (_held[key] as Dictionary).size()
	return total


## Forget every entry (a test world's restore calls it, so no test leaks one into the next).
static func clear() -> void:
	_held.clear()
