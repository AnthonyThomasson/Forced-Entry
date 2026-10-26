extends RefCounted
## AI BEHAVIOUR sub-domain — TACTICAL ENTRY's claim, a part the entry holds as `claim`: the
## slot this member claims in the doorway's stack and where it stands (E2, E19 to E22): the
## stack heard this tick, the claim as the radio carries it (the frame it was made on and
## where), the side it asks for and its place in its side's file, the move-up into a lower
## slot, and the back of the stack when the stack keeps it from its slot.
## Built once by the entry (`entry.gd`) on its shared `state` and `world`, it holds nothing
## else: what it needs of the entry and of its other parts is handed in at the call (`entry`),
## so no reference cycle forms.

## The entry this part is one of, handed in at the call (never held: it holds the part).
const Entry := preload("res://scenes/ai/behavior/entry.gd")
const Locomotion := preload("res://scenes/ai/behavior/locomotion.gd")
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
const DoorStack := preload("res://scenes/ai/perception/stack/door_stack.gd")
const EntryState := preload("res://scenes/ai/behavior/entry/entry_state.gd")
const EntryWorld := preload("res://scenes/ai/behavior/entry/entry_world.gd")
## How far (px) beyond its slot, along the wall, an entrant arrives from (`approach_lead`).
const APPROACH_LEAD := 60.0
## Farthest (px) a member standing in its slot steps to move up into a lower slot of its side (E2):
## the slot beside or in front of it.
const MOVE_UP_REACH := Entry.SPOT_SPACING * 1.5
## How much farther (px) than `MOVE_UP_REACH` from the slot a move-up would hand it a holder still
## on its way, whose way there runs through the mover's step, may be for the move-up to wait
## (`_latecomer_crosses`): one more step's length, because the latecomer walks about as far as the
## mover's step while the mover makes it, so one nearer than reach + a step can come into the step's
## way, and the two meet mid-swap, each a stride off the other's slot (the stack jams).
const MOVE_UP_MARGIN := MOVE_UP_REACH
## Seconds between looks for a slot to move up into (`move_up_now`).
const MOVE_UP_EVERY := 0.25

## The entry's state, shared with it and its other parts.
var state: EntryState
## What the entry works with, shared with it and its other parts.
var world: EntryWorld
## Its place in its side's file (1 = nearest the door): the slot, less the claims ahead on the other
## side.
var place := 0
## The side it asks for: the team's, the order's, its own on a split stack. `side` is where its slot
## is (E21).
var want := 0
## Where its slot stands (`DoorStack.settle`), worked out again as the claims
## change.
var spot := Vector2.INF
## The instance id of the leader that gave the order this entry carries out (0: none).
var leader_id := 0
## The side the team stacks on, as last weighed (a change is weighed again: E19).
var _team_side := 0
## The side the point stacked on, as last seen while the stack formed: the side every member counts
## the rear spots from.
var lead_side := 0
## The doorway's stack this tick (`AgentPerception.entry_stack`; a pass-by's has no claims): the
## claims heard and every slot rule on them.
var stack: RefCounted = DoorStack.new()
## The slot this member moved up from (E2) until it stands in the one it stepped into, else 0: its
## claim holds that one against the latecomer's.
var move_up := 0
## Seconds until the next look for a slot to move up into.
var _move_up_clock := 0.0
## The vacancies this member has moved up into (`"<holder id>:<slot>"`): one move per vacancy.
var _moved_for := {}
## The `GameClock` frame its slot was last claimed on, radioed with every call (`claim_frame`).
var frame := -1
## Where it stood then (`claim_pos`): claims made on the same frame settle by distance
## (`free_slot`).
var pos := Vector2.ZERO
## How far past its slot the approach in hand arrives from (`approach_lead`).
var lead := APPROACH_LEAD


## Built once by the entry, on its `state` and `world`.
func _init(entry_state: EntryState, entry_world: EntryWorld) -> void:
	state = entry_state
	world = entry_world


## Forget the running entry's claim (`Entry.reset`).
func reset() -> void:
	stack = DoorStack.new()
	frame = -1
	pos = Vector2.ZERO
	place = 0
	want = 0
	spot = Vector2.INF
	leader_id = 0
	_team_side = 0
	lead_side = 0
	move_up = 0
	_move_up_clock = 0.0
	_moved_for = {}
	lead = APPROACH_LEAD


## Take the back of the stack (E2: the slots go by arrival): the slot behind the last one claimed,
## when this member is not already the last and the doorway has a slot there
## (`DoorStack.back_slot`). A change is radioed as a new claim. False when there is none to take.
func to_back(entry: Entry) -> bool:
	var back: int = stack.back_slot(state.slot)
	if back == 0:
		return false
	state.slot = back
	move_up = 0
	entry.approach.forming_wait = false
	# A new slot and its own way: the hold is weighed afresh, on its own re-plan.
	entry.approach.dropped_at = Vector2.INF
	_settle(entry, stack)
	entry.approach.enter_approach(entry, stack)
	entry.radio.say(entry, "claim")
	return true


## Keep this NPC's slot, side and place in step with the radio: a slot an ally also claimed is given
## up for the next free one when the ally keeps it (one that moved up into it, E2; nearer it, of two
## claims made on one frame; else the lower instance id: `free_slot`), or for the one the ally freed
## when it moved up; and when the side the team stacks on changes (the point's, once it is known) a
## member that is not the point weighs it again: it follows it, unless its way there crosses the
## doorway's view (E19). The side is otherwise never re-read from where this NPC stands: a lone
## entrant crosses in front of the door to slice its other side. In an ordered stack (LD9) the
## order's side holds instead, for every member (`orders.ordered_side`). The place in its side's
## file follows the claims ahead on the other side. A change of slot or side is radioed as a new
## claim. The chain is the stack's (`DoorStack.claim`); the side asked for is this NPC's
## (`ask_side`).
func keep_slot(entry: Entry) -> void:
	var was := state.slot
	var was_side := state.side
	var was_spot := spot
	var at: Dictionary = stack.claim(me(entry), func(n): return ask_side(entry, n, false))
	state.slot = at["slot"]
	if state.slot != was:
		move_up = 0
	if not at["held"]:
		_refuse(entry)  # Pushed past what a dead end holds (E20).
		return
	stand(at)
	if state.slot != was or state.side != was_side or spot.distance_to(was_spot) > 1.0:
		entry.approach.enter_approach(entry, stack)  # Walk to the new slot.
		if state.slot != was or state.side != was_side:
			# (Still the claim made then: one settled by distance settles on.)
			entry.radio.say(entry, "claim", { "claim_frame": frame })


## Where this NPC's slot stands now in `door_stack` (E20 to E22, `DoorStack.settle`): the side it
## lies
## on (`side`: the one it asks for, `want`, while that side's wall has room, else the other's,
## E21), its place in that side's file and the point (`spot`); a latecomer's claim still on the
## slot it moved up into counts at the one it freed (E2).
func _settle(entry: Entry, door_stack: RefCounted) -> void:
	stand(door_stack.settle(me(entry)))


## Take where this NPC's slot stands, `at` (`DoorStack.settle` or `claim`): its side, its place in
## that side's file and its point.
func stand(at: Dictionary) -> void:
	state.side = at["side"]
	place = at["place"]
	spot = at["point"]


## The side this NPC asks for in its slot `n` (`want`, kept with `_team_side`): in an ordered stack
## (LD9) the order's, for every member (`orders.ordered_side`); else on its claim (`first`) the
## team's from where it stands, or its own when its way there crosses the doorway's view (E19);
## after that, unless it is the point, it weighs again only when the team's side changed.
func ask_side(entry: Entry, n: int, first: bool) -> int:
	var ordered := entry.orders.claim(entry)
	if not ordered.is_empty():
		want = entry.orders.ordered_side(entry, ordered, n)
		_team_side = want
	elif first:
		_team_side = stack.team_side(world.character.global_position)
		want = world.perception.entry_stack_side(stack)
	elif n != 1:
		var team_side: int = stack.team_side(world.character.global_position)
		if team_side != _team_side:
			_team_side = team_side
			want = world.perception.entry_stack_side(stack)
	return want


## This NPC's own claim as it stands, as a `DoorStack` reads a member asking about itself.
func me(entry: Entry) -> Dictionary:
	return {
		"id": world.self_id, "slot": state.slot, "side": state.side, "want": want,
		"frame": frame, "pos": pos, "move_up": move_up, "stuns": entry.grenade.stuns,
		"frags": entry.grenade.frags,
		"order_id": entry.orders.id, "order_bang": entry.orders.bang,
		"order_mode": entry.orders.mode, "order_hold": entry.orders.hold,
		"order_go": entry.readiness.released, "order_side": entry.orders.side,
		"order_frame": entry.orders.frame, "into": state.into,
	}


## Read the doorway's stack for this tick (`stack`): a pass-by joins no stack, so it hears none.
func read_stack() -> void:
	stack = DoorStack.new(
		state.geo,
		[],
	) if state.secure else world.perception.entry_stack(state.opening, state.into)


## Give the slot up: a dead end holds no slot for this NPC (E20, rule 6). Its claim is withdrawn and
## it stops where it is; an ordered member's next decision holds it there, its order refused (the
## snapshot's ORDER option).
func _refuse(entry: Entry) -> void:
	entry.radio.say(entry, "abort")
	world.character.movement.move_input = Vector2.ZERO
	state.phase = "done"


## Whether this NPC's slot is against the doorway's wall (or among the fewest-seen spots beside it),
## not one of the stack's open floor or tail past what the wall holds (rule 6): those are walked to
## by the plain way, not along the wall.
func on_wall() -> bool:
	return state.slot <= int(state.geo.get("wall_n", state.slot))


## Whether this NPC is one of the stack's tail (E20's fallback): it holds the room it came by as
## rear security and never crosses.
func tail() -> bool:
	return stack.tail(state.slot)


## How far past its slot, along the wall, this NPC arrives from: `APPROACH_LEAD`, or short of the
## nearest slot farther along this side that a teammate claims by `Locomotion.PASS_CLEARANCE` (a
## body standing there is passed no closer than that).
func approach_lead(entry: Entry, door_stack: RefCounted) -> float:
	var door: Vector2 = state.geo["pos"]
	var along: Vector2 = state.geo["along"]
	var target_lat := absf((spot - door).dot(along))
	var at_most := APPROACH_LEAD
	for m in door_stack.points(me(entry)):
		if m.get("me", false) or int(m["side"]) != state.side:
			continue
		var point: Vector2 = m["point"]
		var beyond := absf((point - door).dot(along)) - target_lat
		if beyond > 0.0:
			at_most = minf(at_most, maxf(0.0, beyond - Locomotion.PASS_CLEARANCE))
	return at_most


## Move up (E2: the slots go by arrival). Standing in its slot, this member steps into a lower slot
## on its own side, either row, within `MOVE_UP_REACH` of it, whose holder is not there yet (its
## claim still at `claim`, and farther from that slot than this member, and not near the slot this
## member would hand it by a way through this member's step, `_latecomer_crosses`) and which a short
## walk reaches, and takes that number; the holder takes the slot this member freed
## (`DoorStack.slot_for` reads the claim's `move_up`; `DoorStack.move_up_vacancies` the rule part).
## Both are radioed as claims.
## Never into the human's slot (`PlayerStack`'s claim says `human`), nor into one a member moving up
## is on its way to, nor once a member has begun the pie (`pie`), the bang or the crossing; once per
## vacancy (its holder and slot), so it never moves back and forth, though a later vacancy may move
## it up again. Looked for every `MOVE_UP_EVERY` s. True when it moved up (it walks to the new
## slot).
func move_up_now(entry: Entry, delta: float) -> bool:
	_move_up_clock -= delta
	if _move_up_clock > 0.0:
		return false
	_move_up_clock = MOVE_UP_EVERY
	var here: Vector2 = world.character.global_position
	if move_up > 0 or entry.pie.begun or here.distance_to(spot) > StackClaim.SLOT_REACH:
		return false
	var best := {}
	var best_stack: RefCounted = null
	var best_d := INF
	for v: Dictionary in stack.move_up_vacancies(me(entry)):
		var h: Dictionary = v["holder"]
		var point: Vector2 = v["point"]
		var d := here.distance_to(point)
		if (_moved_for.has("%d:%d" % [h["id"], v["slot"]])
				or d > MOVE_UP_REACH
				or d >= best_d
				or d >= (h["pos"] as Vector2).distance_to(point)):
			continue
		var entering := "%s>%s" % [state.opening, state.into]
		var walk := float(world.perception.walk_route(point, entering)["plain_len"])
		if walk <= 0.0 or walk > d * 1.5 + Locomotion.PASS_CLEARANCE:
			continue  # No short way there: a body or a wall between.
		if _latecomer_crosses(h, point):
			continue  # It would meet the latecomer mid-swap: the slots stand as claimed.
		best = h
		best_stack = v["stack"]
		best_d = d
	if best.is_empty():
		return false
	_moved_for["%d:%d" % [best["id"], best["slot"]]] = true
	move_up = state.slot
	state.slot = int(best["slot"])
	_settle(entry, best_stack)
	entry.approach.enter_approach(entry, best_stack)
	# A step within the stack, straight into the slot: not the approach's way along the wall from
	# past it.
	entry.approach.waypoints = []
	entry.approach.cap = world.tuning.entry.approach_time + entry.approach.walk_time(entry)
	entry.radio.say(entry, "claim", { "claim_frame": frame })
	return true


## Whether holder `h`, a teammate still on its way to its slot, may meet this member's move-up into
## `vacancy` (the point of `h`'s slot) mid-swap: it may be within `MOVE_UP_REACH` + `MOVE_UP_MARGIN`
## of the slot the move-up would hand it (this member's own, `spot`), and its straight way from
## there to that slot passes `vacancy` closer than `Locomotion.PASS_CLEARANCE` (it would walk
## through the step). Where it may be is a worst-case bound: its newest known place, seen
## (`Locomotion`'s `crowd.bodies`) or radioed (its claim's `pos`), whichever is newer, brought
## nearer by the ground it may have walked since straight at that slot, its age x its walking pace
## (an entry never runs; its own `movement.walk_speed()` when the NPC knows its body, else this
## member's). A latecomer coming up behind this member, on the same lane, does not cross: it follows
## in.
func _latecomer_crosses(h: Dictionary, vacancy: Vector2) -> bool:
	var where: Vector2 = h["pos"]
	var age := float(h.get("age", 0.0))
	var pace: float = world.character.movement.walk_speed()
	for b in world.loco.crowd.bodies:
		if int(b.get("id", 0)) != int(h["id"]):
			continue
		var seen := 0.0 if b.get("visible", false) else float(b.get("age", INF))
		if seen < age:
			where = b["pos"]
			age = seen
		var body = b.get("node")
		if is_instance_valid(body) and "movement" in body:
			pace = body.movement.walk_speed()
	var gap := where.distance_to(spot)
	if gap - age * pace > MOVE_UP_REACH + MOVE_UP_MARGIN:
		return false
	# The nearest it may be by now, on its way in.
	var at := where.move_toward(spot, minf(age * pace, gap))
	return (Geometry2D.get_closest_point_to_segment(vacancy, at, spot).distance_to(vacancy)
			< Locomotion.PASS_CLEARANCE)
