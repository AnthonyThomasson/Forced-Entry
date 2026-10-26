extends RefCounted
## AI BEHAVIOUR sub-domain — TACTICAL ENTRY. How an NPC gets through a doorway into a room the way
## police and soldiers do (`docs/tactical-entry.md`, E1 to E15), as one member of a team or alone.
## Von only chose the doorway (the ENTER tactic); the choreography is this phase machine, so it runs
## with the server down:
##
##   approach — to its stack slot beside the door, stepping off the door's axis while still well out
##              and arriving along the wall (E1)
##   stack    — in the slot, facing the door (the last of three or more faces back along the line
##              instead, E12; a member past a short room's two holds here as security, E13); radios
##              `ready` (E2); the point of a quiet stack that carries a stun listens here
##              `tuning.entry.listen_time` s before the pie, for a late reason to turn it into
##              a bang (E17)
##   pie      — the point (or a lone entrant) sweeps the arc beside the door in angle steps, looking
##              through it, and notes the share of the room seen and the corners still hidden (E3);
##              alone, both sides (E7) Nobody crosses while a hostile stands in view (E14): the pie
##              stops where it is and the watch stage fires.
##   bang     — a bang entry (`docs/grenades.md` G18): once the stack is ready its thrower radios
##              `bang`, steps out beside the door and throws a stun into the room, committed from
##              its call until the stun leaves its hand; every member holds its slot turned away
##              from the door until the stun goes off
##   cross    — committed: through the threshold without stopping, to its corner (E4, E5); radios
##              `going_in`, then `in` once it is in the room and off the door's axis
##   corner   — holds the corner looking across the room, then clears the rest by sight
##              (`search_coverage.gd`) A pass-by (`secure`, E15) stops here: it slices one side of
##              the pie from beside the jamb and walks on.
##   cover    — once the room is clear, each member covers a different doorway on into a room not
##              yet cleared, its gun through it, until a teammate moves on (E8); alone, it looks
##              through each such doorway in turn
##   rear     — a member left over (no such doorway free) that was the last of the team in holds the
##              doorway it came by, facing back out (E8)
##
## Its role comes from its slot. Slots, readiness and progress travel on the team radio: the
## behaviour queues each step (`take_calls()`) and the controller radios it; the team is read back
## through the perception (`entry_stack`). The point crosses when every member of the stack is ready
## or `tuning.entry.ready_timeout` runs out (E6); a follower crosses `tuning.entry.follow_gap` after
## the member ahead of it is through. With nobody else claiming the doorway the NPC goes alone; an
## ally that claims a slot before it commits joins the stack (E7). In a **bang entry** the stack
## throws a stun grenade into the room first (the `bang` phase, below): the point skips the pie and
## crosses the moment it goes off. Any entry into a room the NPC suspects a hostile in, with a stun
## in the stack, is a bang one, whatever order brought it to the doorway; a quiet entry turns into a
## bang one when a reason to suspect the room comes up before anyone crosses (E17,
## `_maybe_upgrade`). Owns that state and nothing else: `Behavior` calls `begin()` on adopting an
## ENTER leaf and `step()` every tick until it reports done.

const Watch := preload("res://scenes/ai/behavior/watch.gd")
const Locomotion := preload("res://scenes/ai/behavior/locomotion.gd")
## The entry claim's wire format, step lists and slot distances (perception's stack module).
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
const DoorStack := preload("res://scenes/ai/perception/stack/door_stack.gd")
const EntryState := preload("res://scenes/ai/behavior/entry/entry_state.gd")
const EntryWorld := preload("res://scenes/ai/behavior/entry/entry_world.gd")
const EntryClaim := preload("res://scenes/ai/behavior/entry/entry_claim.gd")
const EntryApproach := preload("res://scenes/ai/behavior/entry/entry_approach.gd")
const EntryReadiness := preload("res://scenes/ai/behavior/entry/entry_readiness.gd")
const EntryOrders := preload("res://scenes/ai/behavior/entry/entry_orders.gd")
## How far (px) back from a doorway, inside the cleared room, a member stands to cover it.
const COVER_DEPTH := 110.0
## How far (px) a cover spot is kept off the cleared room's walls.
const COVER_INSET := 20.0
## A waypoint (px) counts as reached this close.
const WAYPOINT_REACH := 20.0
## How close (px) an entrant walks into its corner: all the way, since a few px short of a corner
## beside the doorway (a small room's) is still in the way of the one crossing behind it.
const CORNER_REACH := 6.0
## Distance (px) between the spots two members hold side by side (the later members' spots inside,
## the rear spots): clear of each other's footprint, so neither stands in the hole the other's body
## cuts in the steering map.
const SPOT_SPACING := 44.0
## Most seconds the committed crossing may take before it gives up the commitment (a blocked
## doorway).
const CROSS_CAP := 6.0
## Gaze (rad) within which the look through the door has settled at a pie step.
const GAZE_SETTLED := 0.12
## A bang entry (G18): where the thrower steps out to throw from (px out from the wall, and along it
## from the doorway's centre as shares of its width, toward the stack's side first), how deep into
## the room and how far across it (shares of the room's depth and width) the stun is aimed, in order
## of preference (no deeper than it reaches), and the least distance (px) from the door it lands at.
const BANG_STEP_OUT := 78.0
const BANG_STEP_ALONG := [0.25, 0.0, -0.25]
const BANG_DEPTHS := [0.85, 0.7, 0.55]
const BANG_ACROSS := [0.0, 0.2, -0.2]
const BANG_MIN_DEPTH := 120.0
## The most seconds a stack-ready member waits for its thrower to call the bang before the stack
## goes in quietly, and the most the stack waits for the stun to go off once it was called.
const BANG_CALL_CAP := 8.0
const BANG_BURST_CAP := 5.0
## The most seconds the stack waits for a frag to go off once it was called (`docs/leadership.md`
## LD14): its fuse is twice a stun's.
const FRAG_BURST_CAP := 7.0
## Seconds after the stun went off in which the stack goes in whatever stands in view (a hostile in
## the doorway is blind and deaf); an entry begun within this long of its own team's burst in the
## room goes in on it too (E17).
const BANG_WINDOW := 3.0
## Seconds between reads of why the room is suspect, for a quiet entry that may turn into a bang
## (E17).
const SUSPECT_EVERY := 0.25

## The entry's own state, which `Behavior` reads (`entry/entry_state.gd`): its phase, doorway, slot
## and side, its mode, and its clocks.
var state := EntryState.new()
## What the entry works with (`entry/entry_world.gd`): the side's squad, the behaviour's modules,
## the body and the NPC's tuning, read live.
var world := EntryWorld.new()
## Its slot in the doorway's stack and where it stands (`entry/entry_claim.gd`).
var claim := EntryClaim.new(state, world)
## The walk to its slot, and the phase changes (`entry/entry_approach.gd`).
var approach := EntryApproach.new(state, world)
## In the slot until its turn to cross (`entry/entry_readiness.gd`).
var readiness := EntryReadiness.new(state, world)
## The order the stack goes in under (`entry/entry_orders.gd`).
var orders := EntryOrders.new(state, world)
## Share of the room's sample points seen from outside during the pie.
var seen_fraction := 0.0
## How many sides of the door the pie was sliced from.
var pie_sides := 0
## The corner this NPC enters to.
var corner := Vector2.INF
## The doorway on (its id) this NPC covers once the room is clear ("" = none).
var covering := ""
## Steps to radio, oldest first, each a claim in `StackClaim`'s fields (`entry_step`, ...; the
## behaviour adds the doorway, room, slot and side).
var _calls: Array = []
## A step of this entry has gone out on the radio (`take_calls`).
var _on_air := false
## The latest step radioed, whole (repeated on the heartbeat).
var _last_call := {}
## Seconds until the latest step is radioed again.
var _heartbeat := 0.0
## This member has begun slicing the pie, and says so on the radio (`pie`): nobody moves up behind
## it from then on.
var _pie_begun := false
## Pie steps still to look from (points on the arc).
var _pie_queue: Array = []
## The side being sliced now.
var _pie_side := 0
## The room's sample points (coverage grid).
var _points: Array = []
## Those not yet seen from outside.
var _unseen: Array = []
## Index into the geometry's corners -> seen during the pie.
var _corners_seen := {}
## Current gaze angle (rad), eased toward what the phase looks at.
var _look_angle := 0.0
## Where the rear guard stands, just inside the doorway.
var _rear_spot := Vector2.INF
## Seconds held at the current spot (the corner).
var _dwell := 0.0
## The room has been covered by sight (waiting for the rest of the stack to be in).
var _covered := false
## The doorways on out of the cleared room: { id, into, pos, spot, aim }.
var _watch: Array = []
## Alone: the doorways still to look through, in turn.
var _sweep: Array = []
## Where this NPC stands to cover its doorway.
var _cover_spot := Vector2.INF
## A point through that doorway, in the room beyond: where its gun points.
var _cover_aim := Vector2.INF
## Allies seen holding the cleared room (cover / rear): instance id -> true.
var _holders := {}
## Stun grenades this NPC carries (radioed, so the stack knows who can throw).
var _stuns := 0
## The thrower's part: "go" (to the throw spot), "throw", "back" (to its slot); "" for everyone
## else.
var _bang_stage := ""
## Where the thrower throws from.
var _bang_spot := Vector2.INF
## The points it walks through to get there: out from its slot first, clear of the member ahead of
## it, then along.
var _bang_route: Array = []
## Where the stun is thrown to, in the room.
var _bang_target := Vector2.INF
## Seconds a stack-ready member has waited for the bang to be called.
var _bang_wait := 0.0
## The stack's stun, or its own team's stun or frag, went off in the room: the point crosses at
## once, no pie.
var _bang_over := false
## This member gave the bang up (no lob, no stun, a cap ran out): radioed as `bang_off`, which keeps
## the whole stack quiet.
var _bang_off := false
## Its bang came from a quiet entry turned (E17): it waits for the rest of the stack to follow
## rather than going quiet.
var _upgraded := false
## Teammates whose claims said quiet during this entry: instance id -> true (one that then says bang
## has turned it).
var _quiet_seen := {}
## Seconds until the room's suspicion is read again.
var _suspect_clock := 0.0
## The listen hold at the stack was ended early (a hostile in view, or under fire): it is not taken
## up again.
var _listen_over := false
## The `GameClock` frame of the last burst in the room this entry has taken note of.
var _burst_seen := -1
## `state.time` of the burst in the room (negative: before the entry began).
var _burst_at := -INF
## Frag grenades this NPC carries (radioed, so a frag stack knows who can throw, LD14).
var _frags := 0
## The grenade the bang throws: a stun, or a frag for a stack ordered so (LD14).
var _kind: StringName = &"stun"
## The frag this NPC threw for the bang, to radio (`take_thrown`): { kind, point }; {} for none.
var _thrown := {}


## Capture the locomotion, the perception, the room coverage, the watch module (where a walker
## looks) and the combat module (the tactical reload). Called once by `Behavior.setup()`, which has
## handed in the NPC's tuning (`world.tuning`) first.
func setup(
	loco: Node,
	perception: Node,
	coverage: RefCounted,
	eyes: RefCounted,
	combat: RefCounted,
) -> void:
	world.loco = loco
	world.perception = perception
	world.coverage = coverage
	world.eyes = eyes
	world.combat = combat


## Hand in the NPC's body. Called once by `Behavior.bind()`.
func bind(character: Node) -> void:
	world.character = character


## Start an entry from `params`: `opening` and `into` from an ENTER leaf, `secure` from the guard's
## pass-by detour, and from an ordered stack's leaf (`docs/leadership.md` LD9) its `order_id`,
## `bang`, `mode` (LD14), `wait_go` and `go` (LD13) and side (`stack_at`, or `split`); a join
## (LD24, `StackClaim.is_join`) is run as the NPC's own entry, its order's id left out of it. False
## when the doorway is unknown (the leaf is then dropped and the NPC re-decides). It claims the
## lowest slot the claims heard leave free (the slots go by arrival on the radio, E2), not the one
## the option was measured from: a claim heard since then came first. A claim made on this same
## frame is not first: the member nearer the slot takes it, and two claims on one slot made on one
## frame settle the same way (`claim.keep_slot`; else by instance id), so walks to neighbouring
## slots do not cross.
func begin(params: Dictionary) -> bool:
	reset()
	state.opening = str(params.get("opening", ""))
	state.into = str(params.get("into", ""))
	state.secure = bool(params.get("secure", false))
	state.geo = world.perception.entry_geometry(state.opening, state.into)
	if state.geo.is_empty():
		state.phase = "done"
		return false
	claim.read_stack()
	var team: Array = claim.stack.team
	world.self_id = world.character.get_instance_id()
	_stuns = world.character.inventory.item_count(ItemRegistry.STUN_SLOT)
	_frags = world.character.inventory.item_count(ItemRegistry.FRAG_SLOT)
	orders.begin_order(self, params)
	_begin_mode(team, bool(params.get("bang", false)))
	var at: Dictionary = claim.stack.claim(
		{
			"id": world.self_id, "slot": 0, "frame": GameClock.frame(),
			"pos": world.character.global_position,
		},
		func(n): return claim.ask_side(self, n, true),
	)
	state.slot = at["slot"]
	if not at["held"]:
		# A dead end already holding all it can (E20, rule 6): no slot, no claim (an ordered
		# member's next decision refuses).
		state.phase = "done"
		return false
	claim.leader_id = orders.leader_id()
	claim.stand(at)
	state.solo = orders.alone(team)
	readiness.team_size = team.size()
	_points = world.coverage.sample_room(state.into)
	_unseen = _points.duplicate()
	_look_angle = world.character.facing.angle()
	_note_burst_before()
	approach.enter_approach(self, claim.stack)
	_radio("claim")
	return true


## Set the entry's mode at `begin` (`bang`), its leaf having `asked` for a bang or not: an ordered
## stack goes in the order's way, whoever claimed first (LD9, D10); else a room already suspect
## means a bang with a stun in the stack (`_suspect_bang`, E17), and a stack already claimed goes in
## the way its first claimer chose. A bang the leaf did not ask for is noted (`take_turned`).
func _begin_mode(team: Array, asked: bool) -> void:
	var ordered := orders.claim(self)
	if not ordered.is_empty():
		state.bang = bool(ordered["order_bang"])
	else:
		state.bang = _suspect_bang(team, asked)
		if not team.is_empty():
			state.bang = team.all(func(m): return m["bang"] and not m["bang_off"])
	readiness.turned = state.bang and not asked


## Whether this entry is a bang one on its own terms (E17): its leaf `asked` for it, or the stack
## carries a stun and the room is suspect now, whatever order brought the NPC here. Never a
## pass-by.
func _suspect_bang(team: Array, asked: bool) -> bool:
	if state.secure:
		return false
	if asked:
		return true
	return _stack_has_stun(team) and not world.perception.room_suspicion(state.into).is_empty()


## Forget the running entry.
func reset() -> void:
	state.phase = ""
	state.opening = ""
	state.into = ""
	state.slot = 0
	state.side = 0
	state.solo = true
	state.secure = false
	state.secured = false
	seen_fraction = 0.0
	pie_sides = 0
	corner = Vector2.INF
	covering = ""
	state.bang = false
	_reset_modes()
	_reset_progress()
	claim.reset()
	approach.reset()
	readiness.reset()
	orders.reset()


## Forget the running entry's bang: the throw, the bursts noted and the turns of its mode
## (`reset`).
func _reset_modes() -> void:
	_bang_stage = ""
	_bang_spot = Vector2.INF
	_bang_route = []
	_bang_target = Vector2.INF
	_bang_wait = 0.0
	_bang_over = false
	_bang_off = false
	_upgraded = false
	_quiet_seen = {}
	_suspect_clock = 0.0
	_listen_over = false
	_burst_seen = -1
	_burst_at = -INF
	_frags = 0
	_kind = &"stun"
	_thrown = {}


## Forget the running entry's way through its phases: the doorway's geometry, the radio, the clocks,
## the pie and the hold of the room (`reset`).
func _reset_progress() -> void:
	state.geo = {}
	_calls = []
	_on_air = false
	state.held_back = false
	_last_call = {}
	_heartbeat = StackClaim.HEARTBEAT
	state.clock = 0.0
	_pie_begun = false
	state.time = 0.0
	_pie_queue = []
	_pie_side = 0
	_points = []
	_unseen = []
	_corners_seen = {}
	_rear_spot = Vector2.INF
	_dwell = 0.0
	_covered = false
	_watch = []
	_sweep = []
	_cover_spot = Vector2.INF
	_cover_aim = Vector2.INF
	_holders = {}


## Give the entry up (the NPC chose something else, e.g. a fight): radio `abort` so the stack stops
## counting on it. An entry none of whose steps has gone out yet (its claim held back) gives nothing
## up: its steps are dropped.
func abandon() -> void:
	if state.phase in ["", "done"]:
		return
	if _on_air:
		_radio("abort")
	else:
		_calls = []
	state.phase = "done"


## Whether the entry `params` names can begin on its doorway's slots: they are laid (`wall_n` and
## the rest, `AgentPerception.entry_geometry`) only on a baked nav map, and a stack claims by them.
## True for a doorway the perception does not know (`begin` then fails at once).
func laid(params: Dictionary) -> bool:
	var g: Dictionary = world.perception.entry_geometry(
		str(params.get("opening", "")), str(params.get("into", "")),
	)
	return g.is_empty() or g.has("wall_n")


## The points the approach still walks through to its slot, in order (its waypoints, then the slot),
## from `begin` on: the way `Behavior` reads before the claim of an ordered entry goes out (D4).
func approach_points() -> Array:
	return approach.waypoints + (
		[claim.spot] if state.phase == "approach" and claim.spot != Vector2.INF else []
	)


## Whether the entrant is committed: nothing may stop it (no re-decision, no reload, no crouch)
## while it crosses, until it is through the threshold and off the door's axis (E4), nor while it
## throws the bang (`throwing`).
func committed() -> bool:
	return state.phase == "cross" or throwing()


## Whether this member is the bang's thrower between its call and the stun leaving its hand: the
## walk out to the throw spot, taking the stun in hand and the wind-up (E17). A hostile seen
## meanwhile does not make it leave: it throws, then fights. A cap that runs out, the stun lost or a
## walk with no way through end it (`_give_up_bang`).
func throwing() -> bool:
	return state.phase == "bang" and _bang_stage in ["go", "throw"]


## Whether the entry became a bang one its order did not ask for since the last call (E17: the room
## was suspect at `begin`, or a late reason turned it): true once, so the order it runs under is
## re-adopted as a bang entry.
func take_turned() -> bool:
	var was := readiness.turned
	readiness.turned = false
	return was


## The steps queued for the radio since the last call, oldest first: { step, cleared_room? }; none
## while `held_back`.
func take_calls() -> Array:
	if state.held_back:
		return []
	var out := _calls
	_calls = []
	_on_air = _on_air or not out.is_empty()
	return out


## The frag this NPC threw into the room for the bang since the last call (`{ kind, point }`, the
## point it was aimed at), once, for the controller to radio as `frag_out` (LD14); {} for none. A
## stun's bang radios nothing of its throw.
func take_thrown() -> Dictionary:
	var out := _thrown
	_thrown = {}
	return out


## Whether this member holds in its slot, ready, for the leader's go (LD13): the stack it is in was
## ordered to hold and has had no go.
func holding_for_go() -> bool:
	return readiness.holding and state.phase == "stack"


## Whether this member holds its slot crouched for the frag its stack throws into the room (LD14):
## the bang phase of a frag stack, in its slot (the thrower once it is back in it).
func holds_crouched() -> bool:
	return state.phase == "bang" and _kind == &"frag" and not throwing() \
		and world.character.global_position.distance_to(claim.spot) <= WAYPOINT_REACH


## The entry as data, for `debug_entry()` / `debug_state()` and the tests: the doorway, slot, side,
## role, phase, what the pie saw and where it is going.
func debug() -> Dictionary:
	if state.phase == "":
		return {}
	var hidden: Array = []
	for i in state.geo.get("corners", []).size():
		if not _corners_seen.get(i, false):
			hidden.append(state.geo["corners"][i]["pos"])
	return {
		"opening": state.opening, "into": state.into, "slot": state.slot, "side": state.side,
		"place": claim.place, "solo": state.solo, "phase": state.phase, "secure": state.secure,
		"seen_fraction": seen_fraction, "pie_sides": pie_sides,
		"hidden_corners": hidden, "corner": corner,
		"stack_point": claim.spot if not state.geo.is_empty() else Vector2.INF,
		"team": readiness.team_size, "covering": covering,
		"watch_doors": _watch.map(func(w): return w["id"]), "bang": state.bang,
		"bang_off": _bang_off, "upgraded": _upgraded, "bang_stage": _bang_stage,
		"order_id": orders.id, "order_mode": orders.mode, "order_hold": orders.hold,
		"released": readiness.released, "holding": holding_for_go(), "kind": _kind,
	}


## The entry as world-space data for the entry debug overlays (observation only): the doorway's
## frame (its fatal funnel's depth among it), slots, pie arc and corners (with what the pie saw),
## this NPC's role, slot, approach and gaze, the ready-barrier timers, the team off the radio, and
## once the room is clear the doorways on it covers. {} when no entry is running.
func debug_view() -> Dictionary:
	if state.phase in ["", "done"] or state.geo.is_empty():
		return {}
	var team: Array = claim.stack.team
	var corners := _view_corners()
	var role := ("solo"
			if team.is_empty() and readiness.through.is_empty()
			else ("point" if readiness.members_ahead(self).is_empty() else "follower"))
	var me := { "id": world.self_id, "slot": state.slot, "side": state.side }
	var members: Array = team + [me.merged({ "name": "me" })]
	var order: Array = claim.stack.crossing(me)
	var ready_left := _view_ready_left(role)
	var hold_left := _view_hold_left()
	var follow_left := _view_follow_left()
	return {
		"door": {
			"pos": state.geo["pos"],
			"width": state.geo["width"],
			"out": state.geo["out"],
			"along": state.geo["along"],
			"room": state.geo["room"],
			"funnel": StackClaim.FUNNEL_DEPTH,
		},
		"opening": state.opening, "into": state.into, "phase": state.phase, "role": role,
		"slot": state.slot, "side": state.side, "place": claim.place, "slots": state.geo["slots"],
		"order": order.map(func(m): return "me" if m.get("me", false) else str(m["name"])),
		"my_slot": claim.spot, "pie": state.geo["pie"], "pie_queue": _pie_queue.duplicate(),
		"pie_side": _pie_side, "pie_sides": pie_sides, "corners": corners, "corner": corner,
		"waypoints": approach.waypoints.duplicate(),
		"unseen": _unseen.duplicate() if state.phase == "pie" else [],
		"seen_fraction": seen_fraction,
		"gaze": Vector2.from_angle(_look_angle), "ready_left": ready_left,
		"follow_left": follow_left,
		"waiting_for": (
			team.filter(func(m): return m["step"] == "claim").map(func(m): return str(m["name"]))
		),
		"team": team.map(func(m):
			var d: Dictionary = m.duplicate()
			d["through"] = StackClaim.through(m["step"])
			d["place"] = DoorStack.place(members, int(m["side"]), int(m["slot"]))
			return d),
		"watch": _watch.map(
			func(w): return { "id": w["id"], "pos": w["pos"], "spot": w["spot"], "aim": w["aim"] }
		),
		"covering": covering, "sweep": _sweep.map(func(w): return w["id"]), "rear_spot": _rear_spot,
		"hold_left": hold_left, "ready_total": world.tuning.entry.ready_timeout,
		"follow_total": world.tuning.entry.follow_gap, "hold_total": _view_hold_total(),
	}


## The doorway's corners for `debug_view`, each with whether the pie saw it (`seen`).
func _view_corners() -> Array:
	var corners: Array = []
	for i in (state.geo["corners"] as Array).size():
		var c: Dictionary = (state.geo["corners"][i] as Dictionary).duplicate()
		c["seen"] = _corners_seen.get(i, false)
		corners.append(c)
	return corners


## The seconds left of the point's wait for the stack (`debug_view`), for this NPC in `role`: from
## when it was ready, or under an order from when every recipient was in its slot (LD17); -1 when
## it does not wait.
func _view_ready_left(role: String) -> float:
	var waits_from := readiness.all_in_at if orders.id != "" else readiness.ready_at
	if role == "point" and waits_from >= 0.0 and state.phase in ["stack", "pie"]:
		return maxf(
			world.tuning.entry.ready_timeout
					- (state.time - maxf(waits_from, readiness.team_grew_at)),
			0.0,
		)
	return -1.0


## The seconds left of the hold of the cleared room (`debug_view`): the cover's or the rear's; -1
## in any other phase.
func _view_hold_left() -> float:
	if state.phase == "cover":
		return maxf(world.tuning.entry.cover_time - state.clock, 0.0)
	if state.phase == "rear":
		return maxf(world.tuning.entry.rear_security_time - state.clock, 0.0)
	return -1.0


## The longest the hold of the cleared room lasts (`debug_view`): the rear's in the rear phase, else
## the cover's.
func _view_hold_total() -> float:
	if state.phase == "rear":
		return world.tuning.entry.rear_security_time
	return world.tuning.entry.cover_time


## The seconds left before a follower crosses after the member ahead of it (`debug_view`); -1 while
## it is not its turn.
func _view_follow_left() -> float:
	if readiness.turn_at >= 0.0 and state.phase == "stack":
		return maxf(world.tuning.entry.follow_gap - (state.time - readiness.turn_at), 0.0)
	return -1.0


## One tick of the entry. True once it is over (the room is clear and any rear watch is done, or it
## was given up), when the NPC should re-decide.
func step(delta: float) -> bool:
	if state.phase in ["", "done"]:
		return true
	state.time += delta
	state.clock += delta
	claim.read_stack()
	var team: Array = claim.stack.team
	_stuns = world.character.inventory.item_count(ItemRegistry.STUN_SLOT)
	_frags = world.character.inventory.item_count(ItemRegistry.FRAG_SLOT)
	readiness.holding = false
	_note_burst()
	readiness.note_team(self, team)
	orders.note_go(self)
	readiness.note_all_in(self, team)
	if state.phase in ["approach", "stack", "pie"]:
		claim.keep_slot(self)
		orders.follow_order(self, team)
		_maybe_upgrade(team, delta)
	if state.phase in ["approach", "stack", "bang", "pie", "cross"]:
		var crossing: Array = claim.stack.crossing(
			{ "id": world.self_id, "slot": state.slot, "side": state.side }
		)
		claim.lead_side = int(crossing[0]["side"])
	_heartbeat -= delta
	if _heartbeat <= 0.0 and not _last_call.is_empty():
		# Keep the claim (and what it covers) alive on the radio.
		_radio(_last_call["entry_step"], _last_call)
	match state.phase:
		"approach":
			approach.tick_approach(self, team, delta)
		"stack":
			readiness.tick_stack(self, team, delta)
		"bang":
			_tick_bang(team, delta)
		"pie":
			_tick_pie(team, delta)
		"cross":
			_tick_cross(delta)
		"corner":
			_tick_corner(team, delta)
		"clear":
			_tick_clear(team, delta)
		"cover":
			_tick_cover(team, delta)
		"rear":
			_tick_rear(team, delta)
	return state.phase == "done"


## The walk this phase is on has no way through: a body seals it and stays
## (`Locomotion`'s `crowd.take_blocked`, after a moment's wait and then every few seconds while it
## stays held). The phase re-plans, so no member stands held for ever: the approach goes on to its
## next point (or its slot) by whatever way there is; a member the stack itself keeps from its slot
## takes the back of the stack (`claim.to_back`), and with no slot to take it gives the claim up; a
## pie step is skipped; the thrower gives the bang up; a member crossing waits out the first signal
## (the one ahead is still in the doorway and moves on in a moment), then takes its corner where it
## stands once through, or gives the entry up when the doorway is still sealed; a corner, a cover
## spot or the rear spot is held from where it stands, and the room is covered from where it stands.
## True when the entry is given up (radioed `abort`): the caller re-decides because the way is
## blocked.
func way_blocked() -> bool:
	approach.blocked_count += 1
	match state.phase:
		"approach":
			if approach.drop_sealed(self):
				return false
			if approach.held_by_forming(self):
				# The stack is forming, not keeping it out: it waits, its walk held
				# (`approach.tick_approach` ends the wait).
				approach.forming_wait = true
				return false
			return approach.to_back_or_abort(self)
		"pie":
			if not _pie_queue.is_empty():
				_pie_queue.pop_front()
				state.clock = 0.0
		"bang":
			if _bang_stage == "go":
				_give_up_bang()
				approach.set_phase("stack")
		"cross":
			if approach.blocked_count < 2:
				# The member ahead is still in the doorway: it moves on into the room in a moment.
				return false
			var off: Vector2 = world.character.global_position - (state.geo["pos"] as Vector2)
			if off.dot(state.geo["out"]) >= -StackClaim.THROUGH_DEPTH:
				_radio("abort")
				state.phase = "done"
				return true
			corner = world.character.global_position
		"corner":
			corner = world.character.global_position
		"clear":
			_covered = true
		"cover":
			_cover_spot = world.character.global_position
		"rear":
			_rear_spot = world.character.global_position
	return false


## Whether the stack is in bang mode and has a stun to throw: every member's claim says bang (one
## that gave it up vetoes it), or this member's quiet entry has just turned and the rest have yet to
## follow (`_upgraded`: their claims say bang within a call or two), or the stack goes in under an
## order that says bang (LD9: a member still quiet follows it), and a member carries one. The mode
## is the order's, else the first claimer's (`begin`), so a stack goes in all one way.
func _banging(team: Array) -> bool:
	return (state.bang
			and not _bang_over
			and (_upgraded or orders.stack_ordered(self) or team.all(func(m): return m["bang"]))
			and _thrower() != -1)


## The instance id of the member who throws the bang's grenade (`_bang_kind`), or -1 when nobody
## can: the second of the stack if it carries one, else the lowest slot that does (alone, this NPC).
## Every member works it out from the radio's `stuns` (a frag stack's: `frags`, LD14) the same way.
func _thrower() -> int:
	return claim.stack.thrower(
		_bang_kind(), { "id": world.self_id, "slot": state.slot, "stuns": _stuns, "frags": _frags },
	)


## A member in its slot with the stack ready that is the thrower calls the bang and goes to throw.
## Returns true once the phase has changed. A thrower with nowhere to throw from (no clear lob into
## the room) gives the bang up: the stack goes in quietly.
func _bang_due(team: Array, delta: float) -> bool:
	if _bang_over or not state.bang or orders.held_for_go(self):
		return false  # (A held stack calls no bang before its go, LD13.)
	var ordered := orders.stack_ordered(self)
	if _bang_held_off(team, ordered):
		return false
	return _bang_call(team, ordered, delta)


## Whether the stack's bang is off for now (`_bang_due`; `ordered`: it goes in under an order): a
## teammate gave the bang up, or went in quietly before the stack turned, so this member goes in
## quietly too and its claims say so; or, in a stack nobody was ordered to, a claim says quiet: the
## stack goes in the way its first claimer chose (a claim heard after this one was made), unless
## this member's quiet entry just turned and the rest follow within a call or two.
func _bang_held_off(team: Array, ordered: bool) -> bool:
	if _vetoed(team) or (_upgraded and _crossing()):
		_give_up_bang()
		return true
	if not ordered and not team.all(func(m): return m["bang"]):
		if not _upgraded:
			_go_quiet()
		return true
	return false


## The bang in a stack in bang mode (`_bang_due`; `ordered`: it goes in under an order): a member
## that hears the thrower's call holds for the grenade; an ordered stack in place whose grenade is
## gone goes in quietly (D1 / D15); the thrower, once the stack is ready and no hostile stands in
## view, plans the throw and calls it (`_throw_bang`), the rest wait for it. True once the phase has
## changed.
func _bang_call(team: Array, ordered: bool, delta: float) -> bool:
	if team.any(func(m): return m["step"] == "bang"):
		_enter_bang()  # The thrower called it: hold, turned away, until the grenade goes off.
		return true
	if ordered and readiness.stack_ready(self, team) and not _stack_has(team, _bang_kind()):
		# D1 / D15: the stack is in and the order's stun (or frag) is gone: it goes in quietly, and
		# its claims say so (`bang_off`).
		_give_up_bang()
		return false
	if _thrower() == -1 or not readiness.stack_ready(self, team) or state.hostile_in_view:
		return false
	if _thrower() != world.self_id:
		_bang_wait += delta  # Waiting for the thrower to call the bang.
		return false
	return _throw_bang()


## The thrower calls the bang: it plans the throw and goes to make it, radioing `bang`. With nowhere
## to throw from (no clear lob into the room) it gives the bang up: the stack goes in quietly. True
## once the phase has changed.
func _throw_bang() -> bool:
	if not _plan_bang():
		_give_up_bang()
		return false
	_bang_stage = "go"
	_enter_bang()
	_radio("bang")
	return true


## Begin the bang phase, taking note of the last burst so only a grenade of the bang's kind that
## goes off from now on ends it.
func _enter_bang() -> void:
	_kind = _bang_kind()
	approach.set_phase("bang")
	_burst_seen = int(world.perception.last_burst.get("frame", -1))
	_burst_at = -INF


## Whether the point holds in its slot for the bang the stack's thrower is about to call, rather
## than slicing the pie: the stack is in bang mode and has waited less than `BANG_CALL_CAP` for it,
## or it goes in with a stun under an order and the rest of the stack, the thrower among them, is
## still on its way (D7).
func _waits_for_bang(team: Array) -> bool:
	if (state.bang
			and not _bang_over
			and orders.stack_ordered(self)
			and not readiness.stack_ready(self, team)):
		return true
	if not _banging(team):
		return false
	if _bang_wait >= BANG_CALL_CAP:
		_give_up_bang()
		return false
	return true


## The bang is off: the stack goes in quietly (the point slices the pie). Radioed with the next
## claim (`bang_off`), so the whole stack follows and no new reason turns it back (E17).
func _give_up_bang() -> void:
	_bang_off = true
	_go_quiet()


## Go in quietly, as the stack's first claimer chose: radioed with the next claim. Not a veto: a new
## reason may still turn it.
func _go_quiet() -> void:
	state.bang = false
	_upgraded = false
	_bang_stage = ""
	_radio(str(_last_call.get("entry_step", "ready")), _last_call)


## Whether a teammate gave the bang up (its claims say `bang_off`): the stack goes in quietly. In an
## ordered stack only a member under the same order does (its stun lost or no lob, D1): an ordered
## stun stack is never vetoed by anyone else (LD9).
func _vetoed(team: Array) -> bool:
	var ordered := orders.claim(self)
	if ordered.is_empty():
		return team.any(func(m): return m["bang_off"])
	return team.any(func(m): return m["bang_off"] and m["order_id"] == ordered["order_id"])


## Whether a member of the stack is crossing or through the doorway.
func _crossing() -> bool:
	return claim.stack.going_in()


## A quiet entry turns into a bang one (E17, `docs/grenades.md` G18) while nobody has crossed and
## the stack carries a stun, when the NPC suspects the room (footsteps or gunfire heard there, shot
## at from it, an ally's fight in it, a hostile lost in it, by its doorway or heading in; read every
## `SUSPECT_EVERY` s: a reason that came up after the entry began, or one it knew when it joined a
## quiet stack), or when a teammate's claims turn from quiet to bang (it knows the reason). Its
## claims say bang, so the whole stack follows; a point slicing the pie goes back to its slot to
## wait for the bang. Not once the bang was given up in this stack (`bang_off`), nor on a pass-by.
func _maybe_upgrade(team: Array, delta: float) -> void:
	if state.bang or not _may_turn(team):
		return
	var turned := team.any(func(m): return m["bang"] and _quiet_seen.has(m["id"]))
	if not turned:
		_suspect_clock -= delta
		if _suspect_clock > 0.0:
			return
		_suspect_clock = SUSPECT_EVERY
		if world.perception.room_suspicion(state.into).is_empty():
			return
	state.bang = true
	_upgraded = true
	readiness.turned = true
	_bang_wait = 0.0
	if state.phase == "pie":
		_pie_queue = []
		approach.set_phase("stack")  # Back to its slot, to hold for the bang instead of slicing on.
	_radio(str(_last_call.get("entry_step", "claim")), _last_call)


## Whether the point of a quiet entry still holds in its slot before the pie (E17): the stack
## carries a stun and a late reason could still turn the entry into a bang one (`_may_turn`), for
## `tuning.entry.listen_time` s from getting to its slot. A hostile in view or coming under fire
## ends the hold for this entry: what is there is fought, or the room is gone into, not waited on.
func _listening(team: Array) -> bool:
	if (_listen_over
			or state.bang
			or not _may_turn(team)
			or state.time - readiness.ready_at >= world.tuning.entry.listen_time):
		return false
	if state.hostile_in_view or world.perception.under_fire():
		_listen_over = true
		return false
	return true


## Whether a late reason could still turn this quiet entry into a bang one (`_maybe_upgrade`): the
## stack carries a stun, nobody has crossed, no member gave the bang up, the stack is not over a
## burst already, it is not a pass-by, and nobody in it was ordered (LD9: an ordered quiet stack
## stays quiet).
func _may_turn(team: Array) -> bool:
	return (not (
		_bang_off or _bang_over or state.secure or _vetoed(team) or _crossing()
		or orders.stack_ordered(self)
	)
			and _stack_has_stun(team))


## Whether the stack carries a stun: this NPC, or a teammate whose claims say so (`stuns`).
func _stack_has_stun(team: Array) -> bool:
	return _stack_has(team, &"stun")


## Whether the stack carries a grenade of `kind` (`stun` / `frag`): this NPC, or a teammate whose
## claims say so (`stuns` / `frags`).
func _stack_has(team: Array, kind: StringName) -> bool:
	var key := "frags" if kind == &"frag" else "stuns"
	return _carried(kind) > 0 or team.any(func(m): return int(m[key]) > 0)


## How many grenades of `kind` (`stun` / `frag`) this NPC carries.
func _carried(kind: StringName) -> int:
	return _frags if kind == &"frag" else _stuns


## The grenade the stack's bang throws: a frag for a stack under an order whose mode is frag (LD14),
## else a stun.
func _bang_kind() -> StringName:
	var ordered := orders.claim(self)
	return &"frag" if not ordered.is_empty() and str(ordered["order_mode"]) == "frag" else &"stun"


## Plan the throw: a spot to throw from and a target in the room, a clear lob from the thrower's
## hand there to the target (one that clears the jamb: `AgentPerception.can_lob`, from the hand with
## room to spare either side). The target is the room's far side, `BANG_DEPTHS` of the way in and
## `BANG_ACROSS` of the way across, or, in a room deeper than a stun reaches from the spot, the
## farthest point along that line it reaches (`_bang_aim`); at least `BANG_MIN_DEPTH` from the door.
## The first of them that some spot reaches with a clear lob wins, the thrower's own slot before a
## step out in front of the door (`BANG_STEP_ALONG`). A frag (LD14, D16) aims only where its burst
## leaves every claimed slot of the stack, the thrower's own too, out of its danger zone
## (`AgentPerception.in_grenade_zone`: the wall between shields it). False when nowhere gives a
## clear lob (for a frag, a safe one).
func _plan_bang() -> bool:
	var kind := _bang_kind()
	var depth := _bang_room_depth()
	var width := absf((state.geo["room"] as Rect2).size.dot((state.geo["along"] as Vector2).abs()))
	var spots := _bang_spots()
	var reach: float = world.perception.grenade_reach(kind)
	var slots := _slot_points() if kind == &"frag" else []
	for d: float in BANG_DEPTHS:
		for a: float in BANG_ACROSS:
			for spot: Vector2 in spots:
				var target := _bang_aim(spot, depth * d, width * a, reach)
				if _bang_target_ok(target, kind, slots) and _clear_lob(spot, target, reach, kind):
					_take_bang(spot, target)
					return true
	return false


## How deep (px) the room being entered runs from the doorway, along its axis: to its farthest
## corner.
func _bang_room_depth() -> float:
	var door: Vector2 = state.geo["pos"]
	var room: Rect2 = state.geo["room"]
	var depth := 0.0
	for c: Vector2 in [
			room.position,
			Vector2(room.end.x, room.position.y),
			room.end,
			Vector2(room.position.x, room.end.y),
	]:
		depth = maxf(depth, (door - c).dot(state.geo["out"]))
	return depth


## The spots the bang may be thrown from, in order of preference: the thrower's own slot, then each
## step out in front of the door (`BANG_STEP_OUT` from the wall, `BANG_STEP_ALONG` of its width
## along it, toward the stack's side first).
func _bang_spots() -> Array:
	var door: Vector2 = state.geo["pos"]
	var out: Vector2 = state.geo["out"]
	var along: Vector2 = state.geo["along"]
	var spots: Array = [claim.spot]
	for share: float in BANG_STEP_ALONG:
		spots.append(world.loco.reachable(door + out * BANG_STEP_OUT
				+ along * state.side * float(state.geo["width"]) * share))
	return spots


## Whether the bang may land at `target`: inside the room, at least `BANG_MIN_DEPTH` from the door,
## and, for a frag (`kind`), where its burst reaches none of the stack's `slots` (D16).
func _bang_target_ok(target: Vector2, kind: StringName, slots: Array) -> bool:
	if (not (state.geo["room"] as Rect2).grow(-30.0).has_point(target)
			or target.distance_to(state.geo["pos"]) < BANG_MIN_DEPTH):
		return false
	return not slots.any(func(p): return world.perception.in_grenade_zone(kind, target, p))


## Take the bang's plan: thrown from `spot` at `target`, walked to out from the slot first (clear
## of the member ahead of it), then along.
func _take_bang(spot: Vector2, target: Vector2) -> void:
	var door: Vector2 = state.geo["pos"]
	var out: Vector2 = state.geo["out"]
	var along: Vector2 = state.geo["along"]
	_bang_spot = spot
	_bang_target = target
	_bang_route = [
		world.loco.reachable(door + out * maxf(BANG_STEP_OUT, (spot - door).dot(out))
				+ along * (claim.spot - door).dot(along)),
		spot,
	]


## Where every member of the stack stands in its slot: the slot points of the claims heard and this
## NPC's own.
func _slot_points() -> Array:
	return claim.stack.points(claim.me(self)).map(func(m): return m["point"]).filter(
		func(p): return p != Vector2.INF,
	)


## The point a stun thrown from `spot` is aimed at: `deep` px into the room from the doorway (along
## its axis) and `across` px across it, or, when that is beyond `reach` of the spot, the farthest
## point the same distance across that is within it (a room deeper than a stun reaches: it goes in
## as far as it can). `Vector2.INF` when no point that far across is within reach.
func _bang_aim(spot: Vector2, deep: float, across: float, reach: float) -> Vector2:
	var door: Vector2 = state.geo["pos"]
	var out: Vector2 = state.geo["out"]
	var q: Vector2 = door + (state.geo["along"] as Vector2) * across - spot
	var b := q.dot(out)
	var room_left := b * b - q.length_squared() + reach * reach
	if room_left < 0.0:
		return Vector2.INF
	return q + spot - out * minf(deep, b + sqrt(room_left) - 1.0)


## Whether a grenade of `kind` thrown by a thrower that walks to `spot` and faces `target` flies to
## it clear of the jamb (`AgentPerception.can_lob`: from its hand, with room to spare either side,
## wherever its walk into the spot may end). The target is within the grenade's throw reach
## (`reach`, `AgentPerception.grenade_reach`) of the spot, so the thrower throws from where it
## stands and does not close in.
func _clear_lob(spot: Vector2, target: Vector2, reach: float, kind: StringName) -> bool:
	return spot.distance_to(target) <= reach and world.perception.can_lob(spot, target, kind, true)


## The bang phase. Everyone holds its slot turned away from the door while the stun is thrown and
## goes off (a frag: crouched, `holds_crouched`, LD14); the thrower first steps to its throw spot,
## throws (taking the grenade in hand, `Combat`) and comes back. When the stun has gone off the
## stack is over the bang: the point crosses at once (`readiness.tick_stack`), the rest follow as
## usual. The bang is given up if the throw fails, a teammate gave it up (its claims say quiet) or
## the stun does not go off.
func _tick_bang(team: Array, delta: float) -> void:
	if _burst_at > -INF:
		_bang_over = true
		approach.set_phase("stack")
		return
	if (state.clock > (FRAG_BURST_CAP if _kind == &"frag" else BANG_BURST_CAP)
			or _vetoed(team)
			or (not orders.stack_ordered(self) and not team.all(func(m): return m["bang"]))):
		_give_up_bang()
		approach.set_phase("stack")
		return
	match _bang_stage:
		"go":
			_bang_go(delta)
		"throw":
			_bang_throw(delta)
		_:
			_bang_back(delta)


## The thrower's walk out to its throw spot, all the way into it (`StackClaim.SLOT_REACH`: the lob
## was judged from there, and a stride short of it a jamb can be in its way), looking where it will
## throw; there, it stands and takes the grenade in hand to throw (`Combat`'s `throw.begin`).
func _bang_go(delta: float) -> void:
	while (_bang_route.size() > 1
			and world.character.global_position.distance_to(_bang_route[0]) <= WAYPOINT_REACH):
		_bang_route.pop_front()
	if not approach.arrived_at(_bang_spot, StackClaim.SLOT_REACH):
		world.loco.move_to(
			_bang_route[0],
			StackClaim.SLOT_REACH if _bang_route.size() == 1 else 0.0,
		)
		_look_toward(_bang_target, delta, 3.0)
		return
	world.character.movement.move_input = Vector2.ZERO
	world.combat.throw.begin(
		ItemRegistry.FRAG_SLOT if _kind == &"frag" else ItemRegistry.STUN_SLOT,
		_bang_target,
		world.perception.grenade_reach(_kind),
	)
	_bang_stage = "throw"


## The thrower's throw (`Combat`'s `throw.step`): a throw that fails gives the bang up; once the
## grenade leaves its hand it walks back, and a frag is kept to radio as "frag out" (LD14,
## `take_thrown`).
func _bang_throw(delta: float) -> void:
	if world.combat.throw.stage != "away" and world.combat.throw.step(delta) == &"failed":
		world.combat.throw.end()
		_give_up_bang()
		approach.set_phase("stack")
		return
	if world.combat.throw.released():
		world.combat.throw.end()
		_bang_stage = "back"
		if _kind == &"frag":
			_thrown = { "kind": _kind, "point": _bang_target }


## Hold the slot through the bang turned away from the door: back in it (or, shoved out of it, a
## step back in), the thrower once its grenade is away and everyone else from the call.
func _bang_back(delta: float) -> void:
	var spot := claim.spot
	if world.character.global_position.distance_to(spot) > WAYPOINT_REACH:
		world.loco.move_to(spot, StackClaim.SLOT_REACH)
	else:
		world.character.movement.move_input = Vector2.ZERO
	_look_toward(claim.spot + (state.geo["out"] as Vector2) * 300.0, delta, 3.0)


## Whether a burst in the room being entered ends a wait: the perception notes every burst
## (`last_burst`). In the bang phase, a grenade of the bang's kind (a stun, or a frag stack's frag)
## its own team threw that goes off after the phase began: the stack's own, or a teammate's thrown
## another way (a GRENADE), counts as the bang. Before anyone of this member has crossed (approach,
## stack, the pie), a stun or frag its own team threw (the NPC or an ally): the entry goes in on it
## (E17), no pie, as after a bang.
func _note_burst() -> void:
	var burst: Dictionary = world.perception.last_burst
	if (state.secure
			or burst.is_empty()
			or int(burst["frame"]) <= _burst_seen
			or not (state.geo.get("room", Rect2()) as Rect2).has_point(burst["position"])):
		return
	if not burst.get("team", false):
		return
	if not state.phase in ["bang", "approach", "stack", "pie"]:
		return
	if state.phase == "bang" and burst["kind"] != _kind:
		return
	_burst_seen = int(burst["frame"])
	_burst_at = state.time
	if state.phase != "bang":
		_bang_over = true


## At `begin`: a burst from before the entry is taken note of here, not as one during it, and its
## own team's in the room a moment before (within `BANG_WINDOW`) counts, so an entry begun on the
## heels of a stun or frag thrown into the room goes in on it (a GRENADE, then the walk in).
func _note_burst_before() -> void:
	var burst: Dictionary = world.perception.last_burst
	if burst.is_empty():
		return
	_burst_seen = int(burst["frame"])
	if (state.secure
			or not burst.get("team", false)
			or not (state.geo.get("room", Rect2()) as Rect2).has_point(burst["position"])):
		return
	var age := (float(GameClock.frame() - int(burst["frame"]))
			/ float(Engine.physics_ticks_per_second))
	if age > BANG_WINDOW:
		return
	_burst_at = -age
	_bang_over = true


## Whether the stun went off a moment ago (`BANG_WINDOW`): the stack goes in without the usual hold
## for a hostile in view.
func _in_bang_window() -> bool:
	return _bang_over and state.time - _burst_at < BANG_WINDOW


## Whether the live grenade of the evade reflex's `plan` (`AgentPerception.evade_plan`) is the one
## this entry is waiting for (the evade reflex then leaves the stack to its own turned-away hold,
## beside the wall and out of the burst's line): any stun, while a stun's bang phase runs (in flight
## it is at the doorway, where its landing is not known to those who did not throw it); a frag,
## while a frag's bang phase runs, in flight (the stack's own, aimed where no slot is in its zone,
## D16) or come down where this member's slot is out of its danger zone (LD14: the slot is its
## cover; one the frag reaches, a frag that came back to the door, is evaded as anywhere).
func expects_burst(plan: Dictionary) -> bool:
	if state.phase != "bang" or plan.get("kind") != _kind:
		return false
	return _kind == &"stun" or not bool(plan.get("landed", false)) \
		or not world.perception.in_grenade_zone(
			_kind,
			plan.get("lies", plan["point"]),
			claim.spot,
		)


## Become the point: slice the pie from this side (and, alone, from the other side after).
func _start_pie(team: Array) -> void:
	state.solo = orders.alone(team)
	approach.set_phase("pie")
	if not _pie_begun:
		_pie_begun = true
		if not _last_call.is_empty():
			# The pie is begun: on the radio at once, so nobody moves up behind it (E2).
			_radio(_last_call["entry_step"], _last_call)
	_pie_side = state.side
	_pie_queue = (state.geo["pie"][state.side] as Array).duplicate()
	pie_sides = 1


## Walk the pie arc a step at a time; at each step look through the door until the gaze settles plus
## `tuning.entry.pie_dwell`, noting what is seen. When the arc is done: alone, slice the other side
## too; else wait for the stack, then go in. The other side's front man of a split stack (E19)
## slices its half, radios `ready` and then crosses in its turn, after the point.
func _tick_pie(team: Array, delta: float) -> void:
	_note_seen()
	if not team.is_empty():
		state.solo = false  # An ally claimed a slot: no second side, it joins the stack.
	if state.hostile_in_view and not _in_bang_window():
		# E14: what is in view is fought from where it stands, not walked past or into.
		world.character.movement.move_input = Vector2.ZERO
		state.clock = 0.0
		return
	if _bang_over:
		_pie_queue = []  # A burst in the room (its own team's): no more slicing, in at once.
	if _pie_queue.is_empty():
		_end_of_pie(team, delta)
		return
	var spot: Vector2 = _pie_queue[0]
	if not approach.arrived_at(spot):
		world.loco.move_to(spot)
		_look_toward(_through_door(world.character.global_position), delta)
		state.clock = 0.0
		return
	world.character.movement.move_input = Vector2.ZERO
	var settled := _look_toward(_through_door(spot), delta)
	if settled and state.clock >= world.tuning.entry.pie_dwell:
		_pie_queue.pop_front()
		state.clock = 0.0
	elif not settled:
		state.clock = 0.0


## The arc is done, looking through the door: a pass-by is secured (seen from beside the jamb and
## covered: on its way, nothing left behind it); alone, the other side is sliced too; else, ready,
## it waits for the stack, topped off (E11), then goes in: a follower of a split stack after the
## member ahead of it (`readiness.follow`), the point once the stack is ready and no hostile stands
## in view (E14).
func _end_of_pie(team: Array, delta: float) -> void:
	world.character.movement.move_input = Vector2.ZERO
	_look_toward(state.geo["pos"] - (state.geo["out"] as Vector2) * 300.0, delta)
	if state.secure:
		state.secured = true
		state.phase = "done"
		return
	if state.solo and pie_sides < 2 and not _bang_over:
		_pie_other_side()
		return
	readiness.say_ready(self)
	var ahead := readiness.members_ahead(self)
	if not ahead.is_empty():
		if _bang_over or not approach.topping_off(delta):
			readiness.follow(self, team, ahead)
	elif (readiness.stack_ready(self, team)
			and (not state.hostile_in_view or _in_bang_window())
			and (_bang_over or not approach.topping_off(delta))):
		_start_cross(team)


## Alone: cross in front of the door (as far out as the arc's end) and slice it from the other side,
## from the axis outward.
func _pie_other_side() -> void:
	_pie_side = -state.side
	pie_sides = 2
	_pie_queue = (state.geo["pie"][-state.side] as Array).duplicate()
	_pie_queue.reverse()


## Drop every room point and corner now in sight from the unseen sets, and update the share seen.
func _note_seen() -> void:
	for p in world.perception.visible_points(_unseen):
		_unseen.erase(p)
	if not _points.is_empty():
		seen_fraction = 1.0 - float(_unseen.size()) / float(_points.size())
	var corners: Array = state.geo["corners"]
	var unseen_corners: Array = []
	for i in corners.size():
		if not _corners_seen.get(i, false):
			unseen_corners.append(corners[i]["pos"])
	for p in world.perception.visible_points(unseen_corners):
		for i in corners.size():
			if corners[i]["pos"] == p:
				_corners_seen[i] = true


## A point through the door, on the line from `from` through the threshold: where to look from a pie
## step.
func _through_door(from: Vector2) -> Vector2:
	var door: Vector2 = state.geo["pos"]
	return door + (door - from).normalized() * 300.0


## Commit to the crossing: pick the corner for this member's place in the order, radio `going_in`,
## go.
func _start_cross(team: Array) -> void:
	var order := readiness.members_before(self).filter(
		func(m): return StackClaim.through(m["step"]),
	).size()
	corner = _corner_for(
		order,
		team.any(func(m): return int(m["side"]) != 0 and int(m["side"]) != state.side),
	)
	approach.set_phase("cross")
	_radio("going_in")


## The corner (or spot) the member `order`-th through the door enters to. The point buttonhooks to
## the corner on the door's wall on its own side; alone, it goes to that wall's corner on the side
## away from where it stands, so it crosses the room's front; on a stack `split` across the door
## (E19) it crosses to the corner on the far side. The second crosses to the hard corner on the
## other side from its own (on the door's wall, else any hard one there, else the near one): on a
## split stack, the side the point came from. Later members take a spot inside, off the axis.
func _corner_for(order: int, split := false) -> Vector2:
	var corners: Array = state.geo["corners"]
	if order == 0:
		if split:
			return _pick_corner(corners, -state.side, true)
		var own := state.side
		if state.solo:
			own = -_pie_side if pie_sides > 0 else -state.side
		return _pick_corner(corners, own, false)
	if order == 1:
		return _pick_corner(corners, -state.side, true)
	var door: Vector2 = state.geo["pos"]
	return world.loco.reachable(door - (state.geo["out"] as Vector2) * 90.0
			+ (state.geo["along"] as Vector2) * state.side
				* (float(state.geo["width"]) * 0.5 + SPOT_SPACING * (order - 1)))


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
func _tick_cross(delta: float) -> void:
	world.loco.move_to(corner, CORNER_REACH)
	if world.character.movement.move_input == Vector2.ZERO and not world.loco.crowd.holding():
		# Never stand in the funnel (unless a body is in the way).
		var to_corner: Vector2 = corner - world.character.global_position
		world.character.movement.move_input = to_corner.normalized()
	_look_toward(_across_from(corner), delta, 3.0)
	var rel: Vector2 = world.character.global_position - (state.geo["pos"] as Vector2)
	var through: bool = (rel.dot(state.geo["out"]) < -StackClaim.THROUGH_DEPTH
			and absf(rel.dot(state.geo["along"])) > float(state.geo["width"]) * 0.5)
	if (through
			or state.clock > CROSS_CAP
			or world.character.global_position.distance_to(corner) <= WAYPOINT_REACH):
		_radio("in")
		approach.set_phase("corner")


## Where to look from a corner: across the room, at the far side opposite it.
func _across_from(p: Vector2) -> Vector2:
	var room: Rect2 = state.geo["room"]
	return room.get_center() * 2.0 - p


## Into the corner, then hold it looking across the room for `tuning.entry.corner_dwell` (even when
## the team has already called the room clear: its sector is covered either way); then clear the
## room by sight.
func _tick_corner(team: Array, delta: float) -> void:
	_look_toward(_across_from(corner), delta, 3.0)
	if not approach.arrived_at(corner, CORNER_REACH) and state.clock < CROSS_CAP:
		world.loco.move_to(corner, CORNER_REACH)
		_dwell = 0.0
		return
	world.character.movement.move_input = Vector2.ZERO
	_dwell += delta
	if _dwell >= world.tuning.entry.corner_dwell and _cleared_by_team(team):
		_finish(team)
	elif _dwell >= world.tuning.entry.corner_dwell:
		approach.set_phase("clear")
		world.coverage.begin()


## Cover the room by sight; when done, and the rest of the stack is in too (or has had
## `tuning.entry.ready_timeout` to come), radio it clear and move on. An ally that radioed it clear
## first ends this NPC's search.
func _tick_clear(team: Array, delta: float) -> void:
	if _cleared_by_team(team):
		_finish(team)
		return
	if not _covered:
		_covered = world.coverage.step(delta)
		return
	world.character.movement.move_input = Vector2.ZERO
	_look_toward(_across_from(world.character.global_position), delta)
	var coming := team.filter(
		func(m): return not StackClaim.through(m["step"]) and m["step"] != "claim",
	)
	if coming.is_empty() or state.clock >= world.tuning.entry.ready_timeout + CROSS_CAP:
		_radio("clear", { "cleared_room": state.into })
		_finish(team)


## Whether an ally of this entry has radioed the room clear (its latest call may already be the
## watch it keeps after).
func _cleared_by_team(team: Array) -> bool:
	return team.any(func(m): return StackClaim.cleared(m["step"]))


## The room is clear (by this NPC's sight or an ally's call): it is marked cleared, so nothing walks
## into it unprepared again (the entry guard, E9). Then the room is held (E8): with a team, each
## member covers a different doorway on into a room not yet cleared, and a member left over holds
## the doorway it came by, facing back out. A room with no doorway on leaves only the last of the
## team in on the rear; everyone else is done. Alone, it looks through each doorway on in turn.
func _finish(team: Array) -> void:
	world.perception.mark_cleared(state.into)
	_watch = _watch_doors()
	if _watch.is_empty():
		_hold_rear_or_done()
		return
	if readiness.through.is_empty():
		_sweep = _watch.duplicate()
		_dwell = 0.0
		approach.set_phase("cover")
		return
	if _claim_door(team):
		approach.set_phase("cover")
		_radio("cover", { "covering": covering })
		return
	_hold_rear_or_done(true)


## Hold the doorway this NPC came by, facing back out (rear security): a member left over when the
## team covers the doorways on (`spare`), or the last of the team in; anyone else is done.
func _hold_rear_or_done(spare := false) -> void:
	covering = ""
	var last := (not readiness.through.is_empty()
			and readiness.through.values().all(func(other_slot): return other_slot < state.slot))
	if not (last or (spare and not readiness.through.is_empty())):
		_end_hold()
		return
	# A spot of its own: the slots take turns either side of the doorway, each pair a body's
	# clearance further along the wall, counted from the point's side, the same for every member (a
	# split stack's members stacked on either side, E19).
	var door: Vector2 = state.geo["pos"]
	var rank := maxi(state.slot - 1, 0)
	var first := claim.lead_side if claim.lead_side != 0 else state.side
	var on := first if rank % 2 == 0 else -first
	_rear_spot = world.loco.reachable(door - (state.geo["out"] as Vector2) * 30.0
			+ (state.geo["along"] as Vector2) * on
				* (float(state.geo["width"]) * 0.5 + 24.0 + SPOT_SPACING * floorf(rank / 2.0)))
	approach.set_phase("rear")
	_radio("rear")
	world.character.movement.move_input = Vector2.ZERO


## The doorways on out of the cleared room, each with where to stand to cover it and where to point
## the gun: inside the cleared room, `COVER_DEPTH` back from the doorway and off its axis on the
## side this NPC is on, looking through it.
func _watch_doors() -> Array:
	var out: Array = []
	var room: Rect2 = (state.geo["room"] as Rect2).grow(-COVER_INSET)
	for d in world.perception.entry_watch_doors(state.into, state.opening):
		var g: Dictionary = world.perception.entry_geometry(d["id"], d["into"])
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


## Claim the doorway on that is nearest this NPC and that no teammate covers, keeping the one it
## already covers while that stays its own (when two claim one, the lower instance id keeps it, as
## with a stack slot). False when every doorway on is covered.
func _claim_door(team: Array) -> bool:
	var me: int = world.character.get_instance_id()
	var best := {}
	for w in _watch:
		var mine := team.all(
			func(m): return m["step"] != "cover" or m["covering"] != w["id"] or me < m["id"],
		)
		if not mine:
			continue
		if w["id"] == covering:
			best = w
			break
		if (best.is_empty()
				or world.character.global_position.distance_to(w["spot"])
					< world.character.global_position.distance_to(best["spot"])):
			best = w
	if best.is_empty():
		return false
	covering = best["id"]
	_cover_spot = best["spot"]
	_cover_aim = best["aim"]
	return true


## Hold the cleared room covering a doorway on: to the cover spot with the gun through that doorway,
## kept there until a teammate who held the room moves on, or `tuning.entry.cover_time` runs out. A
## teammate that takes the same doorway with a lower instance id makes this NPC take another (or the
## rear). Alone: look through each doorway on in turn, `tuning.entry.watch_dwell` each once the gaze
## has settled, then done.
func _tick_cover(team: Array, delta: float) -> void:
	if state.clock >= world.tuning.entry.cover_time:
		_end_hold()
		return
	if not _sweep.is_empty():
		_tick_sweep(delta)
		return
	if _team_moved(team):
		_end_hold()
		return
	var was := covering
	if not _claim_door(team):
		_hold_rear_or_done(true)
		return
	if covering != was:
		_radio("cover", { "covering": covering })
	if not approach.arrived_at(_cover_spot):
		world.loco.move_to(_cover_spot)
	else:
		world.character.movement.move_input = Vector2.ZERO
	_look_toward(_cover_aim, delta, 3.0)


## Alone in the cleared room: look through the next doorway on in turn, `tuning.entry.watch_dwell`
## once the gaze has settled, then on to the next; done after the last.
func _tick_sweep(delta: float) -> void:
	world.character.movement.move_input = Vector2.ZERO
	var w: Dictionary = _sweep[0]
	var at: Vector2 = w["pos"]
	if _look_toward(at + (at - world.character.global_position).normalized() * 300.0, delta, 2.0):
		_dwell += delta
	else:
		_dwell = 0.0
	if _dwell >= world.tuning.entry.watch_dwell:
		_sweep.pop_front()
		_dwell = 0.0
		if _sweep.is_empty():
			_end_hold()


## Hold just inside the doorway facing back out the way the team came, until a teammate who held the
## room moves on or `tuning.entry.rear_security_time` runs out.
func _tick_rear(team: Array, delta: float) -> void:
	if not approach.arrived_at(_rear_spot):
		world.loco.move_to(_rear_spot)
	else:
		world.character.movement.move_input = Vector2.ZERO
	_look_toward((state.geo["pos"] as Vector2) + (state.geo["out"] as Vector2) * 300.0, delta, 3.0)
	if state.clock >= world.tuning.entry.rear_security_time or _team_moved(team):
		_end_hold()


## Whether a teammate who was holding the cleared room (covering a doorway or the rear) has moved
## on: its latest call is no longer a hold on this doorway (it radioed `done` or `abort`, or claims
## another doorway).
func _team_moved(team: Array) -> bool:
	for m in team:
		if StackClaim.holding(m["step"]):
			_holders[m["id"]] = true
	for id in _holders:
		if not team.any(func(m): return m["id"] == id and StackClaim.holding(m["step"])):
			return true
	return false


## The watch is over: radio `done` (a teammate still holding the room takes it as the team moving
## on) and finish.
func _end_hold() -> void:
	if state.phase in ["cover", "rear"] and not readiness.through.is_empty():
		_radio("done")
	state.phase = "done"


## Queue step `what` for the radio, a claim in `StackClaim`'s fields (and remember it, with its
## extra fields, for the heartbeat).
func _radio(what: String, extra := {}) -> void:
	if state.secure:
		return  # A pass-by joins no stack and claims nothing on the radio.
	# (A new claim: the heartbeat's repeat keeps the frame it was made on.)
	if what == "claim" and not extra.has("claim_frame"):
		claim.frame = GameClock.frame()
		claim.pos = world.character.global_position
	# (D14: the frame its crossing began on, once; its `going_in` is committed.)
	if readiness.crossed_frame < 0 and StackClaim.crossing(what):
		readiness.crossed_frame = GameClock.frame()
	var msg := { "entry_step": what, "claim_frame": claim.frame, "claim_pos": claim.pos }
	msg.merge(extra)
	msg["crossed_frame"] = readiness.crossed_frame
	msg["bang"] = state.bang
	msg["bang_off"] = _bang_off
	msg["stuns"] = _stuns
	msg["frags"] = _frags
	# (E2: the slot it moved up from, while it walks into the one it took.)
	msg["move_up"] = claim.move_up
	msg["pie"] = _pie_begun
	msg["join"] = orders.join  # A join's claim, never its holder's own (D30).
	if orders.id != "":
		# An ordered stack's claim (LD9): the order, its mode and its side, so the stack goes in the
		# order's way.
		msg["order_id"] = orders.id
		msg["order_bang"] = orders.bang
		msg["order_mode"] = orders.mode  # (LD14.)
		msg["order_hold"] = orders.hold  # Held for the leader's go, and whether it came (LD13).
		msg["order_go"] = readiness.released
		msg["order_side"] = orders.side
		msg["order_frame"] = orders.frame
	_calls.append(msg)
	_last_call = msg.duplicate()
	_heartbeat = StackClaim.HEARTBEAT


## Look where it walks: a few paces down its path (the door it is lining up), not the next waypoint
## beside it.
func _aim_travel() -> void:
	if world.character.movement.move_input == Vector2.ZERO:
		return
	var ahead: Vector2 = world.eyes.travel_point()
	var toward: Vector2 = ((ahead - world.character.global_position)
			if ahead != Vector2.INF
			else world.character.movement.move_input)
	var from: Vector2 = world.character.global_position
	world.character.movement.aim_point = from + toward.normalized() * 100.0
	_look_angle = toward.angle()


## Turn the gaze toward `point` at `tuning.coverage.look_rate` (× `speed`); true once it is there.
func _look_toward(point: Vector2, delta: float, speed := 1.0) -> bool:
	_look_angle = Watch.ease_gaze(
		world.character,
		point,
		world.tuning.coverage.look_rate * speed,
		delta,
	)
	var desired := (point - (world.character.global_position as Vector2)).angle()
	return state.gaze_held or absf(angle_difference(_look_angle, desired)) <= GAZE_SETTLED
