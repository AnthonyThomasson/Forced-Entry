extends RefCounted
## Vision domain: what a `ViewCone` job holds between steps and builds in: the corners found, the
## even fan's ends and hide reaches and its previous hit, the corners the eye sees, the sorted rays
## of the sweep in hand, and the polygons and counts built so far, which `ViewCone` swaps in when
## the job completes (so a reader never sees half of them). Private to `ViewCone`.

## Where the even fan's ray `i` ends (`ViewCone._fan_hide` holds how far a corner is hidden in each
## interval between two of them).
var fan_ends := PackedVector2Array()
## The last fan ray's hit and its distance from the eye.
var previous := {}
var previous_distance := 0.0
## The corners of the shapes about the eye, and those of them the eye sees.
var found: Array = []
var visible: Array = []
## The rays of the sweep in hand, each `[angle, direction, fan index]`, sorted by angle.
var rays: Array = []
## The cone and the bubble built so far, and the counts a test reads for the cost.
var cone := PackedVector2Array()
var bubble := PackedVector2Array()
var corner_rays := 0
var corners_read := 0


## Forget the last job's.
func clear() -> void:
	fan_ends = PackedVector2Array()
	previous = {}
	previous_distance = 0.0
	found = []
	visible = []
	rays = []
	cone = PackedVector2Array()
	bubble = PackedVector2Array()
	corner_rays = 0
	corners_read = 0
