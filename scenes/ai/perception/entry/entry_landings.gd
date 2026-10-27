extends RefCounted
## AI PERCEPTION sub-domain — ENTRY GEOMETRY's landings: where an entry's grenade thrown into a room
## by a doorway comes down (`docs/grenades.md` G18, `docs/leadership.md` LD14), the one rule the
## stack's thrower aims by (the behaviour's `entry_grenade.gd`) and an ambush post is shielded by
## (`entry_posts.gd`). Every call takes the way in's entry geometry `g` (`AgentEntry.geometry`: the
## doorway's centre `pos`, the unit normal `out` of the room, `along` its wall, the room's `rect` as
## `room`). Static, preloaded (no `class_name`).

## How deep into the room and how far across it (shares of the room's depth and width) a grenade is
## aimed, in order of preference (no deeper than it reaches), the least distance (px) from the door
## it lands at, and how far (px) inside the room's walls.
const BANG_DEPTHS := [0.85, 0.7, 0.55]
const BANG_ACROSS := [0.0, 0.2, -0.2]
const BANG_MIN_DEPTH := 120.0
const BANG_INSET := 30.0


## The aim points of an entry's grenade into `g`'s room, in order of preference, each as
## `Vector2(deep, across)` px: `deep` into the room from the doorway along its axis and `across` it
## along the wall, `BANG_DEPTHS` of the room's depth by `BANG_ACROSS` of its width.
static func grid(g: Dictionary) -> Array:
	var depth := room_depth(g)
	var width := absf((g["room"] as Rect2).size.dot((g["along"] as Vector2).abs()))
	var out: Array = []
	for d: float in BANG_DEPTHS:
		for a: float in BANG_ACROSS:
			out.append(Vector2(depth * d, width * a))
	return out


## How deep (px) `g`'s room runs from the doorway, along its axis: to its farthest corner.
static func room_depth(g: Dictionary) -> float:
	var door: Vector2 = g["pos"]
	var room: Rect2 = g["room"]
	var depth := 0.0
	for c: Vector2 in [
			room.position,
			Vector2(room.end.x, room.position.y),
			room.end,
			Vector2(room.position.x, room.end.y),
	]:
		depth = maxf(depth, (door - c).dot(g["out"]))
	return depth


## The point a grenade thrown from `spot` at aim point `at` (`grid`: `deep` px into `g`'s room, x,
## and `across` px across it, y) lands at: that point, or, when it is beyond `reach` of the spot,
## the farthest point the same distance across that is within it (a room deeper than the grenade
## reaches: it goes in as far as it can). `Vector2.INF` when no point that far across is within
## reach.
static func aim(g: Dictionary, spot: Vector2, at: Vector2, reach: float) -> Vector2:
	var door: Vector2 = g["pos"]
	var out: Vector2 = g["out"]
	var q: Vector2 = door + (g["along"] as Vector2) * at.y - spot
	var b := q.dot(out)
	var room_left := b * b - q.length_squared() + reach * reach
	if room_left < 0.0:
		return Vector2.INF
	return q + spot - out * minf(at.x, b + sqrt(room_left) - 1.0)


## Whether a grenade may land at `target`: inside `g`'s room, `BANG_INSET` clear of its walls, and
## at least `BANG_MIN_DEPTH` from the doorway.
static func lands(g: Dictionary, target: Vector2) -> bool:
	return ((g["room"] as Rect2).grow(-BANG_INSET).has_point(target)
			and target.distance_to(g["pos"]) >= BANG_MIN_DEPTH)


## Where an entry's grenade of throw `reach` (px) thrown in by `g`'s doorway may land, as reckoned
## from the doorway's centre: each aim point of `grid`, pulled back to within `reach` (`aim`), that
## `lands`, in order of preference.
static func spots(g: Dictionary, reach: float) -> Array:
	var out: Array = []
	for at: Vector2 in grid(g):
		var target := aim(g, g["pos"], at, reach)
		if lands(g, target) and not out.has(target):
			out.append(target)
	return out
