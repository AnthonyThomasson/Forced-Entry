extends Node
## AI domain · TEAM — the human's place in an AI stack (`docs/tactical-entry.md` E16). A child of
## the human's character (the match builder attaches it with `attach`, as it hands an NPC its
## `rooms` and `openings`): it listens to the same `&"callout"` radio the NPCs use, and when an
## allied team is stacking at a doorway near the human it reserves the human the first free slot
## there, on the team's side of the door or, when its way there would cross the doorway's view, on
## the side the human stands on (a split stack, E19), the way an NPC claims one: a `callout` with
## the human as speaker carrying a full claim encoded by `StackClaim.encode` (every entry field an
## NPC's carries, plus `human`, `leader` and `own`), repeated every `StackClaim.HEARTBEAT` s so the
## claim stays live. The AI's entry code reads it like any teammate's claim, so the point waits for
## the human at the ready barrier, a lone AI is no longer solo, and an AI behind the human crosses
## after it. The one thing it reads `human` for: no AI member moves up into the human's slot (E2).
##
## The human is never ordered: its radio step is read from where it stands (`claim` away from the
## slot, `ready` in it, `going_in` in the doorway, `in` through it), and its claim's
## `crossed_frame` is the frame its latest crossing began on (a held stack takes it as its go only
## when it began since the order was issued, `docs/leadership.md` D14). The claim is withdrawn
## (`abort`) when the human leaves (walks beyond `reserve_range * leave_factor`, dies), when no one
## is left stacking, or when the AI ahead is through and the human has not crossed within
## `go_timeout`; it is finished with `done` once through and nobody waits behind it.
##
## When the human leads its side's squad (`squad`, handed in as an NPC is handed its own:
## `MatchBuilder.bind_squad`), its claims say so (`leader: true`, `docs/leadership.md` LD17): a
## stack it ordered waits for it as for an ordered member, until it stands in its slot. Leading a
## squad with another living member on the invaders' side (`own_claims`, D29), it also claims of
## its own (LD24, D27): stepping up to a doorway nobody stacks at (standing `STEP_UP_TIME` against
## its wall beside the opening, on the side a stack forms on), it claims the first slot there,
## marked `own`, which its squad hears as the leader's own claim and rallies the team to; that
## claim is kept while nobody else stacks there yet. A slot it is reserved in a stack already
## forming is E16's: never `own`, it rallies nobody.
##
## `view()` is what the UI's stack markers draw. Observation and radio only: it never moves or
## steers the character.

const AgentEntry := preload("res://scenes/ai/perception/agent_entry.gd")
## The entry claim's wire format, step lists and slot distances, and the claims heard on the radio
## (scenes/ai/perception/stack/).
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
const ClaimLedger := preload("res://scenes/ai/perception/stack/claim_ledger.gd")
const DoorStack := preload("res://scenes/ai/perception/stack/door_stack.gd")
const StackLayout := preload("res://scenes/ai/perception/stack/stack_layout.gd")
const PlayerStackReservation := preload("res://scenes/ai/team/player_stack_reservation.gd")
const PlayerStackStepUp := preload("res://scenes/ai/team/player_stack_step_up.gd")
## Seconds the human's `in` stays on the radio for an AI waiting behind it to hear, and the most it
## is held.
const IN_HOLD_MIN := 1.0
const IN_HOLD_MAX := 8.0
## Seconds between the checks that need a path query (is a team near, has the human left).
const CHECK_INTERVAL := 0.25
## How far (px) out from a doorway's wall plane, and past its jamb along the wall, the human stands
## when it has stepped up to it (two bodies' room, D27).
const STEP_UP_REACH := 60.0
## How long (s) the human stands stepped up to a doorway before it claims there of its own (D27).
const STEP_UP_TIME := 0.5

## How far (px of walking) from a doorway the human may be and still be reserved a slot there.
@export var reserve_range: float = 300.0
## The reservation is dropped beyond `reserve_range` times this.
@export var leave_factor: float = 1.5
## How far (px) a callout carries to the human (the NPCs' `callout_range`): set, it reaches the
## claims it hears at once.
@export var callout_range: float = 1500.0:
	set(value):
		callout_range = value
		_ledger.setup({ "range": value })
## Seconds a heard callout stays current (the NPCs' `callout_ttl`): set, it reaches the claims it
## hears at once.
@export var callout_ttl: float = 6.0:
	set(value):
		callout_ttl = value
		_ledger.setup({ "ttl": value })
## Seconds the human is given to follow once the AI ahead of it is through, before its slot is
## withdrawn.
@export var go_timeout: float = 6.0

## The human's side's squad (`ai/team/squad.gd`), when it has one: its `leader()` is asked.
var squad: Node = null
## Whether the human, leading its squad, claims of its own at a doorway it steps up to (LD24, D29):
## set by its composer (`MatchBuilder.bind_squad`) for the invaders' side only, so a human defender
## leader's step-ups rally nobody. Off unless set.
var own_claims := false
## The human's character (the parent).
var _char: Node2D = null
## The doorway geometry (slots), the same the NPCs build.
var _entry: RefCounted = AgentEntry.new()
## The allies' entry claims heard on the radio, the latest per speaker (its side, `callout_range`,
## `callout_ttl` on `GameClock`).
var _ledger: RefCounted = ClaimLedger.new()
## The reservation held: the doorway, the human's slot and side, its claim and step (none while its
## `opening` is "").
var reservation: PlayerStackReservation = PlayerStackReservation.new()
## Seconds until the next walking-distance check.
var _check := 0.0
## doorway id -> true: declined, until nobody stacks there any more.
var _barred := {}
## The house's doorways and rooms (`attach`): the doorways the human may step up to.
var _openings: Array = []
## The human stepping up to a doorway nobody stacks at, for its own claim (LD24).
var step_up: PlayerStackStepUp = PlayerStackStepUp.new(self)


func _ready() -> void:
	if _char == null:
		_char = get_parent() as Node2D
	_ledger.setup({
		"faction": _char.get("faction"), "range": callout_range, "ttl": callout_ttl,
		"listener": _char,
	})
	EventBus.posted.connect(_on_posted)


func _exit_tree() -> void:
	if EventBus.posted.is_connected(_on_posted):
		EventBus.posted.disconnect(_on_posted)


func _physics_process(delta: float) -> void:
	if _char == null or not is_instance_valid(_char):
		return
	_check -= delta
	var due := _check <= 0.0
	if due:
		_check = CHECK_INTERVAL
	if reservation.opening == "":
		if due and _char.get("is_dead") != true:
			_look_for_team()
		return
	_keep_reservation(delta, due)


## Give `character` its stack radio: the house's `rooms` and `openings` as an NPC controller is
## handed them. Returns it.
static func attach(character: Node, rooms: Array, openings: Array) -> Node:
	var existing := character.get_node_or_null("PlayerStack")
	if existing != null:
		return existing
	var stack := new()
	stack.name = "PlayerStack"
	stack._char = character as Node2D
	stack._entry.set_house(openings, rooms)
	stack._openings = openings
	character.add_child(stack)
	return stack


## The reservation as data for the markers (`{}` with none): `opening`, `door`, `slots`
## (`{ n, point, mine, held }` for slot 1 up to the last taken, each where it stands in the file on
## its holder's side of the door: both sides on a split stack, E19; a free one on the human's side),
## `mine` (the human's slot) and `step` (its own radio step).
func view() -> Dictionary:
	if reservation.opening == "" or reservation.geo.is_empty():
		return {}
	var slots: Array = _stack().layout(_me()).map(
		func(sl):
			return { "n": sl["n"], "point": sl["point"], "mine": sl["mine"], "held": sl["held"] },
	)
	return {
		"opening": reservation.opening,
		"door": reservation.geo["pos"],
		"slots": slots,
		"mine": reservation.slot,
		"step": reservation.step,
	}


## The reserved doorway's stack (`DoorStack`): the claims heard on it over its geometry.
func _stack() -> RefCounted:
	return _ledger.stack(reservation.opening, reservation.geo)


## The human's own claim as a `DoorStack` reads a member asking about itself: its slot and the side
## it stands on, the side it asks for (`want`), the frame and spot it claimed on and its step.
func _me() -> Dictionary:
	return {
		"id": _char.get_instance_id(), "slot": reservation.slot, "side": reservation.on,
		"want": reservation.side, "frame": reservation.claim_frame, "pos": reservation.claim_pos,
		"step": reservation.step,
	}


## Hear an allied entry claim within range (the ledger keeps the latest per speaker).
func _on_posted(topic: StringName, data: Dictionary) -> void:
	if topic == &"callout" and _char != null:
		_ledger.hear(data, _char.global_position)


## Reserve the first free slot at the nearest doorway near the human where an allied team is
## stacking up.
func _look_for_team() -> void:
	var map: RID = _char.get_world_2d().navigation_map
	var space: PhysicsDirectSpaceState2D = _char.get_world_2d().direct_space_state
	var best := {}
	var best_dist := INF
	var claiming := {
		"id": _char.get_instance_id(), "slot": 0, "frame": GameClock.frame(),
		"pos": _char.global_position,
	}
	var stacking_now := {}
	for at: Dictionary in _ledger.openings_stacking():
		var id: String = at["opening"]
		stacking_now[id] = true
		if _barred.has(id):
			continue
		var geo: Dictionary = _entry.geometry(id, at["into"], map, space)
		if geo.is_empty():
			continue
		var dist := _walk_distance(geo["pos"])
		if dist <= reserve_range and dist < best_dist:
			best_dist = dist
			best = { "id": id, "into": at["into"], "geo": geo, "stack": _ledger.stack(id, geo) }
	for id in _barred.keys():
		if not stacking_now.has(id):
			_barred.erase(id)   # Their stack is over: a later one is a new offer.
	if best.is_empty() and own_claims and _leads_team():
		_claim_own(stacking_now)
		return
	if (best.is_empty()
			or not StackLayout.holds_slot(
				best["stack"].geometry,
				best["stack"].slot_for(claiming),
			)):
		return   # (A dead end with no room left in it holds no slot for the human either, E20.)
	_reserve(best["id"], best["into"], best["geo"], best["stack"])


## Whether the human leads its squad and the squad has another living member, whom its own claim
## rallies.
func _leads_team() -> bool:
	if (squad == null
			or not is_instance_valid(squad)
			or not squad.has_method("leader")
			or squad.leader() != _char):
		return false
	return squad.members().any(func(m): return m != _char and squad.alive(m))


## Claim the first slot of the doorway the human has stepped up to (`step_up.stepped`), none forming
## there (`stacking_now`: the doorways a stack forms at): its own claim, on the side it stands on.
func _claim_own(stacking_now: Dictionary) -> void:
	var at := step_up.stepped(stacking_now)
	if at.is_empty():
		return
	reservation.own = true
	_reserve(at["id"], at["into"], at["geo"], DoorStack.new(at["geo"], []))


## Reserve the human the first slot `stack` (the claims on doorway `id` into room `into`, geometry
## `geo`) leaves free, claiming now from where it stands, on the side it stands on unless its way
## there crosses the doorway's view (E19), and radio the claim.
func _reserve(id: String, into: String, geo: Dictionary, stack: RefCounted) -> void:
	reservation.opening = id
	reservation.into = into
	reservation.geo = geo
	reservation.claim_frame = GameClock.frame()
	reservation.claim_pos = _char.global_position
	reservation.slot = 0
	var at: Dictionary = stack.claim(_me(), func(_n): return _ask_side(stack, true))
	reservation.slot = at["slot"]
	reservation.on = at["side"]
	reservation.step = "claim"
	reservation.crossed_frame = -1
	reservation.ahead_through_at = -1.0
	reservation.in_at = -1.0
	_post(reservation.step)


## The side the human asks for at `stack` (`reservation.side`, kept with `reservation.team_side`):
## from where it stands, the team's unless its way there crosses the doorway's view (E19), weighed
## on its claim (`first`) and again whenever the side the team stacks on changes (its point is known
## now).
func _ask_side(stack: RefCounted, first: bool) -> int:
	var pos := _char.global_position
	var team_side: int = stack.team_side(pos)
	if first or team_side != reservation.team_side:
		reservation.team_side = team_side
		var world := _char.get_world_2d()
		reservation.side = _entry.stack_side_from(
			stack,
			pos,
			world.navigation_map,
			world.direct_space_state,
		)
	return reservation.side


## Walking distance (px) from the human to `to` over the baked map; the straight line before it is
## baked.
func _walk_distance(to: Vector2) -> float:
	var from := _char.global_position
	var straight := from.distance_to(to)
	var map: RID = _char.get_world_2d().navigation_map
	if straight > reserve_range * leave_factor or not NavBuilder.ready(map):
		return straight
	return NavBuilder.path_length(NavBuilder.route(map, from, to))


## One tick of a held reservation: leave it, follow the radio, and say where the human stands. `due`
## is true on the ticks that may afford a path query.
func _keep_reservation(delta: float, due: bool) -> void:
	if _char.get("is_dead") == true:
		_withdraw("abort")
		return
	var stack := _stack()
	if _leaves(stack, due):
		return
	if reservation.step != "in" and not _keeps_slot(stack):
		return
	if _gives_up(stack):
		return
	_take_step()
	if reservation.step == "in" and _done_inside(stack):
		return
	reservation.heartbeat -= delta
	if reservation.heartbeat <= 0.0:
		_post(reservation.step)


## Withdraw from `stack` when the human has walked off out of range (on a `due` tick, before it is
## in) or nobody stacks there any more (the human's own claim stands with nobody else yet); true
## when it did.
func _leaves(stack: RefCounted, due: bool) -> bool:
	if (due
			and reservation.step != "in"
			and _walk_distance(reservation.geo["pos"]) > reserve_range * leave_factor):
		_withdraw("abort")
		return true
	if (not (stack.stacking() or stack.team.any(func(m): return m["step"] == "in"))
			and (not reservation.own or reservation.step == "in")):
		_withdraw("abort" if reservation.step != "in" else "done")
		return true
	return false


## Keep the human's slot in `stack`: an AI that keeps the same slot (claimed on its frame nearer it,
## else the lower instance id) has it, and the human takes the next free one (E2), radioed when its
## slot or side changes. False, withdrawn, when it is pushed past what a dead end holds (E20).
func _keeps_slot(stack: RefCounted) -> bool:
	var was := reservation.slot
	var was_side := reservation.on
	var at: Dictionary = stack.claim(_me(), func(_n): return _ask_side(stack, false))
	reservation.slot = at["slot"]
	if not at["held"]:
		_withdraw("abort")
		return false
	reservation.on = at["side"]
	if reservation.slot != was or reservation.on != was_side:
		_post(reservation.step)
	return true


## Withdraw, barred from this stack, when everyone ahead of the human in `stack` has been through
## for `go_timeout` s while it still waits: it had its chance. True when it did.
func _gives_up(stack: RefCounted) -> bool:
	var ahead: Array = stack.ahead(_me())
	# (Its own claim with nobody ahead of it is the point's: nobody's going in to wait on.)
	var ahead_through: bool = (
		(not reservation.own or not ahead.is_empty())
			and ahead.all(func(m): return StackClaim.through(m["step"]))
	)
	if ahead_through and reservation.ahead_through_at < 0.0:
		reservation.ahead_through_at = GameClock.seconds()
	elif not ahead_through:
		reservation.ahead_through_at = -1.0
	if (_waiting(reservation.step)
			and reservation.ahead_through_at >= 0.0
			and GameClock.seconds() - reservation.ahead_through_at >= go_timeout):
		_barred[reservation.opening] = true   # It had its chance at this stack.
		_withdraw("abort")
		return true
	return false


## The human's step from where it stands, radioed when it changes (the frame a crossing begins on
## and the time it gets in kept).
func _take_step() -> void:
	var now := _step_at(_char.global_position)
	if now == reservation.step:
		return
	if not StackClaim.crossing(reservation.step) and StackClaim.crossing(now):
		reservation.crossed_frame = GameClock.frame()
	reservation.step = now
	if reservation.step == "in":
		reservation.in_at = GameClock.seconds()
	_post(reservation.step)


## Withdraw, done and barred from this stack, once the human has held the room `IN_HOLD_MAX` s, or
## `IN_HOLD_MIN` s with nobody behind it in `stack` still waiting. True when it did.
func _done_inside(stack: RefCounted) -> bool:
	var waiting: bool = stack.behind(_me()).any(
		func(m): return _waiting(m["step"]),
	)
	var held := GameClock.seconds() - reservation.in_at
	if held >= IN_HOLD_MAX or (held >= IN_HOLD_MIN and not waiting):
		_barred[reservation.opening] = true
		_withdraw("done")
		return true
	return false


## Whether entry step `step` is a member still waiting in the stack: holding its place
## (`StackClaim.stacking`) and not yet crossing.
static func _waiting(step: String) -> bool:
	return StackClaim.stacking(step) and step != "going_in"


## The radio step for the human standing at `pos`: through the doorway (and it stays so), in the
## doorway's funnel, in its slot, or still on its way.
func _step_at(pos: Vector2) -> String:
	if reservation.step == "in":
		return "in"
	var door: Vector2 = reservation.geo["pos"]
	var out: Vector2 = reservation.geo["out"]
	var outward := (pos - door).dot(out)
	var lateral := absf((pos - door).dot(out.orthogonal()))
	if (outward < -StackClaim.THROUGH_DEPTH
			and lateral < float(reservation.geo["width"]) * 0.5 + StackClaim.THROUGH_DEPTH):
		return "in"
	if absf(outward) < StackClaim.FUNNEL_DEPTH and lateral < float(reservation.geo["width"]) * 0.5:
		return "going_in"
	var spot: Vector2 = _stack().settle(_me())["point"]
	var d := pos.distance_to(spot)
	var reach := StackClaim.HUMAN_SLOT_REACH
	if d <= reach or (reservation.step == "ready" and d <= reach * 2.0):
		return "ready"
	return "claim"


## Give the reservation up, telling the radio (`abort`: dropped; `done`: went through and moved on).
func _withdraw(how: String) -> void:
	_post(how)
	reservation.clear()


## Radio the human's step as a `callout` (the header every callout starts with, and the claim's
## entry fields encoded by `StackClaim.encode`, the NPCs' own) and restart the heartbeat.
func _post(step: String) -> void:
	reservation.heartbeat = StackClaim.HEARTBEAT
	var pos := _char.global_position
	var msg := {
		"speaker": _char,
		"faction": _char.get("faction"),
		"position": pos,
		"status": "",
		"path": "",
		"label": "stacking up (%s)" % step.replace("_", " "),
		"target_id": 0,
		"point": pos,
	}
	msg.merge(StackClaim.encode({
		"opening": reservation.opening,
		"into": reservation.into,
		"slot": reservation.slot,
		"side": reservation.on,
		"entry_step": step,
		# A full claim, as an NPC's (E2, E16): the frame and spot it was made on, and that it never
		# holds a stack back nor turns it, throws nothing for it and never moves up.
		"claim_frame": reservation.claim_frame,
		"claim_pos": reservation.claim_pos,
		"crossed_frame": reservation.crossed_frame,  # Its latest crossing's (D14).
		"bang": true,
		"bang_off": false,
		"stuns": 0,
		"frags": 0,
		"move_up": 0,
		"pie": false,
		"leader": (squad != null and is_instance_valid(squad) and squad.has_method("leader")
				and squad.leader() == _char),
		"human": true,  # The human's claim: no AI member moves up into its slot (E2).
		# Its own claim, which its squad rallies the team to (LD24); else E16's.
		"own": reservation.own,
	}))
	EventBus.post(&"callout", msg)
