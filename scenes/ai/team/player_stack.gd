extends Node
## AI domain · TEAM — the human's place in an AI stack (`docs/tactical-entry.md` E16). A child of
## the human's character (Main attaches it with `attach`, as it hands an NPC its `rooms` and
## `openings`): it listens to the same `&"callout"` radio the NPCs use, and when an allied team is
## stacking at a doorway near the human it reserves the human the first free slot there, on the
## team's side of the door or, when its way there would cross the doorway's view, on the side the
## human stands on (a split stack, E19), the way an NPC claims one: a `callout` with the human as
## speaker carrying a full claim encoded by `StackClaim.encode` (every entry field an NPC's
## carries, plus `human`, `leader` and `own`), repeated every `StackClaim.HEARTBEAT` s so the claim
## stays live. The AI's entry code reads it like any teammate's claim, so the point waits for the
## human at the ready barrier, a lone AI is no longer solo, and an AI behind the human crosses
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
## `MatchSpawner.bind_squad`), its claims say so (`leader: true`, `docs/leadership.md` LD17): a
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
## set by Main through `MatchSpawner.bind_squad` for the invaders' side only, so a human defender
## leader's step-ups rally nobody. Off unless set.
var own_claims := false
## The human's character (the parent).
var _char: Node2D = null
## The doorway geometry (slots), the same the NPCs build.
var _entry: RefCounted = AgentEntry.new()
## The allies' entry claims heard on the radio, the latest per speaker (its side, `callout_range`,
## `callout_ttl` on `GameClock`).
var _ledger: RefCounted = ClaimLedger.new()
## The doorway reserved ("" = no reservation).
var _opening := ""
## The key of the room the reserved doorway leads into.
var _into := ""
## The reserved doorway's geometry (`AgentEntry.geometry`).
var _geo := {}
## The human's slot number (1 = the point; 0 = none): the order it claimed in.
var _slot := 0
## The side of the door the human stacks on (1 / -1 along its wall).
var _side := 0
## The side its slot stands on: `_side`, or the other while `_side`'s wall is full (E21).
var _on := 0
## The physics frame the claim was made on and where the human stood then (E2: same-frame claims
## settle by distance), kept by every repeat of it.
var _claim_frame := -1
var _claim_pos := Vector2.INF
## The side the team stacks on, as last weighed (a change is weighed again).
var _team_side := 0
## The human's latest radio step (claim / ready / going_in / in).
var _step := ""
## The physics frame the human's latest crossing began on (-1 for none): restamped each time its
## step goes from a waiting one (claim / ready) to `going_in` or `in`, since a human that brushed
## the funnel steps back out of it, unlike an NPC. A held stack takes it as its go only when it
## began since the order was issued (D14): a crossing already under way then is not restamped.
var _crossed_frame := -1
## Seconds until the latest step is radioed again.
var _heartbeat := 0.0
## Seconds until the next walking-distance check.
var _check := 0.0
## `GameClock.seconds()` the AI ahead of the human was first all through (-1 = not yet).
var _ahead_through_at := -1.0
## `GameClock.seconds()` the human was through.
var _in_at := -1.0
## doorway id -> true: declined, until nobody stacks there any more.
var _barred := {}
## The house's doorways and rooms (`attach`): the doorways the human may step up to.
var _openings: Array = []
## Whether the reservation is the human's own claim (it stepped up with no stack forming), not a
## slot in an allied stack.
var _own := false
## The doorway the human stands stepped up to ("" none).
var _stepping := ""
## Since when (`GameClock.seconds()`) the human has stood stepped up to `_stepping`.
var _stepping_since := 0.0


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
	if _opening == "":
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
	if _opening == "" or _geo.is_empty():
		return {}
	var slots: Array = _stack().layout(_me()).map(
		func(sl):
			return { "n": sl["n"], "point": sl["point"], "mine": sl["mine"], "held": sl["held"] },
	)
	return {
		"opening": _opening,
		"door": _geo["pos"],
		"slots": slots,
		"mine": _slot,
		"step": _step,
	}


## The reserved doorway's stack (`DoorStack`): the claims heard on it over its geometry.
func _stack() -> RefCounted:
	return _ledger.stack(_opening, _geo)


## The human's own claim as a `DoorStack` reads a member asking about itself: its slot and the side
## it stands on, the side it asks for (`want`), the frame and spot it claimed on and its step.
func _me() -> Dictionary:
	return {
		"id": _char.get_instance_id(), "slot": _slot, "side": _on, "want": _side,
		"frame": _claim_frame, "pos": _claim_pos, "step": _step,
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
	if best.is_empty() or not best["stack"].has_slot(best["stack"].slot_for(claiming)):
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


## Claim the first slot of the doorway the human has stepped up to (`_stepped_up`), none forming
## there (`stacking_now`: the doorways a stack forms at): its own claim, on the side it stands on.
func _claim_own(stacking_now: Dictionary) -> void:
	var at := _stepped_up(stacking_now)
	if at.is_empty():
		return
	_own = true
	_reserve(at["id"], at["into"], at["geo"], DoorStack.new(at["geo"], []))


## Reserve the human the first slot `stack` (the claims on doorway `id` into room `into`, geometry
## `geo`) leaves free, claiming now from where it stands, on the side it stands on unless its way
## there crosses the doorway's view (E19), and radio the claim.
func _reserve(id: String, into: String, geo: Dictionary, stack: RefCounted) -> void:
	_opening = id
	_into = into
	_geo = geo
	_claim_frame = GameClock.frame()
	_claim_pos = _char.global_position
	_slot = 0
	var at: Dictionary = stack.claim(_me(), func(_n): return _ask_side(stack, true))
	_slot = at["slot"]
	_on = at["side"]
	_step = "claim"
	_crossed_frame = -1
	_ahead_through_at = -1.0
	_in_at = -1.0
	_post(_step)


## The side the human asks for at `stack` (`_side`, kept with `_team_side`): from where it stands,
## the team's unless its way there crosses the doorway's view (E19), weighed on its claim (`first`)
## and again whenever the side the team stacks on changes (its point is known now).
func _ask_side(stack: RefCounted, first: bool) -> int:
	var pos := _char.global_position
	var team_side: int = stack.team_side(pos)
	if first or team_side != _team_side:
		_team_side = team_side
		var world := _char.get_world_2d()
		_side = _entry.stack_side_from(stack, pos, world.navigation_map, world.direct_space_state)
	return _side


## The doorway the human has stepped up to (`{ id, into, geo }`, {} for none): one no stack forms
## at (`stacking_now`) nor declined, on whose stack side it has stood `STEP_UP_TIME` against the
## wall beside the opening (out from the wall plane and past the jamb along it, each within
## `STEP_UP_REACH`): where the first of a stack stands. Not a pure query: each call advances the
## step-up timer (`_stepping`, restarted at `GameClock.seconds()` whenever the doorway stood at
## changes), so it is called once per check.
func _stepped_up(stacking_now: Dictionary) -> Dictionary:
	var pos := _char.global_position
	var world := _char.get_world_2d()
	var found := {}
	for o: Dictionary in _openings:
		var door: Vector2 = o["pos"]
		var half := float(o.get("width", 80.0)) * 0.5
		var id := AgentEntry.opening_id(o)
		if (pos.distance_to(door) > half + STEP_UP_REACH * 2.0
				or stacking_now.has(id)
				or _barred.has(id)):
			continue
		for key in o.get("rooms", []):
			var geo: Dictionary = _entry.geometry(
				id, str(key), world.navigation_map, world.direct_space_state,
			)
			if geo.is_empty() or not _entry.on_stack_side(geo, pos):
				continue
			var out := (pos - door).dot(geo["out"])
			var lateral := absf((pos - door).dot(geo["along"]))
			if (out > 0.0
					and out <= STEP_UP_REACH
					and lateral >= half
					and lateral <= half + STEP_UP_REACH):
				found = { "id": id, "into": str(key), "geo": geo }
				break
		if not found.is_empty():
			break
	var here := str(found.get("id", ""))
	if here != _stepping:
		_stepping = here
		_stepping_since = GameClock.seconds()
	if here == "" or GameClock.seconds() - _stepping_since < STEP_UP_TIME:
		return {}
	return found


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
	var pos := _char.global_position
	if due and _step != "in" and _walk_distance(_geo["pos"]) > reserve_range * leave_factor:
		_withdraw("abort")
		return
	if (not (stack.stacking() or stack.team.any(func(m): return m["step"] == "in"))
			and (not _own or _step == "in")):
		# Nobody is stacking here any more (the human's own claim stands with nobody else yet).
		_withdraw("abort" if _step != "in" else "done")
		return
	if _step != "in":
		var was := _slot
		var was_side := _on
		# An AI that keeps the same slot (claimed on its frame nearer it, else the lower instance
		# id) has it: the human takes the next free one (E2).
		var at: Dictionary = stack.claim(_me(), func(_n): return _ask_side(stack, false))
		_slot = at["slot"]
		if not at["held"]:
			_withdraw("abort")   # Pushed past what a dead end holds (E20).
			return
		_on = at["side"]
		if _slot != was or _on != was_side:
			_post(_step)
	var ahead: Array = stack.ahead(_me())
	# (Its own claim with nobody ahead of it is the point's: nobody's going in to wait on.)
	var ahead_through: bool = (
		(not _own or not ahead.is_empty())
			and ahead.all(func(m): return StackClaim.through(m["step"]))
	)
	if ahead_through and _ahead_through_at < 0.0:
		_ahead_through_at = GameClock.seconds()
	elif not ahead_through:
		_ahead_through_at = -1.0
	if (_waiting(_step)
			and _ahead_through_at >= 0.0
			and GameClock.seconds() - _ahead_through_at >= go_timeout):
		_barred[_opening] = true   # It had its chance at this stack.
		_withdraw("abort")
		return
	var now := _step_at(pos)
	if now != _step:
		if not StackClaim.crossing(_step) and StackClaim.crossing(now):
			_crossed_frame = GameClock.frame()
		_step = now
		if _step == "in":
			_in_at = GameClock.seconds()
		_post(_step)
	if _step == "in":
		var waiting: bool = stack.behind(_me()).any(
			func(m): return _waiting(m["step"]),
		)
		var held := GameClock.seconds() - _in_at
		if held >= IN_HOLD_MAX or (held >= IN_HOLD_MIN and not waiting):
			_barred[_opening] = true
			_withdraw("done")
			return
	_heartbeat -= delta
	if _heartbeat <= 0.0:
		_post(_step)


## Whether entry step `step` is a member still waiting in the stack: holding its place
## (`StackClaim.stacking`) and not yet crossing.
static func _waiting(step: String) -> bool:
	return StackClaim.stacking(step) and step != "going_in"


## The radio step for the human standing at `pos`: through the doorway (and it stays so), in the
## doorway's funnel, in its slot, or still on its way.
func _step_at(pos: Vector2) -> String:
	if _step == "in":
		return "in"
	var door: Vector2 = _geo["pos"]
	var out: Vector2 = _geo["out"]
	var outward := (pos - door).dot(out)
	var lateral := absf((pos - door).dot(out.orthogonal()))
	if (outward < -StackClaim.THROUGH_DEPTH
			and lateral < float(_geo["width"]) * 0.5 + StackClaim.THROUGH_DEPTH):
		return "in"
	if absf(outward) < StackClaim.FUNNEL_DEPTH and lateral < float(_geo["width"]) * 0.5:
		return "going_in"
	var spot: Vector2 = _stack().settle(_me())["point"]
	var d := pos.distance_to(spot)
	var reach := StackClaim.HUMAN_SLOT_REACH
	if d <= reach or (_step == "ready" and d <= reach * 2.0):
		return "ready"
	return "claim"


## Give the reservation up, telling the radio (`abort`: dropped; `done`: went through and moved on).
func _withdraw(how: String) -> void:
	_post(how)
	_own = false
	_opening = ""
	_into = ""
	_geo = {}
	_slot = 0
	_side = 0
	_on = 0
	_claim_frame = -1
	_claim_pos = Vector2.INF
	_team_side = 0
	_step = ""
	_crossed_frame = -1
	_ahead_through_at = -1.0
	_in_at = -1.0


## Radio the human's step as a `callout` (the header every callout starts with, and the claim's
## entry fields encoded by `StackClaim.encode`, the NPCs' own) and restart the heartbeat.
func _post(step: String) -> void:
	_heartbeat = StackClaim.HEARTBEAT
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
		"opening": _opening,
		"into": _into,
		"slot": _slot,
		"side": _on,
		"entry_step": step,
		# A full claim, as an NPC's (E2, E16): the frame and spot it was made on, and that it never
		# holds a stack back nor turns it, throws nothing for it and never moves up.
		"claim_frame": _claim_frame,
		"claim_pos": _claim_pos,
		"crossed_frame": _crossed_frame,  # Its latest crossing's (D14).
		"bang": true,
		"bang_off": false,
		"stuns": 0,
		"frags": 0,
		"move_up": 0,
		"pie": false,
		"leader": (squad != null and is_instance_valid(squad) and squad.has_method("leader")
				and squad.leader() == _char),
		"human": true,  # The human's claim: no AI member moves up into its slot (E2).
		"own": _own,  # Its own claim, which its squad rallies the team to (LD24); else E16's.
	}))
	EventBus.post(&"callout", msg)
