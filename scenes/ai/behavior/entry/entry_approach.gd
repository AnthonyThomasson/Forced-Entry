extends RefCounted
## AI BEHAVIOUR sub-domain — TACTICAL ENTRY's approach, a part the entry holds as
## `approach`: the walk to its slot (E1, E2, E18): the waypoints out from the wall and along
## it, across in front of the door or round its view, the walk's cap, and what a hold on the
## walk does (a sealed waypoint dropped, the wait on a stack still forming, the back of the
## stack); with the phase changes (`set_phase`) and the tactical reload at the stack (E11).
## Built once by the entry (`entry.gd`) on its shared `state` and `world`, it holds nothing
## else: what it needs of the entry and of its other parts is handed in at the call (`entry`),
## so no reference cycle forms.

## The entry this part is one of, handed in at the call (never held: it holds the part).
const Entry := preload("res://scenes/ai/behavior/entry.gd")
const Locomotion := preload("res://scenes/ai/behavior/locomotion.gd")
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
const EntryState := preload("res://scenes/ai/behavior/entry/entry_state.gd")
const EntryWorld := preload("res://scenes/ai/behavior/entry/entry_world.gd")
## How far (px) out from the wall an entrant crosses in front of a door it must get past.
const CROSS_DEPTH := 140.0
## How far (px) off the walls of the room it stacks in that crossing, and every approach waypoint,
## stays.
const CROSS_INSET := 24.0
## The step (px) the approach's lead past the slot (`claim.lead`) is shortened by where that
## point is off the stack's ground (`AgentPerception.entry_on_stack_side`).
const LEAD_STEP := 8.0
## The farthest (px) an approach waypoint may be moved onto the navmesh and still stand for the
## point it was asked for.
const WAYPOINT_SNAP := 24.0
## The longest (s, from when the hold began) a walk to the stack waits on a teammate of the stack
## still on its way to its own slot before it takes the back of the stack as a walk the stack seals
## does (`Entry.way_blocked`, `held_by_forming`).
const HELD_BY_FORMING_CAP := 3.0
## How long ago (s) a body at rest out of sight may have been seen for a hold's verdict on the slot
## to count it (`_standing_bodies`).
const SEEN_FRESH := 0.5
## Most seconds one entry spends topping its gun off before the crossing (a reload that will not
## start is not waited on forever).
const TOP_OFF_CAP := 8.0

## The entry's state, shared with it and its other parts.
var state: EntryState
## What the entry works with, shared with it and its other parts.
var world: EntryWorld
## The approach's cap (s): `tuning.entry.approach_time` on top of the walk there at walking pace
## (`walk_time`), measured as it is planned.
var cap := 0.0
## Points still to walk through before the current phase's spot.
var waypoints: Array = []
## Seconds this entry has spent topping its gun off.
var _top_off_spent := 0.0
## The approach was laid while the map round the doorway's view was being baked (`_way_round`).
var _round_pending := false
## How many times the walk of this phase has been found sealed (`Entry.way_blocked`).
var blocked_count := 0
## The approach is held by a teammate still on its way and waits for it (`Entry.way_blocked`, at
## most `HELD_BY_FORMING_CAP`).
var forming_wait := false
## Where the member stood when a hold last dropped approach waypoints (`drop_sealed`; INF: none
## since it walked on).
var dropped_at := Vector2.INF


## Built once by the entry, on its `state` and `world`.
func _init(entry_state: EntryState, entry_world: EntryWorld) -> void:
	state = entry_state
	world = entry_world


## Forget the running entry's approach (`Entry.reset`).
func reset() -> void:
	_round_pending = false
	cap = 0.0
	waypoints = []
	_top_off_spent = 0.0
	blocked_count = 0
	forming_wait = false
	dropped_at = Vector2.INF


## The approach's waypoints the hold that blocked its walk seals, dropped: the one it was walking
## to, then each next one at the slot (within `StackClaim.SLOT_REACH` of it: the walk into the slot
## follows anyway) or whose plain way from where the member stands passes the body holding it
## (`Locomotion.seals`), up to the first the hold does not seal (E19's point out from the wall, on
## another way), which is the next tried. True when the approach goes on: a waypoint is left, or the
## hold does not seal the slot for good (`_slot_sealed`: another way reaches it, which the walk is
## held until the locomotion takes). False when it does: the sealed rule's.
func drop_sealed(entry: Entry) -> bool:
	var spot := entry.claim.spot
	if not waypoints.is_empty():
		dropped_at = world.character.global_position
		waypoints.pop_front()
		while not waypoints.is_empty() and _sealed_waypoint(waypoints[0], spot):
			waypoints.pop_front()
	return not waypoints.is_empty() or not _slot_sealed(entry, spot)


## Whether the hold that blocked the approach seals waypoint `p` too (`drop_sealed`): it lies at
## the slot (`spot`, within `StackClaim.SLOT_REACH`: the walk into the slot follows anyway), or its
## plain way from where the member stands passes the body holding it (`Locomotion.seals`).
func _sealed_waypoint(p: Vector2, spot: Vector2) -> bool:
	return p.distance_to(spot) <= StackClaim.SLOT_REACH or world.loco.seals(p)


## Whether the hold seals the slot (at `spot`) for good: a body between the member and its slot, not
## on it. Its plain way passes the body the walk is held by (`Locomotion.seals`) and no way at all
## reaches it with that body and each other body standing still in the way at body width
## (`_standing_bodies`, `AgentPerception.entry_slot_reach`). A body standing on the slot (within
## `Locomotion.PASS_CLEARANCE` of it, Locomotion's own read of a body on the goal) is no seal: the
## walk goes on, and Locomotion ends it at a free spot beside the slot. A way round there is, though
## the steering map does not show it yet (a teammate on its way still crossing it), is no seal. Nor
## is one not known yet (its map still being baked): the hold's next re-plan asks again.
func _slot_sealed(entry: Entry, spot: Vector2) -> bool:
	if world.loco.crowd.held_at().distance_to(spot) < Locomotion.PASS_CLEARANCE:
		return false
	return (world.loco.seals(spot)
			and world.perception.entry_slot_reach(spot, _standing_bodies(entry)) == 0)


## The bodies a hold's verdict on the slot weighs (`_slot_sealed`): the one the walk is held by, and
## every other body at rest the walk knows of (`Locomotion`'s `crowd.bodies`: the teammates standing
## in their slots among them) that it sees now or saw within `SEEN_FRESH` s, but a teammate of this
## stack still on its way to its slot (its claim at `claim`), which moves on. A body last seen
## longer ago is only where it stood then (a teammate gone on into its slot), and a false "sealed"
## gives the slot up, so it does not count.
func _standing_bodies(entry: Entry) -> Array:
	var coming := {}
	for m in entry.claim.stack.team:
		if m["step"] == "claim":
			coming[int(m["id"])] = true
	var out: Array = [world.loco.crowd.held_at()]
	for b in world.loco.crowd.bodies:
		if (coming.has(int(b.get("id", 0)))
				or (b.get("vel", Vector2.ZERO) as Vector2).length() >= Locomotion.REST_SPEED):
			continue
		if b.get("visible", false) or float(b.get("age", INF)) <= SEEN_FRESH:
			out.append(b["pos"])
	return out


## Whether the walk to the stack is held by a teammate of this stack still on its way to its own
## slot (its claim at `claim`: walking there, or moving up), not the human, for less than
## `HELD_BY_FORMING_CAP` since the hold began: the stack forming (two walkers that give way to each
## other stand still a moment), which clears, not the stack keeping this member from its slot. A
## hold by a member in its slot, by the human (its claim stays at `claim` however long it takes) or
## by anyone else is the stack's or the way's, and so is a hold past the cap (two members holding
## each other wait it out together, then the sealed rule parts them, `to_back_or_abort`).
func held_by_forming(entry: Entry) -> bool:
	var id: int = world.loco.crowd.held_by()
	if id == 0 or state.secure or world.loco.crowd.held_time() >= HELD_BY_FORMING_CAP:
		return false
	for m in entry.claim.stack.team:
		if int(m["id"]) == id:
			return m["step"] == "claim" and not bool(m.get("human", false))
	return false


## The walk to the stack is sealed for good: take the back of the stack (`claim.to_back`), else give
## the claim up (`abort`). True when it gave the entry up.
func to_back_or_abort(entry: Entry) -> bool:
	if entry.claim.to_back(entry):
		return false
	entry.radio.say(entry, "abort")
	state.phase = "done"
	return true


## Head for the slot: if on the wrong side of the door with no way round its view (`_way_round`),
## first out from the wall and across in front of it, far out; then (when not already beyond the
## slot along the wall) sideways at that depth to a point past the slot, then in to the wall and
## along it to the slot. With a way round, the walk goes round the view (and the room being entered)
## to the point past the slot. So the last leg runs along the wall, never down the door's axis. The
## point past the slot stops a body's clearance short of the next slot along that side a teammate
## claims (`team`), so the walk never aims at a teammate's body, nor goes round it (E2).
func enter_approach(entry: Entry, stack: RefCounted) -> void:
	set_phase("approach")
	entry.readiness.ready_said = false
	var lead := entry.claim.approach_lead(entry, stack)
	entry.claim.lead = lead
	waypoints = []
	if not entry.claim.on_wall():
		cap = world.tuning.entry.approach_time + walk_time(entry)
		# An open-floor or tail slot (rule 6): the plain way there, which keeps out of the doorway's
		# view.
		return
	_lay_wall_approach(entry, lead)
	# Each inside the room the stack stands in; one that lands off the stack's ground (another
	# doorway's funnel) is left out.
	waypoints = waypoints.map(func(p): return _waypoint(p)).filter(
		func(p): return p != Vector2.INF,
	)
	cap = world.tuning.entry.approach_time + walk_time(entry)


## Lay the waypoints of the walk to a slot against the wall (`enter_approach`), arriving from
## `lead` px past the slot: across in front of the door first when it must (`_cross_in_front`),
## then (when not already beyond the slot along the wall) sideways at that depth to the point past
## the slot, then in to the wall there. The lead is shortened until its points can be walked to
## (`_fit_lead`).
func _lay_wall_approach(entry: Entry, lead: float) -> void:
	var door: Vector2 = state.geo["pos"]
	var out: Vector2 = state.geo["out"]
	var along: Vector2 = state.geo["along"]
	var target := entry.claim.spot
	var target_out := (target - door).dot(out)
	var target_lat := absf((target - door).dot(along))
	var here: Vector2 = world.character.global_position
	var lat := (here - door).dot(along)
	var depth := _cross_in_front(entry, (here - door).dot(out), lat, target_out)
	var deep := _crosses_door(lat) or absf(lat) < target_lat + lead * 0.5
	lead = _fit_lead(entry, lead, depth, deep)
	if deep:
		waypoints.append(_wall_point(maxf(depth, target_out), target_lat + lead))
	waypoints.append(_wall_point(target_out, target_lat + lead))


## The first leg of a walk to a slot on the other side of the door from where the NPC stands, `lat`
## px along the wall and `depth` px out from it: with no way round the doorway's view
## (`_way_round`), out from the wall before crossing the door's front (a waypoint, far out); with
## one, round the view straight to the point past the slot. The depth the rest of the walk runs at:
## `depth` when it crosses nothing, the crossing's depth, or the slot's own (`target_out`) round the
## view.
func _cross_in_front(entry: Entry, depth: float, lat: float, target_out: float) -> float:
	var crossing := _crosses_door(lat)
	var round_way := _way_round(entry.claim.spot) if crossing else 1
	_round_pending = round_way < 0
	if round_way == 0:
		depth = maxf(depth, _cross_depth())
		var door: Vector2 = state.geo["pos"]
		var out: Vector2 = state.geo["out"]
		var along: Vector2 = state.geo["along"]
		waypoints.append(door + out * depth + along * lat)
	elif crossing:
		depth = target_out
	return depth


## Whether a point `lat` px along the doorway's wall lies on the other side of the door from this
## NPC's slot (`side`).
func _crosses_door(lat: float) -> bool:
	return signf(lat) != float(state.side) and absf(lat) >= 1.0


## `lead` shortened by `LEAD_STEP` until the point it puts past the slot can be walked to
## (`_lead_ok`), and with a `deep` walk the one sideways at `depth` too: never past the room's end
## nor into another doorway's funnel, where the walk would go by another way.
func _fit_lead(entry: Entry, lead: float, depth: float, deep: bool) -> float:
	while lead > 0.0 and not _lead_fits(entry, lead, depth, deep):
		lead = maxf(lead - LEAD_STEP, 0.0)
	return lead


## Whether the points `lead` px past the slot can be walked to (`_fit_lead`): the one at the wall,
## then, on a `deep` walk, the one sideways at `depth` (no less than the slot's own).
func _lead_fits(entry: Entry, lead: float, depth: float, deep: bool) -> bool:
	var door: Vector2 = state.geo["pos"]
	var target := entry.claim.spot
	var target_out := (target - door).dot(state.geo["out"])
	var lat := absf((target - door).dot(state.geo["along"])) + lead
	if not _lead_ok(_wall_point(target_out, lat)):
		return false
	return not deep or _lead_ok(_wall_point(maxf(depth, target_out), lat))


## The point `out_px` out from the doorway's wall and `lat_px` along it on this NPC's side.
func _wall_point(out_px: float, lat_px: float) -> Vector2:
	var door: Vector2 = state.geo["pos"]
	var out: Vector2 = state.geo["out"]
	var along: Vector2 = state.geo["along"]
	return door + out * out_px + along * state.side * lat_px


## How long (s) the approach's walk takes at walking pace: the way the NPC walks it
## (`AgentPerception.walk_route`, this entry's approach), leg by leg through the waypoints into the
## slot, so a long way round (an ordered approach keeps out of the room being entered however long
## it is) is not cut short by the cap (E2).
func walk_time(entry: Entry) -> float:
	var speed: float = world.character.movement.walk_speed()
	if speed <= 0.0:
		return 0.0
	var entering := "%s>%s" % [state.opening, state.into]
	var length := 0.0
	var at: Vector2 = world.character.global_position
	for p in waypoints + [entry.claim.spot]:
		length += float(world.perception.walk_route(p, entering, at)["len"])
		at = p
	return length / speed


## Whether approach waypoint `p` can be walked to (`_waypoint`).
func _lead_ok(p: Vector2) -> bool:
	return _waypoint(p) != Vector2.INF


## Approach waypoint `p` as the walk goes to it: kept inside the room the stack stands in
## (`_in_stack_room`) and onto the navmesh, or INF when that lands off the stack's ground
## (`AgentPerception.entry_on_stack_side`: another doorway's funnel, or across a wall) or more than
## `WAYPOINT_SNAP` px from where it was asked (the nearest walkable point lies somewhere else).
func _waypoint(p: Vector2) -> Vector2:
	var kept := _in_stack_room(p)
	var on: Vector2 = world.loco.reachable(kept)
	if (on.distance_to(kept) > WAYPOINT_SNAP
			or not world.perception.entry_on_stack_side(state.geo, on)):
		return Vector2.INF
	return on


## Point `p` kept inside the room the stack stands in, `CROSS_INSET` off its walls (an approach
## waypoint past the room's end would be reached by some other way round); outside the house, `p`.
func _in_stack_room(p: Vector2) -> Vector2:
	var room: Rect2 = (state.geo.get("from_room", Rect2()) as Rect2).grow(-CROSS_INSET)
	if room.size.x <= 0.0 or room.size.y <= 0.0:
		return p
	return p.clamp(room.position, room.end)


## How far out from the wall the crossing in front of the door goes (with no way round its view):
## `CROSS_DEPTH`, but no deeper than the room the stack stands in allows, a body (`CROSS_INSET`) off
## its far wall; outside the house, `CROSS_DEPTH`.
func _cross_depth() -> float:
	var room: Rect2 = state.geo.get("from_room", Rect2())
	if room.size == Vector2.ZERO:
		return CROSS_DEPTH
	var door: Vector2 = state.geo["pos"]
	var far := -INF
	for c in [
			room.position,
			Vector2(room.end.x, room.position.y),
			room.end,
			Vector2(room.position.x, room.end.y),
	]:
		far = maxf(far, ((c as Vector2) - door).dot(state.geo["out"]))
	return minf(CROSS_DEPTH, far - CROSS_INSET)


## Whether the walk from here to `target` has a way round this doorway's view (E18): 1 when the way
## the NPC walks (`AgentPerception.walk_route`, the approach of this entry: out of the room being
## entered and its doorway's view) goes round it or the plain way never goes into it, 0 when it has
## none (the front is crossed far out), -1 while the map round the views is still being baked.
func _way_round(target: Vector2) -> int:
	var route: Dictionary = world.perception.walk_route(
		target,
		"%s>%s" % [state.opening, state.into],
	)
	if (bool(route["doors"])
			or not (route["views"] as Array).any(func(v): return v["id"] == state.opening)):
		return 1
	return -1 if bool(route["pending"]) else 0


## Walk the approach waypoints, then into the slot; give up the claim when it takes too long.
func tick_approach(entry: Entry, team: Array, delta: float) -> void:
	if state.clock > cap:
		entry.radio.say(entry, "abort")
		state.phase = "done"
		return
	if _end_forming_wait(entry):
		return
	if world.loco.crowd.held_time() > 0.0:
		# Held: the map the verdict on the slot is read from is asked for now, so it is baked by the
		# re-plan.
		_slot_sealed(entry, entry.claim.spot)
	if not team.is_empty() and entry.grenade.due(entry, team, delta):
		# The rest of the stack is in place: the thrower goes straight to throw, rather than into
		# its slot first.
		return
	_replan_approach(entry)
	if _redrop_sealed(entry):
		return
	entry.sweep.aim_travel()
	if _walk_waypoints():
		return
	var spot := entry.claim.spot
	if not arrived_at(spot, StackClaim.SLOT_REACH):
		world.loco.move_to(spot, StackClaim.SLOT_REACH)
		return
	_arrive_at_slot(entry, team)


## End the wait on a teammate of the stack still forming (`forming_wait`) once that hold is over:
## the teammate it waited on moved on (the walk goes on), or the wait ran out with the walk still
## held: the hold is weighed again as a sealed walk (`Entry.way_blocked`). True when that gave the
## entry up.
func _end_forming_wait(entry: Entry) -> bool:
	if not forming_wait or held_by_forming(entry):
		return false
	forming_wait = false
	return world.loco.crowd.held_by() != 0 and entry.way_blocked()


## Lay the approach again when its way has changed: a teammate has since claimed a slot the point
## past this one runs into (arrive short of it), or the map round the doorway's view is up (the way
## there is known now).
func _replan_approach(entry: Entry) -> void:
	if (not waypoints.is_empty()
			and entry.claim.approach_lead(entry, entry.claim.stack) < entry.claim.lead):
		enter_approach(entry, entry.claim.stack)
	elif _round_pending and _way_round(entry.claim.spot) >= 0:
		enter_approach(entry, entry.claim.stack)


## Weigh at once a waypoint the hold already showed sealed, put back by a re-plan of the approach
## (its slot point moved, a teammate's claim): the same hold, so it is dropped again now rather than
## on the hold's next re-plan (`Entry.way_blocked`). Walked on from where the hold stood it, a hold
## met further on is a new one. True when that gave the entry up.
func _redrop_sealed(entry: Entry) -> bool:
	if (dropped_at != Vector2.INF
			and world.character.global_position.distance_to(dropped_at) > Locomotion.HOLD_MOVED):
		dropped_at = Vector2.INF
	if (dropped_at == Vector2.INF
			or forming_wait
			or waypoints.is_empty()
			or not world.loco.seals(waypoints[0])):
		return false
	return entry.way_blocked()


## Walk the approach's waypoints: those got to (or to the free spot beside one a body stands on)
## are dropped, and the walk goes on to the next. True while one is left to walk to.
func _walk_waypoints() -> bool:
	while not waypoints.is_empty() and _got_to(waypoints[0]):
		waypoints.pop_front()
	if waypoints.is_empty():
		return false
	world.loco.move_to(waypoints[0])
	return true


## Whether the approach has got to waypoint `p`: within `WAYPOINT_REACH`, or to where the walk there
## ends (`Locomotion.reached`).
func _got_to(p: Vector2) -> bool:
	return (world.character.global_position.distance_to(p) <= Entry.WAYPOINT_REACH
			or world.loco.reached(p))


## In the slot: stand, stack (E2), note when it got there, and radio `ready` unless it slices its
## own half of the pie first (E19).
func _arrive_at_slot(entry: Entry, team: Array) -> void:
	world.character.movement.move_input = Vector2.ZERO
	set_phase("stack")
	if entry.readiness.ready_at < 0.0:
		entry.readiness.ready_at = state.time
	if not entry.readiness.slices_own_half(entry, team):
		entry.readiness.say_ready(entry)


## The tactical reload (E11): the stack is the one lull before the crossing, so a gun short of full
## is swapped for a full magazine here, standing still, and never in the threshold or the room just
## taken. True while that is under way: the caller does not move on armed with a part-spent gun. Not
## with a hostile holding the entrant's eyes (it fires, and an empty gun is the watch stage's
## reload) and not for longer than `TOP_OFF_CAP` s.
func topping_off(delta: float) -> bool:
	if state.gaze_held or _top_off_spent >= TOP_OFF_CAP:
		return false
	if not world.combat.top_off():
		return false
	world.character.movement.move_input = Vector2.ZERO
	_top_off_spent += delta
	return true


## Move on to phase `next`, restarting the phase clock, and log it (the game's "what is happening"
## log).
func set_phase(next: String) -> void:
	state.phase = next
	state.clock = 0.0
	blocked_count = 0
	GameLog.say("%s entry %s > %s: %s at %s (slot %d%s)" % [
		world.character.name, state.opening, state.into, next,
		world.character.global_position.round(), state.slot, ", alone" if state.solo else "",
	])


## Whether the character has got to `p`: close by, or at the end of its nav path there (arriving
## within `within` px when given, `Locomotion.move_to`).
func arrived_at(p: Vector2, within := 0.0) -> bool:
	return (world.character.global_position.distance_to(p)
				<= (within if within > 0.0 else Entry.WAYPOINT_REACH * 0.6)
			or world.loco.reached(p, within))
