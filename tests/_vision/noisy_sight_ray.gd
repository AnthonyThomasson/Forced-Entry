extends SightRay
## A sight ray whose long level cast reports a hit the engine's float noise could report: a ray
## along the x axis that passes `NOISE` px outside a shape's face is answered as if it had struck
## the shape (the cast is made `NOISE` px nearer the shape), as the engine does for an edge-on ray
## on a dented face (`docs/player-vision.md`, V1 cost). Not a test: a view's `ViewCone` is given
## one in place of its own (`tests/vision/fan_hide_margin_keeps_grazing_corner_test.gd`).

## How far (px) outside a face the noisy hit lands: the engine's hit positions are off by up to
## about this much.
const NOISE := 0.0175
## A cast this long along the x axis is the fan's centre ray: no other cast of the view is.
const LONG := 1000.0

## How many casts were answered with the noisy hit.
var noisy := 0


func cast(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> Dictionary:
	var aside := Vector2.ZERO
	if absf(to.y - from.y) < 1e-3 and to.x - from.x > LONG:
		aside = Vector2(0.0, NOISE)
	var found := super.cast(space, from, to)
	if found.is_empty() and aside != Vector2.ZERO:
		found = super.cast(space, from + aside, to + aside)
		noisy += 0 if found.is_empty() else 1
	return found
