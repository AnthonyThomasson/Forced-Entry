class_name FadeHold
extends RefCounted
## Art domain, what one fade unit tells General's `FadedTwins` (`fade_unit.gd`, `wall_fade.gd`): the
## body it is of (`key`, its instance id), its index in that body (a wall's segment, 0 for a piece)
## and whether it is held faded now, so the player's aim looks through a twin whose mesh is
## see-through. A unit is held while it is more than `HELD_AT` faded, and no longer. Nothing is
## written per frame: `FadedTwins` is told when the unit passes the half, and when it moves.

## How far faded a unit is when the aim looks through it.
const HELD_AT := 0.5

## The body and the unit's index in it, and whether `FadedTwins` has it held now.
var key := 0
var index := 0
var holding := false


## The unit is `faded` of the way and stands at `box`: it is held (or no longer) when that passes
## the half.
func update(faded: float, box: FadeBox) -> void:
	if (faded > HELD_AT) == holding:
		return
	if holding:
		release()
	else:
		holding = true
		move(box)


## The unit stands at `box` now: while it is held, `FadedTwins` has its footprint.
func move(box: FadeBox) -> void:
	if holding:
		var unit := RenderConfig.unit
		FadedTwins.hold(key, index, box.centre / unit, box.axis, box.half / unit)


## The unit is not held faded (any more): its mesh left, a segment was rebuilt, or it came back.
func release() -> void:
	if holding:
		holding = false
		FadedTwins.release(key, index)
