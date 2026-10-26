extends RefCounted
## AI BEHAVIOUR sub-domain — SEARCH COVERAGE. How a searcher covers a room by sight: on arrival it
## samples the room into a grid of points, then each tick drops the ones now in its view cone with a
## clear line, turns its gaze to the nearest one still unseen and, when that point is far or behind
## furniture, walks to a new vantage. It is done once `tuning.coverage.target` of the points have
## been seen or the time budget runs out. Owns that state and nothing else: `Behavior` decides when
## a search move begins, calls `begin()` on arrival, `step()` each tick, and re-decides when
## `step()` reports it done.

const Watch := preload("res://scenes/ai/behavior/watch.gd")

## The NPC's tunables, handed in by `setup`, read live from its `tuning.coverage`: `spacing` (the
## room sample grid, px: smaller = finer coverage, more sight rays), `target` (the fraction of
## sampled points that must be SEEN to call a room covered, 1 = all), `budget` (max seconds spent
## covering one room before giving up), `approach` (walk toward an unseen point beyond this range,
## or whose line is blocked; else just turn to it), `margin` (inset, px, from the room's walls where
## sampling starts) and `look_rate` (gaze turn speed, rad/s, while looking around).
var tuning: NpcTuning
## All room sample points this search (kept whole for the coverage fraction + debug).
var points: Array = []
## The subset of `points` not yet SEEN (view cone + line of sight).
var unseen: Array = []
## The unseen point currently being looked at / walked to (for the debug overlay).
var target := Vector2.ZERO
## Key of the room being covered, locked on arrival.
var room := ""
## Seconds left before the coverage gives up on unseeable nooks.
var budget := 0.0
## The Locomotion child (pathing, rooms, navmesh test).
var _loco: Node
## The perception sub-domain (what is in sight).
var _perception: Node
## The NPC's body, handed in once by `bind`.
var _character: Node


## Capture the locomotion, the perception and the NPC's `npc_tuning`. Called once by
## `Behavior.setup()`.
func setup(loco: Node, perception: Node, npc_tuning: NpcTuning) -> void:
	_loco = loco
	_perception = perception
	tuning = npc_tuning


## Hand in the NPC's body. Called once by `Behavior.bind()`.
func bind(character: Node) -> void:
	_character = character


## Forget the room being covered (a new leaf is adopted); points are sampled again on the next
## arrival.
func reset() -> void:
	points = []
	unseen = []
	target = Vector2.ZERO
	room = ""


## Start covering the room on arrival: lock the room, sample it into points to be seen, and begin
## the time budget. The room key may be "" (an explore point in no room); then the sample is empty
## and `step()` finishes at once (a single look), which is the graceful fallback.
func begin() -> void:
	room = _loco.room_key_at(_character.global_position)
	points = sample_room(room)
	unseen = points.duplicate()
	target = _character.global_position
	budget = tuning.coverage.budget


## One tick of coverage: drop every sample point now in sight, then — if the room isn't covered yet
## and the budget holds — turn the gaze toward the nearest unseen point and, when it is far or its
## line is blocked (behind furniture), walk toward it so a new vantage reveals it. True once
## `tuning.coverage.target` of the points are seen or the budget runs out.
func step(delta: float) -> bool:
	for p in _perception.sight.visible_points(unseen):
		unseen.erase(p)
	budget -= delta
	if unseen.size() <= floori(points.size() * (1.0 - tuning.coverage.target)) or budget <= 0.0:
		return true
	var self_pos: Vector2 = _character.global_position
	target = _nearest(self_pos, unseen)
	Watch.ease_gaze(_character, target, tuning.coverage.look_rate, delta)
	if (self_pos.distance_to(target) > tuning.coverage.approach
			or not _perception.has_line_to(null, target)):
		_loco.move_to(_loco.reachable(target))  # Relocate to see a far / occluded part of the room.
	else:
		# Close with a clear line: stand and turn, the cone will catch it.
		_character.movement.move_input = Vector2.ZERO
	return false


## The running coverage as data, for the search debug overlay: every sample point, those still
## unseen, the one being looked at now and the seconds left in the budget.
func debug() -> Dictionary:
	return { "points": points, "unseen": unseen, "target": target, "budget": budget }


## Grid-sample room `room_key` into the points a searcher must SEE to have covered it (also what a
## tactical entry measures the share of a room seen from outside against): the rect inset by
## `tuning.coverage.margin` (to keep points off the walls), stepped by `tuning.coverage.spacing`,
## dropping any point not on the navmesh — i.e. inside a carved furniture footprint — so search
## points sit on open floor, not on furniture (which also keeps unseeable points out of the coverage
## set). Deterministic (no RNG). Empty when the room is unknown (coverage then finishes at once).
func sample_room(room_key: String) -> Array:
	var sampled: Array = []
	for r in _loco.rooms:
		if str(r["key"]) != room_key:
			continue
		var rect: Rect2 = (r["rect"] as Rect2).grow(-tuning.coverage.margin)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			rect = r["rect"]  # Too small to inset; use the whole rect.
		var step_px: float = maxf(tuning.coverage.spacing, 8.0)
		var x: float = rect.position.x + step_px * 0.5
		while x < rect.end.x:
			var y: float = rect.position.y + step_px * 0.5
			while y < rect.end.y:
				var p := Vector2(x, y)
				# Skip furniture holes / off-walkable so points land on open floor.
				if _loco.on_navmesh(p):
					sampled.append(p)
				y += step_px
			x += step_px
		break
	return sampled


## The point in `candidates` nearest `from` (world space); `from` when the list is empty.
func _nearest(from: Vector2, candidates: Array) -> Vector2:
	var best: Vector2 = from
	var best_d := INF
	for p in candidates:
		var d: float = from.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = p
	return best
