extends RefCounted
## AI BEHAVIOUR sub-domain — TACTICAL ENTRY's grenade, a part the entry holds as
## `grenade`: the bang (E17, `docs/grenades.md` G18, `docs/leadership.md` LD14): the
## grenades this member carries, who throws, the plan of the throw, the thrower's walk out,
## throw and walk back through `Combat`'s `throw`, the bang given up, and the bursts in the
## room the stack goes in on.
## Built once by the entry (`entry.gd`) on its shared `state` and `world`, it holds nothing
## else: what it needs of the entry and of its other parts is handed in at the call (`entry`),
## so no reference cycle forms.

## The entry this part is one of, handed in at the call (never held: it holds the part).
const Entry := preload("res://scenes/ai/behavior/entry.gd")
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
const EntryState := preload("res://scenes/ai/behavior/entry/entry_state.gd")
const EntryWorld := preload("res://scenes/ai/behavior/entry/entry_world.gd")
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

## The entry's state, shared with it and its other parts.
var state: EntryState
## What the entry works with, shared with it and its other parts.
var world: EntryWorld
## Stun grenades this NPC carries (radioed, so the stack knows who can throw).
var stuns := 0
## The thrower's part: "go" (to the throw spot), "throw", "back" (to its slot); "" for everyone
## else.
var stage := ""
## Where the thrower throws from.
var _bang_spot := Vector2.INF
## The points it walks through to get there: out from its slot first, clear of the member ahead of
## it, then along.
var _bang_route: Array = []
## Where the stun is thrown to, in the room.
var _bang_target := Vector2.INF
## Seconds a stack-ready member has waited for the bang to be called.
var wait := 0.0
## The stack's stun, or its own team's stun or frag, went off in the room: the point crosses at
## once, no pie.
var over := false
## This member gave the bang up (no lob, no stun, a cap ran out): radioed as `bang_off`, which keeps
## the whole stack quiet.
var off := false
## The `GameClock` frame of the last burst in the room this entry has taken note of.
var _burst_seen := -1
## `state.time` of the burst in the room (negative: before the entry began).
var _burst_at := -INF
## Frag grenades this NPC carries (radioed, so a frag stack knows who can throw, LD14).
var frags := 0
## The grenade the bang throws: a stun, or a frag for a stack ordered so (LD14).
var kind: StringName = &"stun"
## The frag this NPC threw for the bang, to radio (`take_thrown`): { kind, point }; {} for none.
var thrown := {}


## Built once by the entry, on its `state` and `world`.
func _init(entry_state: EntryState, entry_world: EntryWorld) -> void:
	state = entry_state
	world = entry_world


## Forget the running entry's grenade (`Entry.reset`).
func reset() -> void:
	stage = ""
	_bang_spot = Vector2.INF
	_bang_route = []
	_bang_target = Vector2.INF
	wait = 0.0
	over = false
	off = false
	_burst_seen = -1
	_burst_at = -INF
	frags = 0
	kind = &"stun"
	thrown = {}


## Whether the stack is in bang mode and has a stun to throw: every member's claim says bang (one
## that gave it up vetoes it), or this member's quiet entry has just turned and the rest have yet to
## follow (`listen.upgraded`: their claims say bang within a call or two), or the stack goes in
## under an order that says bang (LD9: a member still quiet follows it), and a member carries one.
## The mode is the order's, else the first claimer's (`begin`), so a stack goes in all one way.
func banging(entry: Entry, team: Array) -> bool:
	return (state.bang
			and not over
			and (entry.listen.upgraded or entry.orders.stack_ordered(entry)
					or team.all(func(m): return m["bang"]))
			and _thrower(entry) != -1)


## The instance id of the member who throws the bang's grenade (`_bang_kind`), or -1 when nobody
## can: the second of the stack if it carries one, else the lowest slot that does (alone, this NPC).
## Every member works it out from the radio's `stuns` (a frag stack's: `frags`, LD14) the same way.
func _thrower(entry: Entry) -> int:
	return entry.claim.stack.thrower(
		_bang_kind(entry),
		{ "id": world.self_id, "slot": state.slot, "stuns": stuns, "frags": frags },
	)


## A member in its slot with the stack ready that is the thrower calls the bang and goes to throw.
## Returns true once the phase has changed. A thrower with nowhere to throw from (no clear lob into
## the room) gives the bang up: the stack goes in quietly.
func due(entry: Entry, team: Array, delta: float) -> bool:
	if over or not state.bang or entry.orders.held_for_go(entry):
		return false  # (A held stack calls no bang before its go, LD13.)
	var ordered := entry.orders.stack_ordered(entry)
	if _bang_held_off(entry, team, ordered):
		return false
	return _bang_call(entry, team, ordered, delta)


## Whether the stack's bang is off for now (`due`; `ordered`: it goes in under an order): a
## teammate gave the bang up, or went in quietly before the stack turned, so this member goes in
## quietly too and its claims say so; or, in a stack nobody was ordered to, a claim says quiet: the
## stack goes in the way its first claimer chose (a claim heard after this one was made), unless
## this member's quiet entry just turned and the rest follow within a call or two.
func _bang_held_off(entry: Entry, team: Array, ordered: bool) -> bool:
	if vetoed(entry, team) or (entry.listen.upgraded and crossing(entry)):
		give_up_bang(entry)
		return true
	if not ordered and not team.all(func(m): return m["bang"]):
		if not entry.listen.upgraded:
			_go_quiet(entry)
		return true
	return false


## The bang in a stack in bang mode (`due`; `ordered`: it goes in under an order): a member
## that hears the thrower's call holds for the grenade; an ordered stack in place whose grenade is
## gone goes in quietly (D1 / D15); the thrower, once the stack is ready and no hostile stands in
## view, plans the throw and calls it (`_throw_bang`), the rest wait for it. True once the phase has
## changed.
func _bang_call(entry: Entry, team: Array, ordered: bool, delta: float) -> bool:
	if team.any(func(m): return m["step"] == "bang"):
		_enter_bang(entry)  # The thrower called it: hold, turned away, until the grenade goes off.
		return true
	if (ordered and entry.readiness.stack_ready(entry, team)
			and not _stack_has(team, _bang_kind(entry))):
		# D1 / D15: the stack is in and the order's stun (or frag) is gone: it goes in quietly, and
		# its claims say so (`bang_off`).
		give_up_bang(entry)
		return false
	if (_thrower(entry) == -1
			or not entry.readiness.stack_ready(entry, team)
			or state.hostile_in_view):
		return false
	if _thrower(entry) != world.self_id:
		wait += delta  # Waiting for the thrower to call the bang.
		return false
	return _throw_bang(entry)


## The thrower calls the bang: it plans the throw and goes to make it, radioing `bang`. With nowhere
## to throw from (no clear lob into the room) it gives the bang up: the stack goes in quietly. True
## once the phase has changed.
func _throw_bang(entry: Entry) -> bool:
	if not _plan_bang(entry):
		give_up_bang(entry)
		return false
	stage = "go"
	_enter_bang(entry)
	entry.radio.say(entry, "bang")
	return true


## Begin the bang phase, taking note of the last burst so only a grenade of the bang's kind that
## goes off from now on ends it.
func _enter_bang(entry: Entry) -> void:
	kind = _bang_kind(entry)
	entry.approach.set_phase("bang")
	_burst_seen = int(world.perception.last_burst.get("frame", -1))
	_burst_at = -INF


## Whether the point holds in its slot for the bang the stack's thrower is about to call, rather
## than slicing the pie: the stack is in bang mode and has waited less than `BANG_CALL_CAP` for it,
## or it goes in with a stun under an order and the rest of the stack, the thrower among them, is
## still on its way (D7).
func waits_for_bang(entry: Entry, team: Array) -> bool:
	if (state.bang and not over and entry.orders.stack_ordered(entry)
			and not entry.readiness.stack_ready(entry, team)):
		return true
	if not banging(entry, team):
		return false
	if wait >= BANG_CALL_CAP:
		give_up_bang(entry)
		return false
	return true


## The bang is off: the stack goes in quietly (the point slices the pie). Radioed with the next
## claim (`bang_off`), so the whole stack follows and no new reason turns it back (E17).
func give_up_bang(entry: Entry) -> void:
	off = true
	_go_quiet(entry)


## Go in quietly, as the stack's first claimer chose: radioed with the next claim. Not a veto: a new
## reason may still turn it.
func _go_quiet(entry: Entry) -> void:
	state.bang = false
	entry.listen.upgraded = false
	stage = ""
	entry.radio.say(
		entry,
		str(entry.radio.last_call.get("entry_step", "ready")),
		entry.radio.last_call,
	)


## Whether a teammate gave the bang up (its claims say `bang_off`): the stack goes in quietly. In an
## ordered stack only a member under the same order does (its stun lost or no lob, D1): an ordered
## stun stack is never vetoed by anyone else (LD9).
func vetoed(entry: Entry, team: Array) -> bool:
	var ordered := entry.orders.claim(entry)
	if ordered.is_empty():
		return team.any(func(m): return m["bang_off"])
	return team.any(func(m): return m["bang_off"] and m["order_id"] == ordered["order_id"])


## Whether a member of the stack is crossing or through the doorway.
func crossing(entry: Entry) -> bool:
	return entry.claim.stack.going_in()


## Whether the stack carries a stun: this NPC, or a teammate whose claims say so (`stuns`).
func stack_has_stun(team: Array) -> bool:
	return _stack_has(team, &"stun")


## Whether the stack carries a grenade of `grenade_kind` (`stun` / `frag`): this NPC, or a teammate
## whose claims say so (`stuns` / `frags`).
func _stack_has(team: Array, grenade_kind: StringName) -> bool:
	var key := "frags" if grenade_kind == &"frag" else "stuns"
	return _carried(grenade_kind) > 0 or team.any(func(m): return int(m[key]) > 0)


## How many grenades of `grenade_kind` (`stun` / `frag`) this NPC carries.
func _carried(grenade_kind: StringName) -> int:
	return frags if grenade_kind == &"frag" else stuns


## The grenade the stack's bang throws: a frag for a stack under an order whose mode is frag (LD14),
## else a stun.
func _bang_kind(entry: Entry) -> StringName:
	var ordered := entry.orders.claim(entry)
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
func _plan_bang(entry: Entry) -> bool:
	var type := _bang_kind(entry)
	var depth := _bang_room_depth()
	var width := absf((state.geo["room"] as Rect2).size.dot((state.geo["along"] as Vector2).abs()))
	var spots := _bang_spots(entry)
	var reach: float = world.perception.grenade_reach(type)
	var slots := _slot_points(entry) if type == &"frag" else []
	for d: float in BANG_DEPTHS:
		for a: float in BANG_ACROSS:
			for spot: Vector2 in spots:
				var target := _bang_aim(spot, depth * d, width * a, reach)
				if _bang_target_ok(target, type, slots) and _clear_lob(spot, target, reach, type):
					_take_bang(entry, spot, target)
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
func _bang_spots(entry: Entry) -> Array:
	var door: Vector2 = state.geo["pos"]
	var out: Vector2 = state.geo["out"]
	var along: Vector2 = state.geo["along"]
	var spots: Array = [entry.claim.spot]
	for share: float in BANG_STEP_ALONG:
		spots.append(world.loco.reachable(door + out * BANG_STEP_OUT
				+ along * state.side * float(state.geo["width"]) * share))
	return spots


## Whether the bang may land at `target`: inside the room, at least `BANG_MIN_DEPTH` from the door,
## and, for a frag (`grenade_kind`), where its burst reaches none of the stack's `slots` (D16).
func _bang_target_ok(target: Vector2, grenade_kind: StringName, slots: Array) -> bool:
	if (not (state.geo["room"] as Rect2).grow(-30.0).has_point(target)
			or target.distance_to(state.geo["pos"]) < BANG_MIN_DEPTH):
		return false
	return not slots.any(func(p): return world.perception.in_grenade_zone(grenade_kind, target, p))


## Take the bang's plan: thrown from `spot` at `target`, walked to out from the slot first (clear
## of the member ahead of it), then along.
func _take_bang(entry: Entry, spot: Vector2, target: Vector2) -> void:
	var door: Vector2 = state.geo["pos"]
	var out: Vector2 = state.geo["out"]
	var along: Vector2 = state.geo["along"]
	_bang_spot = spot
	_bang_target = target
	_bang_route = [
		world.loco.reachable(door + out * maxf(BANG_STEP_OUT, (spot - door).dot(out))
				+ along * (entry.claim.spot - door).dot(along)),
		spot,
	]


## Where every member of the stack stands in its slot: the slot points of the claims heard and this
## NPC's own.
func _slot_points(entry: Entry) -> Array:
	return entry.claim.stack.points(entry.claim.me(entry)).map(func(m): return m["point"]).filter(
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


## Whether a grenade of `grenade_kind` thrown by a thrower that walks to `spot` and faces `target`
## flies to it clear of the jamb (`AgentPerception.can_lob`: from its hand, with room to spare
## either side, wherever its walk into the spot may end). The target is within the grenade's throw
## reach (`reach`, `AgentPerception.grenade_reach`) of the spot, so the thrower throws from where it
## stands and does not close in.
func _clear_lob(spot: Vector2, target: Vector2, reach: float, grenade_kind: StringName) -> bool:
	return (spot.distance_to(target) <= reach
			and world.perception.can_lob(spot, target, grenade_kind, true))


## The bang phase. Everyone holds its slot turned away from the door while the stun is thrown and
## goes off (a frag: crouched, `holds_crouched`, LD14); the thrower first steps to its throw spot,
## throws (taking the grenade in hand, `Combat`) and comes back. When the stun has gone off the
## stack is over the bang: the point crosses at once (`readiness.tick_stack`), the rest follow as
## usual. The bang is given up if the throw fails, a teammate gave it up (its claims say quiet) or
## the stun does not go off.
func tick_bang(entry: Entry, team: Array, delta: float) -> void:
	if _burst_at > -INF:
		over = true
		entry.approach.set_phase("stack")
		return
	if (state.clock > (FRAG_BURST_CAP if kind == &"frag" else BANG_BURST_CAP)
			or vetoed(entry, team)
			or (not entry.orders.stack_ordered(entry) and not team.all(func(m): return m["bang"]))):
		give_up_bang(entry)
		entry.approach.set_phase("stack")
		return
	match stage:
		"go":
			_bang_go(entry, delta)
		"throw":
			_bang_throw(entry, delta)
		_:
			_bang_back(entry, delta)


## The thrower's walk out to its throw spot, all the way into it (`StackClaim.SLOT_REACH`: the lob
## was judged from there, and a stride short of it a jamb can be in its way), looking where it will
## throw; there, it stands and takes the grenade in hand to throw (`Combat`'s `throw.begin`).
func _bang_go(entry: Entry, delta: float) -> void:
	while (_bang_route.size() > 1
			and world.character.global_position.distance_to(_bang_route[0])
					<= Entry.WAYPOINT_REACH):
		_bang_route.pop_front()
	if not entry.approach.arrived_at(_bang_spot, StackClaim.SLOT_REACH):
		world.loco.move_to(
			_bang_route[0],
			StackClaim.SLOT_REACH if _bang_route.size() == 1 else 0.0,
		)
		entry.sweep.look_toward(_bang_target, delta, 3.0)
		return
	world.character.movement.move_input = Vector2.ZERO
	world.combat.throw.begin(
		ItemRegistry.FRAG_SLOT if kind == &"frag" else ItemRegistry.STUN_SLOT,
		_bang_target,
		world.perception.grenade_reach(kind),
	)
	stage = "throw"


## The thrower's throw (`Combat`'s `throw.step`): a throw that fails gives the bang up; once the
## grenade leaves its hand it walks back, and a frag is kept to radio as "frag out" (LD14,
## `take_thrown`).
func _bang_throw(entry: Entry, delta: float) -> void:
	if world.combat.throw.stage != "away" and world.combat.throw.step(delta) == &"failed":
		world.combat.throw.end()
		give_up_bang(entry)
		entry.approach.set_phase("stack")
		return
	if world.combat.throw.released():
		world.combat.throw.end()
		stage = "back"
		if kind == &"frag":
			thrown = { "kind": kind, "point": _bang_target }


## Hold the slot through the bang turned away from the door: back in it (or, shoved out of it, a
## step back in), the thrower once its grenade is away and everyone else from the call.
func _bang_back(entry: Entry, delta: float) -> void:
	var spot := entry.claim.spot
	if world.character.global_position.distance_to(spot) > Entry.WAYPOINT_REACH:
		world.loco.move_to(spot, StackClaim.SLOT_REACH)
	else:
		world.character.movement.move_input = Vector2.ZERO
	entry.sweep.look_toward(entry.claim.spot + (state.geo["out"] as Vector2) * 300.0, delta, 3.0)


## Whether a burst in the room being entered ends a wait: the perception notes every burst
## (`last_burst`). In the bang phase, a grenade of the bang's kind (a stun, or a frag stack's frag)
## its own team threw that goes off after the phase began: the stack's own, or a teammate's thrown
## another way (a GRENADE), counts as the bang. Before anyone of this member has crossed (approach,
## stack, the pie), a stun or frag its own team threw (the NPC or an ally): the entry goes in on it
## (E17), no pie, as after a bang.
func note_burst() -> void:
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
	if state.phase == "bang" and burst["kind"] != kind:
		return
	_burst_seen = int(burst["frame"])
	_burst_at = state.time
	if state.phase != "bang":
		over = true


## At `begin`: a burst from before the entry is taken note of here, not as one during it, and its
## own team's in the room a moment before (within `BANG_WINDOW`) counts, so an entry begun on the
## heels of a stun or frag thrown into the room goes in on it (a GRENADE, then the walk in).
func note_burst_before() -> void:
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
	over = true


## Whether the stun went off a moment ago (`BANG_WINDOW`): the stack goes in without the usual hold
## for a hostile in view.
func in_bang_window() -> bool:
	return over and state.time - _burst_at < BANG_WINDOW
