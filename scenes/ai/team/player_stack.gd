extends Node
## AI domain · TEAM — the human's place in an AI stack (`docs/tactical-entry.md` E16). A child of
## the human's character (Main attaches it with `attach`, as it hands an NPC its `rooms` and
## `openings`): it listens to the same `&"callout"` radio the NPCs use, and when an allied team is
## stacking at a doorway near the human it reserves the human the first free slot there, on the
## team's side of the door or, when its way there would cross the doorway's view, on the side the
## human stands on (a split stack, E19), the way an NPC claims one: a `callout` with the human as
## speaker (`opening`, `into`, `slot`, `side`, `entry_step`, and `human`), repeated every
## `HEARTBEAT` s so the claim stays live. The AI's entry code reads it like any teammate's claim, so
## the point waits for the human at the ready barrier, a lone AI is no longer solo, and an AI behind
## the human crosses after it. The one thing it reads `human` for: no AI member moves up into the
## human's slot (E2).
##
## The human is never ordered: its radio step is read from where it stands (`claim` away from the
## slot, `ready` in it, `going_in` in the doorway, `in` through it). The claim is withdrawn
## (`abort`) when the human leaves (walks beyond `reserve_range * leave_factor`, dies), when no one
## is left stacking, or when the AI ahead is through and the human has not crossed within
## `go_timeout`; it is finished with `done` once through and nobody waits behind it.
##
## When the human leads its side's squad (`squad`, handed in as an NPC is handed its own:
## `MatchSpawner.bind_squad`), its claims say so (`leader: true`, `docs/leadership.md` LD17): a
## stack it ordered waits for it as for an ordered member, until it stands in its slot. Leading a
## squad with another living member, it also claims of its own (LD24, D27): stepping up to a
## doorway nobody stacks at (standing `STEP_UP_TIME` against its wall beside the opening, on the
## side a stack forms on), it claims the first slot there, marked `own`, which its squad hears as
## the leader's own claim and rallies the team to; that claim is kept while nobody else stacks
## there yet. A slot it is reserved in a stack already forming is E16's: never `own`, it rallies
## nobody.
##
## `view()` is what the UI's stack markers draw. Observation and radio only: it never moves or
## steers the character.

const AgentEntry := preload("res://scenes/ai/perception/agent_entry.gd")
const AgentGrenades := preload("res://scenes/ai/perception/agent_grenades.gd")
## Entry steps that mean a member is still on its way into the room (it holds a place in the stack).
const STACKING := ["claim", "ready", "going_in"]
## Entry steps of a member that is through the doorway.
const THROUGH := ["in", "clear", "cover", "rear"]
## Seconds between repeats of the latest call.
const HEARTBEAT := 2.0
## How close (px) to its slot the human counts as standing in it (the NPCs' `WAYPOINT_REACH`).
const SLOT_REACH := 20.0
## How deep (px) either side of the wall plane the doorway's funnel reaches (the entry tests'
## `FUNNEL_DEPTH`).
const FUNNEL_DEPTH := 40.0
## How far (px) past the wall plane the human is through (the entry's `THROUGH_DEPTH`).
const THROUGH_DEPTH := 26.0
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
## How far (px) a callout carries to the human (the NPCs' `callout_range`).
@export var callout_range: float = 1500.0
## Seconds a heard callout stays current (the NPCs' `callout_ttl`).
@export var callout_ttl: float = 6.0
## Seconds the human is given to follow once the AI ahead of it is through, before its slot is
## withdrawn.
@export var go_timeout: float = 6.0

## The human's side's squad (`ai/team/squad.gd`), when it has one: its `leader()` is asked.
var squad: Node = null
## The human's character (the parent).
var _char: Node2D = null
## The doorway geometry (slots), the same the NPCs build.
var _entry: RefCounted = AgentEntry.new()
## Seconds since the stack was built (physics time).
var _clock := 0.0
## speaker instance id -> { data, at }: the latest callout of each speaker.
var _heard := {}
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
## The side the team stacks on, as last weighed (a change is weighed again).
var _team_side := 0
## The human's latest radio step (claim / ready / going_in / in).
var _step := ""
## Seconds until the latest step is radioed again.
var _heartbeat := 0.0
## Seconds until the next walking-distance check.
var _check := 0.0
## `_clock` the AI ahead of the human was first all through (-1 = not yet).
var _ahead_through_at := -1.0
## `_clock` the human was through.
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
## Since when (`_clock`) the human has stood stepped up to `_stepping`.
var _stepping_since := 0.0


func _ready() -> void:
	if _char == null:
		_char = get_parent() as Node2D
	EventBus.posted.connect(_on_posted)


func _exit_tree() -> void:
	if EventBus.posted.is_connected(_on_posted):
		EventBus.posted.disconnect(_on_posted)


func _physics_process(delta: float) -> void:
	if _char == null or not is_instance_valid(_char):
		return
	_clock += delta
	_forget_stale()
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
	var members := _members(AgentEntry.claims(_opening, _callouts()))
	var holder := {}
	var top := _slot
	for m in members:
		if not holder.has(m["slot"]) or m.get("me", false):
			holder[m["slot"]] = m
		top = maxi(top, m["slot"])
	var slots: Array = []
	for n in range(1, top + 1):
		var on: int = (int(holder[n]["side"])
				if holder.has(n) and int(holder[n]["side"]) != 0
				else AgentEntry.side_for(_geo, members, n, _side))
		var point := AgentEntry.stack_point(_geo, members, n, on)
		if point != Vector2.INF:
			slots.append({ "n": n, "point": point, "mine": n == _slot, "held": holder.has(n) })
	return {
		"opening": _opening,
		"door": _geo["pos"],
		"slots": slots,
		"mine": _slot,
		"step": _step,
	}


## The claims on the reserved doorway (`team`) with the human's own added (`me`).
func _members(team: Array) -> Array:
	return team + [
		{ "id": _char.get_instance_id(), "slot": _slot, "side": _on, "step": _step, "me": true },
	]


## Of the claims on the reserved doorway (`team`), those that cross before the human (`before` true)
## or after it, in the order the stack crosses (agent_entry.gd `crossing_order`: on a split stack
## the sides take turns, E19).
func _crossing(team: Array, before: bool) -> Array:
	var out: Array = []
	var past := false
	for m in AgentEntry.crossing_order(_members(team)):
		if m.get("me", false):
			past = true
		elif past != before:
			out.append(m)
	return out


## Keep the latest callout of each allied speaker within range (`_heard`).
func _on_posted(topic: StringName, data: Dictionary) -> void:
	if topic != &"callout" or _char == null or AgentGrenades.is_call(data.get("status")):
		# (A call about a live grenade is not the speaker's place in a stack: it must not replace
		# its claim.)
		return
	if String(data.get("order_step", "")) != "" and String(data.get("entry_step", "")) == "":
		# (Nor is how an ally's order goes, LD7: the perception leaves what the ally last said
		# standing too.)
		return
	var speaker = data.get("speaker")
	if speaker == _char or not speaker is Node or not is_instance_valid(speaker):
		return
	if StringName(data.get("faction", &"")) != StringName(_char.get("faction")):
		return
	var at: Vector2 = data.get("position", _char.global_position)
	if callout_range > 0.0 and _char.global_position.distance_to(at) > callout_range:
		return
	_heard[speaker.get_instance_id()] = { "data": data, "at": _clock }


## Drop the callouts that lapsed or whose speaker is gone or dead.
func _forget_stale() -> void:
	for id in _heard.keys():
		var rec: Dictionary = _heard[id]
		var speaker = rec["data"].get("speaker")
		if (_clock - rec["at"] > callout_ttl
				or not is_instance_valid(speaker)
				or (speaker as Node).get("is_dead") == true):
			_heard.erase(id)


## The live callouts heard, latest per speaker, in the shape `AgentEntry.claims` reads: the data
## with `age`, `id`, `name`.
func _callouts() -> Array:
	var out: Array = []
	for id in _heard:
		var rec: Dictionary = _heard[id]
		var c: Dictionary = (rec["data"] as Dictionary).duplicate()
		c["age"] = _clock - rec["at"]
		c["id"] = id
		c["name"] = str(c["speaker"].name)
		out.append(c)
	return out


## Reserve the first free slot at the nearest doorway near the human where an allied team is
## stacking up.
func _look_for_team() -> void:
	var calls := _callouts()
	var map: RID = _char.get_world_2d().navigation_map
	var space: PhysicsDirectSpaceState2D = _char.get_world_2d().direct_space_state
	var best := {}
	var best_dist := INF
	var tried := {}
	var stacking_now := {}
	for c in calls:
		var id := str(c.get("opening", ""))
		if id == "" or tried.has(id):
			continue
		tried[id] = true
		var team := AgentEntry.claims(id, calls)
		if not team.any(func(m): return STACKING.has(m["step"])):
			continue
		stacking_now[id] = true
		if _barred.has(id):
			continue
		var geo: Dictionary = _entry.geometry(id, str(c.get("into", "")), map, space)
		if geo.is_empty():
			continue
		var dist := _walk_distance(geo["pos"])
		if dist <= reserve_range and dist < best_dist:
			best_dist = dist
			best = { "id": id, "into": str(c.get("into", "")), "geo": geo, "team": team }
	for id in _barred.keys():
		if not stacking_now.has(id):
			_barred.erase(id)   # Their stack is over: a later one is a new offer.
	if best.is_empty() and _leads_team():
		_claim_own(stacking_now)
		return
	if (best.is_empty()
			or not AgentEntry.holds_slot(
					best["geo"],
					AgentEntry.free_slot(best["team"], _char.get_instance_id(), 0),
			)):
		return   # (A dead end with no room left in it holds no slot for the human either, E20.)
	_reserve(best["id"], best["into"], best["geo"], best["team"])


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
	_reserve(at["id"], at["into"], at["geo"], [])


## Reserve the human the first slot `team` (the claims on doorway `id` into room `into`, geometry
## `geo`) leaves free, on the side it stands on unless its way there crosses the doorway's view
## (E19), and radio the claim.
func _reserve(id: String, into: String, geo: Dictionary, team: Array) -> void:
	var world := _char.get_world_2d()
	var pos := _char.global_position
	_opening = id
	_into = into
	_geo = geo
	_slot = AgentEntry.free_slot(team, _char.get_instance_id(), 0)
	_team_side = AgentEntry.stack_side(_geo, team, pos)
	_side = _entry.stack_side_from(_geo, team, pos, world.navigation_map, world.direct_space_state)
	_on = AgentEntry.side_for(_geo, team, _slot, _side)
	_step = "claim"
	_ahead_through_at = -1.0
	_in_at = -1.0
	_post(_step)


## The doorway the human has stepped up to (`{ id, into, geo }`, {} for none): one no stack forms
## at (`stacking_now`) nor declined, on whose stack side it has stood `STEP_UP_TIME` against the
## wall beside the opening (out from the wall plane and past the jamb along it, each within
## `STEP_UP_REACH`): where the first of a stack stands.
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
		_stepping_since = _clock
	if here == "" or _clock - _stepping_since < STEP_UP_TIME:
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
	var calls := _callouts()
	var team := AgentEntry.claims(_opening, calls)
	var self_id := _char.get_instance_id()
	var pos := _char.global_position
	if due and _step != "in" and _walk_distance(_geo["pos"]) > reserve_range * leave_factor:
		_withdraw("abort")
		return
	if (not team.any(func(m): return STACKING.has(m["step"]) or m["step"] == "in")
			and (not _own or _step == "in")):
		# Nobody is stacking here any more (the human's own claim stands with nobody else yet).
		_withdraw("abort" if _step != "in" else "done")
		return
	if _step != "in":
		var was := _slot
		var was_side := _on
		# An AI with a lower instance id that claimed the same slot keeps it.
		_slot = AgentEntry.free_slot(team, self_id, _slot)
		if not AgentEntry.holds_slot(_geo, _slot):
			_withdraw("abort")   # Pushed past what a dead end holds (E20).
			return
		var team_side := AgentEntry.stack_side(_geo, team, pos)
		if team_side != _team_side:
			# The team's side changed (its point is known now): follow it, unless the way there
			# crosses the view.
			_team_side = team_side
			var world := _char.get_world_2d()
			_side = _entry.stack_side_from(
				_geo, team, pos, world.navigation_map, world.direct_space_state,
			)
		_on = AgentEntry.side_for(_geo, team, _slot, _side)
		if _slot != was or _on != was_side:
			_post(_step)
	var ahead := _crossing(team, true)
	# (Its own claim with nobody ahead of it is the point's: nobody's going in to wait on.)
	var ahead_through: bool = (
		(not _own or not ahead.is_empty())
			and ahead.all(func(m): return THROUGH.has(m["step"]))
	)
	if ahead_through and _ahead_through_at < 0.0:
		_ahead_through_at = _clock
	elif not ahead_through:
		_ahead_through_at = -1.0
	if (_step in ["claim", "ready"]
			and _ahead_through_at >= 0.0
			and _clock - _ahead_through_at >= go_timeout):
		_barred[_opening] = true   # It had its chance at this stack.
		_withdraw("abort")
		return
	var now := _step_at(pos)
	if now != _step:
		_step = now
		if _step == "in":
			_in_at = _clock
		_post(_step)
	if _step == "in":
		var waiting := _crossing(team, false).any(
			func(m): return STACKING.has(m["step"]) and m["step"] != "going_in",
		)
		var held := _clock - _in_at
		if held >= IN_HOLD_MAX or (held >= IN_HOLD_MIN and not waiting):
			_barred[_opening] = true
			_withdraw("done")
			return
	_heartbeat -= delta
	if _heartbeat <= 0.0:
		_post(_step)


## The radio step for the human standing at `pos`: through the doorway (and it stays so), in the
## doorway's funnel, in its slot, or still on its way.
func _step_at(pos: Vector2) -> String:
	if _step == "in":
		return "in"
	var door: Vector2 = _geo["pos"]
	var out: Vector2 = _geo["out"]
	var outward := (pos - door).dot(out)
	var lateral := absf((pos - door).dot(out.orthogonal()))
	if outward < -THROUGH_DEPTH and lateral < float(_geo["width"]) * 0.5 + THROUGH_DEPTH:
		return "in"
	if absf(outward) < FUNNEL_DEPTH and lateral < float(_geo["width"]) * 0.5:
		return "going_in"
	var spot := AgentEntry.stack_point(
		_geo,
		_members(AgentEntry.claims(_opening, _callouts())),
		_slot,
		_on,
	)
	var d := pos.distance_to(spot)
	if d <= SLOT_REACH or (_step == "ready" and d <= SLOT_REACH * 2.0):
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
	_team_side = 0
	_step = ""
	_ahead_through_at = -1.0
	_in_at = -1.0


## Radio the human's step as a `callout` (the same fields the NPCs' entry steps carry) and restart
## the heartbeat.
func _post(step: String) -> void:
	_heartbeat = HEARTBEAT
	var pos := _char.global_position
	EventBus.post(&"callout", {
		"speaker": _char,
		"faction": _char.get("faction"),
		"position": pos,
		"status": "",
		"path": "",
		"label": "stacking up (%s)" % step.replace("_", " "),
		"target_id": 0,
		"point": pos,
		"opening": _opening,
		"into": _into,
		"slot": _slot,
		"side": _on,
		"entry_step": step,
		"leader": (squad != null and is_instance_valid(squad) and squad.has_method("leader")
				and squad.leader() == _char),
		"cleared_room": "",
		"covering": "",
		"human": true,  # The human's claim: no AI member moves up into its slot (E2).
		"own": _own,  # Its own claim, which its squad rallies the team to (LD24); else E16's.
	})
