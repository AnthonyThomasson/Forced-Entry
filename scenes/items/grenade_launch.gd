class_name GrenadeLaunch
extends RefCounted
## What `GrenadeArc.plan` answers: the throw to make, as its launch velocity and the arc it flies.

## An arc that clears everything between the hand and where it lands exists (false: the best that
## could be done, which strikes something).
var ok := false
## The throw is aimed past what the arm reaches: the arc is the farthest one, and it rolls on.
var capped := false
## The launch: across the floor (unit direction, plan space) at `speed` px/s, and up at `rise` px/s.
var direction := Vector2.RIGHT
var speed := 0.0
var rise := 0.0
## The centre's height at the top of the arc (px) and the seconds to its first touchdown.
var apex := 0.0
var time := 0.0
## Where it first touches down (plan point) and where it is expected to come to rest: the aim itself
## for an arc planned in free air, where the flight over the floor rests for one `verify`ed.
var touchdown := Vector2.ZERO
var rest := Vector2.ZERO
