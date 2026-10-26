extends RefCounted
## AI BEHAVIOUR sub-domain — WATCH. Where an NPC looks when no primitive has a reason to look
## anywhere in particular, and which threat takes its eyes and its gun whatever it is doing
## (docs/gaze-and-fire.md). The rule is one sentence: an NPC is always either looking at (and, when
## it can, shooting) a threat, or watching its doors; never a wall, and never with its back to a
## known threat. Owns the watch stage (`apply`, which `Behavior` runs each tick after the primitive
## has steered, handing itself in), the pick of the threat and the rotating look at a room's
## doorways, and nothing else: `Combat` does the shooting, `Locomotion` the walk it looks down. It
## reads its tunables live from the NPC's `tuning.watch` (the look rate off `tuning.coverage`).

## Doorways nearer than this (px) are not worth watching: the NPC stands in them.
const DOOR_MIN_DISTANCE := 60.0
## Spacing (px) of the points along the path tried for a clear line when a walking NPC picks where
## to look.
const PATH_STEP := 30.0

## The NPC's tunables, handed in by `setup`: `tuning.watch.look_ahead` (how far, px, down its path a
## walking NPC looks), `door_dwell` (seconds a resting NPC looks at one doorway before turning to
## the next), `lost_gaze` (seconds a hostile no longer seen still holds its eyes, while it has a
## clear line to where it was last seen), and `tuning.coverage.look_rate` (the gaze's turn speed,
## rad/s, from one doorway to the next).
var tuning: NpcTuning
## The contact holding the NPC's eyes and gun this tick ({} = none); see `apply`.
var threat: Dictionary = {}
## What set the gaze this tick, for the read-outs: threat / doors / primitive (evade, set by
## `Behavior` while it evades).
var gaze := "primitive"
## The Locomotion child (which room the NPC stands in).
var _loco: Node
## The perception sub-domain (the room's doorways, the clear-line test).
var _perception: Node
## The room whose doorways are being watched.
var _room := ""
## That room's doorway points worth watching, in a turn around the room.
var _doors: Array = []
## Which of them is being looked at.
var _door := 0
## Seconds left looking at it.
var _dwell := 0.0
## The NPC's body, handed in once by `bind`.
var _character: Node


## Ease `character`'s gaze from where it looks now toward `point`, by at most `rate` rad/s over
## `delta`, and aim it there (100 px out); returns the new gaze angle. From the current facing, not
## a stored angle: something else (a threat) may have held its eyes meanwhile. The one way a gaze is
## turned: the doors here, a searcher's unseen points, an entry's pie and corners.
static func ease_gaze(character: Node, point: Vector2, rate: float, delta: float) -> float:
	var self_pos: Vector2 = character.global_position
	var angle := rotate_toward(
		(character.facing as Vector2).angle(),
		(point - self_pos).angle(),
		rate * delta,
	)
	character.movement.aim_point = self_pos + Vector2.from_angle(angle) * 100.0
	return angle


## Capture the locomotion, the perception and the NPC's `npc_tuning`. Called once by
## `Behavior.setup()`.
func setup(loco: Node, perception: Node, npc_tuning: NpcTuning) -> void:
	_loco = loco
	_perception = perception
	tuning = npc_tuning


## Hand in the NPC's body. Called once by `Behavior.bind()`.
func bind(character: Node) -> void:
	_character = character


## The watch stage (docs/gaze-and-fire.md), run by `behavior` after its primitive has steered: an
## NPC is always either looking at (and, when it can, shooting) a threat, or watching its doors,
## never a wall and never with its back to a known threat. A threat (`_pick_threat`: the hostile it
## is fighting or the nearest it sees, else one it saw a moment ago with a clear line to where it
## was) takes the eyes and the gun whatever the primitive is doing: `Combat` shoots it as soon as a
## shot is on, and an empty gun is reloaded. A melee and an engaged NPC in position fight their own
## target and aim at it themselves; an interaction has its own gaze. With nothing to look at, a
## resting NPC (a hold, a reload, a move that has arrived) turns among its room's doorways.
func apply(behavior: Node, delta: float) -> void:
	threat = {}
	gaze = "primitive"
	if _character.use.is_busy() or _own_gaze(behavior):
		return
	var t: Dictionary = _pick_threat(behavior._hostiles, behavior._engage_id)
	if not t.is_empty() and not t["visible"] and not _perception.has_line_to(t["node"], t["pos"]):
		t = {}  # Remembered behind a wall: not worth staring at the wall for.
	if not t.is_empty():
		threat = t
		gaze = "threat"
		_character.movement.aim_point = t["pos"]
		behavior._combat.fire_at_will(t)
		if not behavior._entry.committed():
			behavior._combat.reload_if_dry()
		return
	if _resting(behavior):
		gaze = "doors"
		var door = (behavior.task.params.get("door_pos")
				if behavior.task.primitive in [&"defend", &"ambush"]
				else null)
		if door is Vector2:
			# A defender's gun on its own doorway (D2), an ambusher's on the threshold (LD15).
			ease_gaze(_character, door, tuning.coverage.look_rate, delta)
		else:
			idle_gaze(delta)


## Where a walking NPC looks: the farthest point, up to `tuning.watch.look_ahead` px down the walk
## the nav agent was just given, that it has a clear line to. Along a straight walk that is well
## ahead; at a doorway it is through the door as soon as it can see through, and the wall beside it
## never (the immediate waypoint hugs the jamb, and facing it looks at the jamb). Vector2.INF with
## no walk or no clear point (the caller then looks where it steers).
func travel_point() -> Vector2:
	var walk: Dictionary = _loco.path_ahead()
	if walk.is_empty():
		return Vector2.INF
	var path: PackedVector2Array = walk["path"]
	var from: Vector2 = _character.global_position
	var best := Vector2.INF
	var prev := from
	var walked := 0.0
	for i in range(int(walk["index"]), path.size()):
		var seg := prev.distance_to(path[i])
		var d := 0.0
		while d < seg:
			d = minf(d + PATH_STEP, seg)
			if walked + d > tuning.watch.look_ahead:
				return best
			var p := prev.lerp(path[i], d / seg)
			if not _perception.has_line_to(null, p):
				return best
			best = p
		walked += seg
		prev = path[i]
	return best


## Resting with nothing to look at: turn to each doorway of the room in turn,
## `tuning.watch.door_dwell` s apiece, easing between them. Does nothing outdoors or in a room with
## no doorway in line (the gaze it has stays). A fresh NPC that was never given an aim looks where
## its body points, not at the world's origin.
func idle_gaze(delta: float) -> void:
	var here: Vector2 = _character.global_position
	if _character.movement.aim_point == Vector2.ZERO:
		_character.movement.aim_point = here + (_character.facing as Vector2) * 100.0
	var room: String = _loco.room_key_at(here)
	if room != _room or _dwell <= 0.0:
		_pick_door(room)
	_dwell -= delta
	if _doors.is_empty():
		return
	ease_gaze(_character, _doors[_door], tuning.coverage.look_rate, delta)


## Forget the doorway being watched (a new order is taken): the next resting NPC starts again from
## the nearest.
func reset() -> void:
	_room = ""
	_doors = []
	_dwell = 0.0


## Whether `behavior`'s running primitive keeps its own gaze this tick, so the watch stage leaves it
## be: a melee, an interaction, an engage in position, a throw taking the grenade in hand and
## throwing it, an entry's bang.
func _own_gaze(behavior: Node) -> bool:
	match behavior.task.primitive:
		&"melee", &"interact":
			return true
		&"engage":
			return behavior.task.arrived
		&"throw":
			# Taking the grenade in hand and throwing it: aimed at the spot, not shot at the threat.
			return behavior._combat.throw.stage not in ["walk", "away"]
		&"entry":
			return behavior._entry.phase == "bang"  # Turned away from the door for the stun.
	return false


## Whether `behavior`'s running primitive leaves the NPC standing with nowhere in particular to
## look: a hold, a reload, a move that has arrived (and is not covering the room by sight).
func _resting(behavior: Node) -> bool:
	match behavior.task.primitive:
		&"hold", &"reload":
			return true
		&"move":
			return behavior.task.arrived and not behavior.task.look_around
		&"throw":
			return behavior._combat.throw.stage == "away"
		&"defend", &"ambush":
			return behavior.task.arrived
	return false


## The contact that takes the NPC's eyes from `hostiles` (the known hostile contacts, hostile first
## and nearest first): the one it is fighting if it can see it, else the nearest it can see, else
## the one it is fighting as last seen, else the nearest it saw within `tuning.watch.lost_gaze`
## seconds. {} with none. Seen or not, a contact stays a threat only as far as `apply` finds a line
## to it: a hostile remembered behind a wall is not worth staring at the wall for.
func _pick_threat(hostiles: Array, engaged_id: int) -> Dictionary:
	var lost_gaze: float = tuning.watch.lost_gaze
	var seen := {}
	var engaged := {}
	var recent := {}
	for c in hostiles:
		if c["visible"]:
			if c["id"] == engaged_id:
				return c
			if seen.is_empty():
				seen = c
		elif c["id"] == engaged_id:
			engaged = c
		elif recent.is_empty() and float(c["age"]) <= lost_gaze:
			recent = c
	if not seen.is_empty():
		return seen
	return engaged if not engaged.is_empty() else recent


## Choose the next doorway to watch. On entering a room (or the first time) the nearest in line;
## afterwards the next one round the NPC, so it sweeps all of them.
func _pick_door(room: String) -> void:
	var here: Vector2 = _character.global_position
	var fresh := room != _room or _doors.is_empty()
	if fresh:
		_room = room
		_doors = _doors_of(room)
		_door = _nearest(_doors, here)
	elif not _doors.is_empty():
		_door = (_door + 1) % _doors.size()
	_dwell = tuning.watch.door_dwell


## The room's doorways worth watching from where the NPC stands, ordered by the angle they lie at
## round it: those with a clear line to them and not right under its feet.
func _doors_of(room: String) -> Array:
	var here: Vector2 = _character.global_position
	var points: Array = []
	if room == "":
		return points
	for d in _perception.room_doorways(room):
		var p: Vector2 = d["pos"]
		if here.distance_to(p) >= DOOR_MIN_DISTANCE and _perception.has_line_to(null, p):
			points.append(p)
	points.sort_custom(func(a, b): return (a - here).angle() < (b - here).angle())
	return points


## Index in `points` of the one nearest `from` (0 with none).
func _nearest(points: Array, from: Vector2) -> int:
	var best := 0
	var best_d := INF
	for i in points.size():
		var d: float = from.distance_squared_to(points[i])
		if d < best_d:
			best_d = d
			best = i
	return best
