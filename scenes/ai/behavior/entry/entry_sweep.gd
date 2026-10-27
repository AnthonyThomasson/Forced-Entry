extends RefCounted
## AI BEHAVIOUR sub-domain — TACTICAL ENTRY's sweep, a part the entry holds as `sweep`:
## where the entrant looks and what it sees (E3 to E5, E8): its gaze, the room's sample
## points and corners seen from outside, the crossing to its corner, the corner held, the
## room cleared by sight, the doorways on out of it and, alone, each looked through in turn.
## Built once by the entry (`entry.gd`) on its shared `state` and `world`, it holds nothing
## else: what it needs of the entry and of its other parts is handed in at the call (`entry`),
## so no reference cycle forms.

## The entry this part is one of, handed in at the call (never held: it holds the part).
const Entry := preload("res://scenes/ai/behavior/entry.gd")
const Watch := preload("res://scenes/ai/behavior/watch.gd")
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
const EntryState := preload("res://scenes/ai/behavior/entry/entry_state.gd")
const EntryWorld := preload("res://scenes/ai/behavior/entry/entry_world.gd")
## How far (px) back from a doorway, inside the cleared room, a member stands to cover it.
const COVER_DEPTH := 110.0
## How far (px) a cover spot is kept off the cleared room's walls.
const COVER_INSET := 20.0
## How close (px) an entrant walks into its corner: all the way, since a few px short of a corner
## beside the doorway (a small room's) is still in the way of the one crossing behind it.
const CORNER_REACH := 6.0
## Most seconds the committed crossing may take before it gives up the commitment (a blocked
## doorway).
const CROSS_CAP := 6.0
## Gaze (rad) within which the look through the door has settled at a pie step.
const GAZE_SETTLED := 0.12

## The entry's state, shared with it and its other parts.
var state: EntryState
## What the entry works with, shared with it and its other parts.
var world: EntryWorld
## The corner this NPC enters to.
var corner := Vector2.INF
## The room's sample points (coverage grid).
var points: Array = []
## Those not yet seen from outside.
var unseen: Array = []
## Index into the geometry's corners -> seen during the pie.
var corners_seen := {}
## Current gaze angle (rad), eased toward what the phase looks at.
var look_angle := 0.0
## Seconds held at the current spot (the corner).
var dwell := 0.0
## The doorways on out of the cleared room: { id, into, pos, spot, aim }.
var watch: Array = []
## Alone: the doorways still to look through, in turn.
var queue: Array = []


## Built once by the entry, on its `state` and `world`.
func _init(entry_state: EntryState, entry_world: EntryWorld) -> void:
	state = entry_state
	world = entry_world


## Forget the running entry's sweep (`Entry.reset`).
func reset() -> void:
	corner = Vector2.INF
	points = []
	unseen = []
	corners_seen = {}
	dwell = 0.0
	watch = []
	queue = []


## Drop every room point and corner now in sight from the unseen sets, and update the share seen.
func note_seen(entry: Entry) -> void:
	for p in world.perception.sight.visible_points(unseen):
		unseen.erase(p)
	if not points.is_empty():
		entry.pie.seen_fraction = 1.0 - float(unseen.size()) / float(points.size())
	var corners: Array = state.geo["corners"]
	var unseen_corners: Array = []
	for i in corners.size():
		if not corners_seen.get(i, false):
			unseen_corners.append(corners[i]["pos"])
	for p in world.perception.sight.visible_points(unseen_corners):
		for i in corners.size():
			if corners[i]["pos"] == p:
				corners_seen[i] = true


## Commit to the crossing: pick the corner for this member's place in the order, radio `going_in`,
## go.
func start_cross(entry: Entry, team: Array) -> void:
	var order := entry.readiness.members_before(entry).filter(
		func(m): return StackClaim.crossing(m["step"]),
	).size()
	corner = _corner_for(entry,
		order,
		team.any(func(m): return int(m["side"]) != 0 and int(m["side"]) != state.side),
	)
	entry.approach.set_phase("cross")
	entry.radio.say(entry, "going_in")


## The corner (or spot) the member `order`-th through the door enters to. The point buttonhooks to
## the corner on the door's wall on its own side; alone, it goes to that wall's corner on the side
## away from where it stands, so it crosses the room's front; on a stack `split` across the door
## (E19) it crosses to the corner on the far side. The second crosses to the hard corner on the
## other side from its own (on the door's wall, else any hard one there, else the near one): on a
## split stack, the side the point came from. Later members take a spot inside, off the axis.
func _corner_for(entry: Entry, order: int, split := false) -> Vector2:
	var corners: Array = state.geo["corners"]
	if order == 0:
		if split:
			return _pick_corner(corners, -state.side, true)
		var own := state.side
		if state.solo:
			own = -entry.pie.side if entry.pie.sides > 0 else -state.side
		return _pick_corner(corners, own, false)
	if order == 1:
		return _pick_corner(corners, -state.side, true)
	var door: Vector2 = state.geo["pos"]
	return world.loco.reachable(door - (state.geo["out"] as Vector2) * 90.0
			+ (state.geo["along"] as Vector2) * state.side
				* (float(state.geo["width"]) * 0.5 + Entry.SPOT_SPACING * (order - 1)))


## The corner on side `on`: on the door's own wall first (a hard one when `hard_first`), else a hard
## one on that side, else any on that side.
func _pick_corner(corners: Array, on: int, hard_first: bool) -> Vector2:
	var best := Vector2.INF
	var best_rank := 99
	for c in corners:
		if c["side"] != on:
			continue
		var rank := 0 if c["near"] else 2
		if hard_first and not c["hard"]:
			rank += 1
		if rank < best_rank:
			best_rank = rank
			best = c["pos"]
	return best


## Through the threshold to the corner without stopping, gaze across the room; `in` once in the room
## and off the door's axis, then on to the corner.
func tick_cross(entry: Entry, delta: float) -> void:
	world.loco.move_to(corner, CORNER_REACH)
	if world.character.movement.move_input == Vector2.ZERO and not world.loco.crowd.holding():
		# Never stand in the funnel (unless a body is in the way).
		var to_corner: Vector2 = corner - world.character.global_position
		world.character.movement.move_input = to_corner.normalized()
	look_toward(_across_from(corner), delta, 3.0)
	var rel: Vector2 = world.character.global_position - (state.geo["pos"] as Vector2)
	var through: bool = (rel.dot(state.geo["out"]) < -StackClaim.THROUGH_DEPTH
			and absf(rel.dot(state.geo["along"])) > float(state.geo["width"]) * 0.5)
	if (through
			or state.clock > CROSS_CAP
			or world.character.global_position.distance_to(corner) <= Entry.WAYPOINT_REACH):
		entry.radio.say(entry, "in")
		entry.approach.set_phase("corner")


## Where to look from a corner: across the room, at the far side opposite it.
func _across_from(p: Vector2) -> Vector2:
	var room: Rect2 = state.geo["room"]
	return room.get_center() * 2.0 - p


## Into the corner, then hold it looking across the room for `tuning.entry.corner_dwell` (even when
## the team has already called the room clear: its sector is covered either way); then clear the
## room by sight.
func tick_corner(entry: Entry, team: Array, delta: float) -> void:
	look_toward(_across_from(corner), delta, 3.0)
	if not entry.approach.arrived_at(corner, CORNER_REACH) and state.clock < CROSS_CAP:
		world.loco.move_to(corner, CORNER_REACH)
		dwell = 0.0
		return
	world.character.movement.move_input = Vector2.ZERO
	dwell += delta
	if dwell >= world.tuning.entry.corner_dwell and cleared_by_team(team):
		entry.hold.finish(entry, team)
	elif dwell >= world.tuning.entry.corner_dwell:
		entry.approach.set_phase("clear")
		world.coverage.begin()


## Cover the room by sight; when done, and the rest of the stack is in too (or has had
## `tuning.entry.ready_timeout` to come), radio it clear and move on. An ally that radioed it clear
## first ends this NPC's search.
func tick_clear(entry: Entry, team: Array, delta: float) -> void:
	if cleared_by_team(team):
		entry.hold.finish(entry, team)
		return
	if not entry.hold.covered:
		entry.hold.covered = world.coverage.step(delta)
		return
	world.character.movement.move_input = Vector2.ZERO
	look_toward(_across_from(world.character.global_position), delta)
	var coming := team.filter(
		func(m): return not StackClaim.through(m["step"]) and m["step"] != "claim",
	)
	if coming.is_empty() or state.clock >= world.tuning.entry.ready_timeout + CROSS_CAP:
		entry.radio.say(entry, "clear", { "cleared_room": state.into })
		entry.hold.finish(entry, team)


## Whether an ally of this entry has radioed the room clear (its latest call may already be the
## watch it keeps after).
func cleared_by_team(team: Array) -> bool:
	return team.any(func(m): return StackClaim.cleared(m["step"]))


## The doorways on out of the cleared room, each with where to stand to cover it and where to point
## the gun: inside the cleared room, `COVER_DEPTH` back from the doorway and off its axis on the
## side this NPC is on, looking through it.
func watch_doors() -> Array:
	var out: Array = []
	var room: Rect2 = (state.geo["room"] as Rect2).grow(-COVER_INSET)
	for d in world.perception.entry.watch_doors(state.into, state.opening):
		var g: Dictionary = world.perception.entry.geometry(d["id"], d["into"])
		if g.is_empty():
			continue
		var pos: Vector2 = g["pos"]
		var back: Vector2 = g["out"]  # Away from the room beyond: into the cleared room.
		var along: Vector2 = g["along"]
		var lean := 1.0 if (world.character.global_position - pos).dot(along) >= 0.0 else -1.0
		var spot := pos + back * COVER_DEPTH + along * lean * (float(g["width"]) * 0.5 + 20.0)
		spot = world.loco.reachable(spot.clamp(room.position, room.end))
		out.append({ "id": d["id"], "into": d["into"], "pos": pos, "spot": spot,
			"aim": pos + (pos - spot).normalized() * 300.0 })
	return out


## Alone in the cleared room: look through the next doorway on in turn, `tuning.entry.watch_dwell`
## once the gaze has settled, then on to the next; done after the last.
func tick_sweep(entry: Entry, delta: float) -> void:
	world.character.movement.move_input = Vector2.ZERO
	var w: Dictionary = queue[0]
	var at: Vector2 = w["pos"]
	if look_toward(at + (at - world.character.global_position).normalized() * 300.0, delta, 2.0):
		dwell += delta
	else:
		dwell = 0.0
	if dwell >= world.tuning.entry.watch_dwell:
		queue.pop_front()
		dwell = 0.0
		if queue.is_empty():
			entry.hold.end_hold(entry)


## Look where it walks: a few paces down its path (the door it is lining up), not the next waypoint
## beside it.
func aim_travel() -> void:
	if world.character.movement.move_input == Vector2.ZERO:
		return
	var ahead: Vector2 = world.eyes.travel_point()
	var toward: Vector2 = ((ahead - world.character.global_position)
			if ahead != Vector2.INF
			else world.character.movement.move_input)
	var from: Vector2 = world.character.global_position
	world.character.movement.aim_point = from + toward.normalized() * 100.0
	look_angle = toward.angle()


## Turn the gaze toward `point` at `tuning.coverage.look_rate` (× `speed`); true once it is there.
func look_toward(point: Vector2, delta: float, speed := 1.0) -> bool:
	look_angle = Watch.ease_gaze(
		world.character,
		point,
		world.tuning.coverage.look_rate * speed,
		delta,
	)
	var desired := (point - (world.character.global_position as Vector2)).angle()
	return state.gaze_held or absf(angle_difference(look_angle, desired)) <= GAZE_SETTLED
