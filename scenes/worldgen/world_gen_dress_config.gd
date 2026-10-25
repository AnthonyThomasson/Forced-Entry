class_name WorldGenDressConfig
## Tuning for the run-down dressing (scenes/worldgen/room_dresser.gd): where things gather, the
## clutter, the wear clusters and the neon tubes. A `class_name` holder of `static var`s, read as
## `WorldGenDressConfig.<name>`; there is no instance and no autoload.

## The run-down dressing (room_dresser.gd), each room on RNGs of its own. Where things gather: a
## corner or a wall's foot `reach` px in from the room's walls (`inset` px off a wall's
## face), or `furniture_gap` px beside a solid piece; whatever is placed lies within
## `near` px of a wall line or a solid piece, clear of `jamb` px round a doorway;
## `tries` spots are tried for each.
static var inset: float = 6.0
static var reach: Vector2 = Vector2(4, 30)
static var furniture_gap: Vector2 = Vector2(3, 14)
static var near: float = 44.0
static var jamb: float = 6.0
static var tries: int = 16
## Clutter a room: none with `clutter_none_chance`, two with `clutter_two_chance`, else one; each
## its catalogue size scaled by a factor in `clutter_scale`.
static var clutter_none_chance: float = 0.35
static var clutter_two_chance: float = 0.2
static var clutter_scale: Vector2 = Vector2(0.75, 1.25)
## Wear clusters a room: none with `wear_bare_chance`, else one, plus one more with
## `wear_more_chance` for each of `wear_more_area` (px²) the room is bigger than (so 0-3).
static var wear_bare_chance: float = 0.3
static var wear_more_area: Array[float] = [100_000.0, 200_000.0]
static var wear_more_chance: float = 0.5
## The share of rooms with a neon tube along the foot of a wall.
static var neon_tube_chance: float = 0.5
