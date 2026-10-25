class_name Footfall extends RefCounted
## A foot landing, as `BloodFootprints.step` reads it: where the sole lies, which way its toes
## point, its size, which side its arch faces and how fast the walker goes. The walker (the
## Character domain) fills every field from its solved rig.

## The middle of the sole, world px.
var at: Vector2 = Vector2.ZERO
## The unit direction the toes point.
var direction: Vector2 = Vector2.RIGHT
## The sole's length, px.
var length: float = 0.0
## The sole's width, px.
var width: float = 0.0
## Which side of the direction's frame (+y = `direction.orthogonal()`) the arch faces: +1 or -1.
var inner: float = 1.0
## The walker's speed, px/s.
var speed: float = 0.0
