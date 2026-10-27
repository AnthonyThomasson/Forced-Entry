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
## through the perception (`entry.stack`). The point crosses when every member of the stack is ready
## or `tuning.entry.ready_timeout` runs out (E6); a follower crosses `tuning.entry.follow_gap` after
## the member ahead of it goes (as it starts its crossing on the same side of the door, once it is
## through across it). With nobody else claiming the doorway the NPC goes alone; an ally that claims
## a slot before it commits joins the stack (E7). In a **bang entry** the stack
## throws a stun grenade into the room first (the `bang` phase, below): the point skips the pie and
## crosses the moment it goes off. Any entry into a room the NPC suspects a hostile in, with a stun
## in the stack, is a bang one, whatever order brought it to the doorway; a quiet entry turns into a
## bang one when a reason to suspect the room comes up before anyone crosses (E17,
## `listen.maybe_upgrade`). Owns that state and nothing else: `Behavior` calls `begin()` on adopting
## an ENTER leaf and `step()` every tick until it reports done.

## The entry claim's wire format, step lists and slot distances (perception's stack module).
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
const StackLayout := preload("res://scenes/ai/perception/stack/stack_layout.gd")
const EntryState := preload("res://scenes/ai/behavior/entry/entry_state.gd")
const EntryWorld := preload("res://scenes/ai/behavior/entry/entry_world.gd")
const EntryClaim := preload("res://scenes/ai/behavior/entry/entry_claim.gd")
const EntryApproach := preload("res://scenes/ai/behavior/entry/entry_approach.gd")
const EntryReadiness := preload("res://scenes/ai/behavior/entry/entry_readiness.gd")
const EntryOrders := preload("res://scenes/ai/behavior/entry/entry_orders.gd")
const EntryGrenade := preload("res://scenes/ai/behavior/entry/entry_grenade.gd")
const EntryListen := preload("res://scenes/ai/behavior/entry/entry_listen.gd")
const EntryPie := preload("res://scenes/ai/behavior/entry/entry_pie.gd")
const EntrySweep := preload("res://scenes/ai/behavior/entry/entry_sweep.gd")
const EntryHold := preload("res://scenes/ai/behavior/entry/entry_hold.gd")
const EntryRadio := preload("res://scenes/ai/behavior/entry/entry_radio.gd")
## A waypoint (px) counts as reached this close.
const WAYPOINT_REACH := 20.0
## Distance (px) between the spots two members hold side by side (the later members' spots inside,
## the rear spots): clear of each other's footprint, so neither stands in the hole the other's body
## cuts in the steering map.
const SPOT_SPACING := 44.0

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
## The bang: who throws, the throw, the bursts (`entry/entry_grenade.gd`).
var grenade := EntryGrenade.new(state, world)
## How a quiet entry turns into a bang one (`entry/entry_listen.gd`).
var listen := EntryListen.new(state, world)
## Slicing the pie (`entry/entry_pie.gd`).
var pie := EntryPie.new(state, world)
## Its gaze, the crossing, the corner and the clear (`entry/entry_sweep.gd`).
var sweep := EntrySweep.new(state, world)
## Holding the cleared room (`entry/entry_hold.gd`).
var hold := EntryHold.new(state, world)
## Its steps on the team radio (`entry/entry_radio.gd`).
var radio := EntryRadio.new(state, world)


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
	state.geo = world.perception.entry.geometry(state.opening, state.into)
	if state.geo.is_empty():
		state.phase = "done"
		return false
	claim.read_stack()
	var team: Array = claim.stack.team
	world.self_id = world.character.get_instance_id()
	grenade.stuns = world.character.inventory.item_count(ItemRegistry.STUN_SLOT)
	grenade.frags = world.character.inventory.item_count(ItemRegistry.FRAG_SLOT)
	orders.begin_order(self, params)
	listen.begin_mode(self, team, bool(params.get("bang", false)))
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
	sweep.points = world.coverage.sample_room(state.into)
	sweep.unseen = sweep.points.duplicate()
	sweep.look_angle = world.character.facing.angle()
	grenade.note_burst_before()
	approach.enter_approach(self, claim.stack)
	radio.say(self, "claim")
	return true


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
	state.bang = false
	state.geo = {}
	state.held_back = false
	state.clock = 0.0
	state.time = 0.0
	claim.reset()
	approach.reset()
	readiness.reset()
	orders.reset()
	grenade.reset()
	listen.reset()
	pie.reset()
	sweep.reset()
	hold.reset()
	radio.reset()


## Give the entry up (the NPC chose something else, e.g. a fight): radio `abort` so the stack stops
## counting on it. An entry none of whose steps has gone out yet (its claim held back) gives nothing
## up: its steps are dropped.
func abandon() -> void:
	if state.phase in ["", "done"]:
		return
	if radio.on_air:
		radio.say(self, "abort")
	else:
		radio.calls = []
	state.phase = "done"


## Whether the entry `params` names can begin on its doorway's slots: they are laid (`wall_n` and
## the rest, `AgentPerception.entry.geometry`) only on a baked nav map, and a stack claims by them.
## True for a doorway the perception does not know (`begin` then fails at once).
func laid(params: Dictionary) -> bool:
	var g: Dictionary = world.perception.entry.geometry(
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
## walk with no way through end it (`grenade.give_up_bang`).
func throwing() -> bool:
	return state.phase == "bang" and grenade.stage in ["go", "throw"]


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
	var out := radio.calls
	radio.calls = []
	radio.on_air = radio.on_air or not out.is_empty()
	return out


## The frag this NPC threw into the room for the bang since the last call (`{ kind, point }`, the
## point it was aimed at), once, for the controller to radio as `frag_out` (LD14); {} for none. A
## stun's bang radios nothing of its throw.
func take_thrown() -> Dictionary:
	var out := grenade.thrown
	grenade.thrown = {}
	return out


## Whether this member holds in its slot, ready, for the leader's go (LD13): the stack it is in was
## ordered to hold and has had no go.
func holding_for_go() -> bool:
	return readiness.holding and state.phase == "stack"


## Whether this member holds its slot crouched for the frag its stack throws into the room (LD14):
## the bang phase of a frag stack, in its slot (the thrower once it is back in it).
func holds_crouched() -> bool:
	return state.phase == "bang" and grenade.kind == &"frag" and not throwing() \
		and world.character.global_position.distance_to(claim.spot) <= WAYPOINT_REACH


## The entry as data, for `debug_entry()` / `debug_state()` and the tests: the doorway, slot, side,
## role, phase, what the pie saw and where it is going.
func debug() -> Dictionary:
	if state.phase == "":
		return {}
	var hidden: Array = []
	for i in state.geo.get("corners", []).size():
		if not sweep.corners_seen.get(i, false):
			hidden.append(state.geo["corners"][i]["pos"])
	return {
		"opening": state.opening, "into": state.into, "slot": state.slot, "side": state.side,
		"place": claim.place, "solo": state.solo, "phase": state.phase, "secure": state.secure,
		"seen_fraction": pie.seen_fraction, "pie_sides": pie.sides,
		"hidden_corners": hidden, "corner": sweep.corner,
		"stack_point": claim.spot if not state.geo.is_empty() else Vector2.INF,
		"team": readiness.team_size, "covering": hold.covering,
		"watch_doors": sweep.watch.map(func(w): return w["id"]), "bang": state.bang,
		"bang_off": grenade.off, "upgraded": listen.upgraded, "bang_stage": grenade.stage,
		"order_id": orders.id, "order_mode": orders.mode, "order_hold": orders.hold,
		"released": readiness.released, "holding": holding_for_go(), "kind": grenade.kind,
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
		"my_slot": claim.spot, "pie": state.geo["pie"], "pie_queue": pie.queue.duplicate(),
		"pie_side": pie.side, "pie_sides": pie.sides, "corners": corners, "corner": sweep.corner,
		"waypoints": approach.waypoints.duplicate(),
		"unseen": sweep.unseen.duplicate() if state.phase == "pie" else [],
		"seen_fraction": pie.seen_fraction,
		"gaze": Vector2.from_angle(sweep.look_angle), "ready_left": ready_left,
		"follow_left": follow_left,
		"waiting_for": (
			team.filter(func(m): return m["step"] == "claim").map(func(m): return str(m["name"]))
		),
		"team": team.map(func(m):
			var d: Dictionary = m.duplicate()
			d["through"] = StackClaim.through(m["step"])
			d["place"] = StackLayout.place(members, int(m["side"]), int(m["slot"]))
			return d),
		"watch": sweep.watch.map(
			func(w): return { "id": w["id"], "pos": w["pos"], "spot": w["spot"], "aim": w["aim"] }
		),
		"covering": hold.covering, "sweep": sweep.queue.map(func(w): return w["id"]),
		"rear_spot": hold.rear_spot,
		"hold_left": hold_left, "ready_total": world.tuning.entry.ready_timeout,
		"follow_total": world.tuning.entry.follow_gap, "hold_total": _view_hold_total(),
	}


## The doorway's corners for `debug_view`, each with whether the pie saw it (`seen`).
func _view_corners() -> Array:
	var corners: Array = []
	for i in (state.geo["corners"] as Array).size():
		var c: Dictionary = (state.geo["corners"][i] as Dictionary).duplicate()
		c["seen"] = sweep.corners_seen.get(i, false)
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
	grenade.stuns = world.character.inventory.item_count(ItemRegistry.STUN_SLOT)
	grenade.frags = world.character.inventory.item_count(ItemRegistry.FRAG_SLOT)
	readiness.holding = false
	grenade.note_burst()
	readiness.note_team(self, team)
	orders.note_go(self)
	readiness.note_all_in(self, team)
	if state.phase in ["approach", "stack", "pie"]:
		claim.keep_slot(self)
		orders.follow_order(self, team)
		listen.maybe_upgrade(self, team, delta)
	if state.phase in ["approach", "stack", "bang", "pie", "cross"]:
		var crossing: Array = claim.stack.crossing(
			{ "id": world.self_id, "slot": state.slot, "side": state.side }
		)
		claim.lead_side = int(crossing[0]["side"])
	radio.heartbeat -= delta
	if radio.heartbeat <= 0.0 and not radio.last_call.is_empty():
		# Keep the claim (and what it covers) alive on the radio.
		radio.say(self, radio.last_call["entry_step"], radio.last_call)
	match state.phase:
		"approach":
			approach.tick_approach(self, team, delta)
		"stack":
			readiness.tick_stack(self, team, delta)
		"bang":
			grenade.tick_bang(self, team, delta)
		"pie":
			pie.tick_pie(self, team, delta)
		"cross":
			sweep.tick_cross(self, delta)
		"corner":
			sweep.tick_corner(self, team, delta)
		"clear":
			sweep.tick_clear(self, team, delta)
		"cover":
			hold.tick_cover(self, team, delta)
		"rear":
			hold.tick_rear(self, team, delta)
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
			if not pie.queue.is_empty():
				pie.queue.pop_front()
				state.clock = 0.0
		"bang":
			if grenade.stage == "go":
				grenade.give_up_bang(self)
				approach.set_phase("stack")
		"cross":
			if approach.blocked_count < 2:
				# The member ahead is still in the doorway: it moves on into the room in a moment.
				return false
			var off: Vector2 = world.character.global_position - (state.geo["pos"] as Vector2)
			if off.dot(state.geo["out"]) >= -StackClaim.THROUGH_DEPTH:
				radio.say(self, "abort")
				state.phase = "done"
				return true
			sweep.corner = world.character.global_position
		"corner":
			sweep.corner = world.character.global_position
		"clear":
			hold.covered = true
		"cover":
			hold.cover_spot = world.character.global_position
		"rear":
			hold.rear_spot = world.character.global_position
	return false


## Whether the live grenade of the evade reflex's `plan` (`AgentPerception.grenades.evade_plan`) is
## the one this entry is waiting for (the evade reflex then leaves the stack to its own turned-away
## hold, beside the wall and out of the burst's line): any stun, while a stun's bang phase runs (in
## flight it is at the doorway, where its landing is not known to those who did not throw it); a
## frag, while a frag's bang phase runs, in flight (the stack's own, aimed where no slot is in its
## zone, D16) or come down where this member's slot is out of its danger zone (LD14: the slot is its
## cover; one the frag reaches, a frag that came back to the door, is evaded as anywhere).
func expects_burst(plan: Dictionary) -> bool:
	if state.phase != "bang" or plan.get("kind") != grenade.kind:
		return false
	return grenade.kind == &"stun" or not bool(plan.get("landed", false)) \
		or not world.perception.grenades.in_zone(
			grenade.kind,
			plan.get("lies", plan["point"]),
			claim.spot,
		)
