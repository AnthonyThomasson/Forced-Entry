extends RefCounted
## AI BEHAVIOUR sub-domain — the behaviour's entries, its part `entries`: running the `entry`
## primitive over `Entry` (`docs/tactical-entry.md`), the entry guard (E9, E15: a walk into a room
## not cleared goes in by entry first, as a detour that pauses the order and hands it back), an
## ordered stack's way read before its claim (LD9), and the entry read-outs. Built once with its
## `Behavior`, it holds it (a node, so no reference cycle) for the running leaf, the body, the
## perception, the locomotion and `Entry`.

## The running leaf's data (the behaviour's `task`).
const RunningLeaf := preload("res://scenes/ai/behavior/running_leaf.gd")
## The orders part (whether an entry leaf is an ordered stack's, `Orders.ordered_entry`).
const Orders := preload("res://scenes/ai/behavior/behavior_orders.gd")
## The entry claim's wire format (whether an entry leaf is a join).
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
## How far (px of walking) the entry debug view looks ahead along the walk for the next uncleared
## doorway.
const GUARD_PREVIEW_RANGE := 2000.0
## The longest (s) an entry waits for the nav map its doorway's slots are laid on (`Entry.laid`),
## and the read of an ordered entry's way (`_detour_first`) for the map round the doorway views, to
## be baked.
const ROUTE_WAIT := 2.0

## The behaviour it belongs to.
var behavior: Node
## An ENTER leaf was adopted and its entry starts on the next tick (`apply`).
var pending := false
## How long (s) an ordered entry has waited, its claim held back, for the map round the views
## (`_detour_first`).
var _route_wait := 0.0
## The leaf an entry detour paused (see `_begin_detour`); {} when the entry is the NPC's own order.
var resume := {}
## Seconds the guard has been watching (sim time), for the re-arm of a given-up doorway.
var guard_clock := 0.0
## Doorway id -> `guard_clock` before which the guard leaves it alone.
var _guard_off := {}
## The running join's end has been said (`orders.join_over`, LD25).
var join_done := false


func _init(npc_behavior: Node) -> void:
	behavior = npc_behavior


## Whether the running entry turned from quiet to a bang since the last call (E17, a late reason):
## true once.
func take_turned() -> bool:
	return behavior.task.primitive == &"entry" and behavior._entry.take_turned()


## Re-adopt the running entry order as a bang entry under `path` and `labels` (an ENTER turned STUN
## ENTRY): the entry runs on where it is, only what it is called and its `bang` param change.
func adopt_bang(path: Array, labels: Array) -> void:
	var task: RunningLeaf = behavior.task
	task.path = path
	task.labels = labels
	task.params["bang"] = true


## Read-only: the running tactical entry (doorway, slot, side, phase, what the pie saw, the corner),
## or {} when the NPC isn't entering. See entry.gd `debug()`.
func debug() -> Dictionary:
	return behavior._entry.debug() if behavior.task.primitive == &"entry" else {}


## Read-only, for the entry debug overlays: the running entry as world-space data (entry.gd
## `debug_view`, under `entry`; {} when none) and the entry guard's picture under `guard`: whether a
## detour is running and the order it paused (`resume_point`, `resume_label`), the doorways it is
## leaving alone (`rearm`: `{ opening, left }`), its `range`, the next uncleared doorway on the
## current walk (`ahead`: `{ opening, into, dist, pos }`, or {}), the rects of the rooms this NPC
## regards as cleared (`cleared_rooms`), and the doorway views its walks keep out of (`views`:
## `{ id, into, poly }`, with `round_views` true while the walk goes round them on the avoid map).
## Computed only when asked; nothing reads it back.
func debug_view() -> Dictionary:
	var task: RunningLeaf = behavior.task
	var perception: Node = behavior._perception
	var loco: Node = behavior._loco
	var guard_view := {
		"detour": task.primitive == &"entry" and not resume.is_empty(),
		"resume_point": resume.get("point", Vector2.INF),
		"resume_label": " - ".join(resume.get("labels", [])),
		"rearm": [],
		"range": behavior.tuning.entry_guard.reach,
		"ahead": {},
		"cleared_rooms": [],
		"views": [],
		"round_views": loco.debug_state().get("way", "") == "doors",
	}
	for id in _guard_off:
		var left: float = float(_guard_off[id]) - guard_clock
		if left > 0.0:
			guard_view["rearm"].append({ "opening": id, "left": left })
	if perception != null:
		guard_view["views"] = perception.avoided_views()
		for r in behavior.rooms:
			if perception.is_cleared(str(r["key"])):
				guard_view["cleared_rooms"].append(r["rect"])
		var walk: Dictionary = loco.path_ahead() if task.primitive != &"entry" else {}
		if not walk.is_empty():
			var gate: Dictionary = perception.threshold_ahead(
				walk["path"], walk["index"], GUARD_PREVIEW_RANGE,
			)
			if not gate.is_empty():
				var geo: Dictionary = perception.entry_geometry(gate["opening"], gate["into"])
				if not geo.is_empty():
					gate["pos"] = geo["pos"]
					guard_view["ahead"] = gate
	var entry: Dictionary = behavior._entry.debug_view() if task.primitive == &"entry" else {}
	return { "entry": entry, "guard": guard_view }


## The entry steps to radio since the last call (claims in `StackClaim`'s fields), with the
## doorway, the room it leads into, slot and side they are about; the controller posts them as
## callouts.
func take_calls() -> Array:
	var out: Array = []
	for c in behavior._entry.take_calls():
		c.merge({
			"opening": behavior._entry.state.opening,
			"into": behavior._entry.state.into,
			"slot": behavior._entry.state.slot,
			"side": behavior._entry.state.side,
		})
		out.append(c)
	return out


## Whether the entry guard applies to `leaf` for a doorway into room `into`: a walk (move / engage /
## interact, or a throw from a throw spot) that is not a retreat, while the NPC is not under fire,
## or, under fire, into the room the shots came from (`fight.into_the_shots`).
func guards(leaf: Dictionary, into: String) -> bool:
	var params: Dictionary = leaf.get("params", {})
	var prim: StringName = leaf.get("primitive", &"hold")
	var walks: bool = (prim in [&"move", &"engage", &"interact", &"defend", &"ambush"]
			or (prim == &"throw" and bool(params.get("walk", false))))
	return (behavior.tuning.entry_guard.enabled
			and walks
			and bool(params.get("entry_guard", true))
			and (not behavior._perception.under_fire() or behavior.fight.into_the_shots(into)))


## Whether the walk the running primitive is on keeps out of the doorway views (E18): the walks the
## entry guard covers, so a move, an engage or an interact that is not a retreat, a throw's walk to
## its throw spot, and an entry's approach to its stack (its other walks, the pie and the crossing,
## are the entry's own), while the NPC is not under fire. Not an evade. An ordered stack's walk does
## whatever `tuning.entry.enabled` says (D4).
func keeps_out_of_views() -> bool:
	var task: RunningLeaf = behavior.task
	var perception: Node = behavior._perception
	if (not behavior.tuning.entry_guard.enabled
			or not (behavior.tuning.entry.enabled or behavior.orders.ordered_stack())
			or not behavior.grenades.evade.is_empty()
			or perception.under_fire()):
		return false
	if task.primitive == &"entry":
		return behavior._entry.state.phase == "approach"
	if task.primitive == &"throw":
		return behavior._combat.throw.stage == "walk"
	return (task.primitive in [&"move", &"engage", &"interact", &"defend", &"ambush"]
			and bool(task.params.get("entry_guard", true)))


## Entry: start the entry on the primitive's first tick, then run its phases (the watch stage shoots
## a threat in sight in every one of them). Done (the room clear, or the entry given up) →
## re-decide.
func apply(delta: float) -> void:
	var task: RunningLeaf = behavior.task
	behavior._entry.state.gaze_held = not behavior._watch.threat.is_empty()
	behavior._entry.state.hostile_in_view = _hostile_in_view()
	if pending and _begin_pending(delta):
		return
	if behavior._entry.state.held_back:
		if _detour_first(delta):
			return
		# The way is clear: the entry begins again, from the claims heard meanwhile (others' held
		# back like its own), and its claim goes out.
		behavior._entry.reset()
		if not behavior._entry.begin(task.params):
			finish()
			return
	if behavior._entry.step(delta):
		finish()
		return
	if behavior.orders.join_over():
		# Its leader's stack went in and cleared the room without it (LD25, D26): it follows again
		# now, not once its entry would have ended. One inside holds the room until its entry ends.
		join_done = true
		task.resolved = true
		task.resolve_reason = "join over"
	if behavior._entry.holding_for_go():
		# Ready in its slot and held for the leader's go (LD13).
		behavior.orders.say_step("in_position")
	if task.held and not behavior._entry.throwing():
		# The stun is away (or the bang given up): the decision held off for it is taken now, from
		# where it stands.
		task.held = false
		task.resolved = true
		task.resolve_reason = "after the bang"


## Begin the pending entry on its first tick, once the doorway's slots are laid (or `ROUTE_WAIT` s
## have gone by), and hold an ordered stack's claim back while its way is read. True when the tick
## ends here: still waiting for the slots, or the entry could not begin (and is finished).
func _begin_pending(delta: float) -> bool:
	var task: RunningLeaf = behavior.task
	if not behavior._entry.laid(task.params) and _route_wait < ROUTE_WAIT:
		# The doorway's slots are laid once the nav map is baked: a stack claims nothing before.
		_route_wait += delta
		behavior._character.movement.move_input = Vector2.ZERO
		return true
	pending = false
	_route_wait = 0.0
	if not behavior._entry.begin(task.params):
		if StackClaim.is_join(task.params):
			# No slot in its leader's stack (a dead end, E20): the join is refused and it follows
			# again (LD24, LD25).
			behavior._perception.orders.end(task.params.get("order_id"), "refused")
		finish()
		return true
	behavior._entry.state.held_back = (resume.is_empty()
			and Orders.ordered_entry(task.params)
			and behavior._entry.state.phase == "approach")
	return false


## An ordered stack's way to its doorway (D4, LD9), read before the member's claim goes out: its
## entry has begun (its slot, its side and the approach's waypoints are worked out) and holds its
## claim back (`Entry.state.held_back`) while the whole walk to the slot, leg by leg as the approach
## walks it (`AgentPerception.walk_route`: out of the room being entered and its doorway's view), is
## read for a threshold into a room not cleared (`threshold_ahead`; the room being entered and the
## doorway it stacks at left out), and, with no other recipient coming to the doorway, a doorway
## view it would cross (E15, `passing_ahead`; not one of the room being entered, which the stack
## clears). The first is gone through by entry first, as a detour (`_begin_detour`): the entry is
## dropped unheard, so no claim was made and none is given up; the order's entry starts afresh once
## the detour is over, and reads the way again. True while it is detouring or waits (at most
## `ROUTE_WAIT` s) for a map round the views to be baked; false when the way is clear and the claim
## is due.
func _detour_first(delta: float) -> bool:
	var perception: Node = behavior._perception
	if not behavior.tuning.entry_guard.enabled or perception.under_fire():
		return false
	var opening: String = behavior._entry.state.opening
	var into: String = behavior._entry.state.into
	var entering := "%s>%s" % [opening, into]
	var path := PackedVector2Array()
	var from := Vector2.INF
	var baking := false
	for p: Vector2 in behavior._entry.approach_points():
		var leg: Dictionary = perception.walk_route(p, entering, from)
		baking = baking or bool(leg["pending"])
		path.append_array(leg["path"])
		from = p
	if baking and _route_wait < ROUTE_WAIT:
		_route_wait += delta
		behavior._character.movement.move_input = Vector2.ZERO
		return true
	var gate := _other_threshold(path, 0, INF)
	if not _recipients_coming():
		var passing: Dictionary = perception.passing_ahead(path, 0, INF)
		if (not passing.is_empty()
				and passing["opening"] != opening
				and str(passing["into"]) != into
				and (gate.is_empty() or float(passing["dist"]) < float(gate["dist"]))
				and float(_guard_off.get(passing["opening"], -1.0)) <= guard_clock
				and not perception.entry_stack(passing["opening"]).claimed()):
			passing["secure"] = true
			gate = passing
	if gate.is_empty():
		return false
	behavior._entry.reset()
	_begin_detour(gate)
	return true


## The threshold into a room not cleared on `path` (from `index`, within `reach` of walking,
## `threshold_ahead`), or {}: not the doorway the entry stacks at, a doorway into the room it
## enters, or one the guard leaves alone for now (`_guard_off`).
func _other_threshold(path: PackedVector2Array, index: int, reach: float) -> Dictionary:
	var gate: Dictionary = behavior._perception.threshold_ahead(path, index, reach)
	if gate.is_empty():
		return gate
	if (gate["opening"] == behavior._entry.state.opening
			or str(gate["into"]) == behavior._entry.state.into
			or float(_guard_off.get(gate["opening"], -1.0)) > guard_clock):
		return {}
	return gate


## Whether the order the pending entry stacks under names another living member: a team is coming to
## the doorway, so nobody leaves the way to it to cover a doorway on the way (E15, as for a stack
## others claim).
func _recipients_coming() -> bool:
	var held: Dictionary = behavior._perception.orders.current()
	if str(held.get("id", "")) != str(behavior.task.params.get("order_id", "")):
		return false
	var character: Node = behavior._character
	return (held.get("to", []) as Array).any(
		func(m): return is_instance_valid(m) and m != character and m.get("is_dead") != true,
	)


## Whether a hostile stands in view for the entry's purposes (E14): the threat holding the NPC's
## eyes is seen now, or was a moment ago (`tuning.watch.lost_gaze` s), and there is a line of fire
## to it from here, so it can be engaged from outside. A hostile remembered from longer ago, or one
## seen but behind a wall or out of range (nothing to engage it with from outside), does not hold an
## entry outside.
func _hostile_in_view() -> bool:
	return (not behavior._watch.threat.is_empty()
			and (bool(behavior._watch.threat["visible"])
					or float(behavior._watch.threat["age"]) <= behavior.tuning.watch.lost_gaze)
			and behavior._combat.has_line_of_fire(behavior._watch.threat))


## The entry is over, or could not start. As the NPC's own order (ENTER) it resolves and the NPC
## re-decides. As a detour (`_begin_detour`) it hands the walk back to the order it paused, which
## carries on from where the entry left the NPC; a doorway whose room is still not cleared (the
## entry did not get to the end) is left alone for `tuning.entry_guard.rearm` s.
func finish() -> void:
	var task: RunningLeaf = behavior.task
	task.held = false
	if resume.is_empty():
		task.primitive = &"hold"
		task.resolved = true
		return
	var entry: RefCounted = behavior._entry
	if entry.state.secured:
		# Secured in passing: not again for a while.
		_guard_off[entry.state.opening] = guard_clock + behavior.tuning.entry_guard.secure_time
	elif not behavior._perception.is_cleared(entry.state.into):
		_guard_off[entry.state.opening] = guard_clock + behavior.tuning.entry_guard.rearm
	_resume_order()


## Hand the walk back to the order a detour paused.
func _resume_order() -> void:
	var task: RunningLeaf = behavior.task
	var r := resume
	resume = {}
	task.primitive = r["primitive"]
	task.params = r["params"]
	task.path = r["path"]
	task.labels = r["labels"]
	task.point = r["point"]
	task.arrived = r["arrived"]
	task.look_around = r["look_around"]
	task.arrive_room = r["arrive_room"]
	behavior.errand.act_armed = r["act_armed"]
	pending = bool(r.get("entry_pending", false))
	# The order's cap runs from here: the entry took the time it took.
	task.commit_timer = behavior.tuning.decision.max_commit_time
	if task.primitive == &"throw":
		# The walk to the throw spot goes on from where the entry left it.
		behavior.grenades.begin_throw_order()


## The entry guard (E9): a walk that is about to cross into a room that is not cleared goes in by
## tactical entry, whatever order it came from (a search or explore, a lead, a closing-in, the way
## to an object or to a throw spot, the front entrance). It reads the walk the nav agent was just
## given rather than the leaf's destination, so a path through an intermediate room, a reposition in
## a fight and the way to a doorway itself are all covered. Exempt: a retreat
## (`tuning.entry_guard.enabled: false` on its node), an NPC under fire (but for a walk into the
## room the shots came from, `fight.into_the_shots`), an entry already running, and anything that is
## not walking.
func guard() -> void:
	var perception: Node = behavior._perception
	if behavior.task.primitive == &"entry":
		_guard_running()
		return
	if not _walk_guarded():
		return
	var walk: Dictionary = behavior._loco.path_ahead()
	if walk.is_empty():
		return
	var gate: Dictionary = perception.threshold_ahead(
		walk["path"], walk["index"], behavior.tuning.entry_guard.reach,
	)
	if not perception.under_fire():
		var passing := _passing_gate(walk, gate)
		if not passing.is_empty():
			gate = passing
	elif gate.is_empty() or not behavior.fight.into_the_shots(str(gate["into"])):
		# Under fire: no time to stack or to secure what it passes, but for a walk into the room the
		# shots came from.
		return
	if gate.is_empty() or float(_guard_off.get(gate["opening"], -1.0)) > guard_clock:
		return
	_begin_detour(gate)


## The entry guard over a running entry: a detour's entry shot at before it crossed is given up (but
## into the shots it stacks), and an ENTER order's own approach is guarded (`_guard_approach`).
func _guard_running() -> void:
	if (not resume.is_empty()
			and not behavior._entry.committed()
			and behavior._perception.under_fire()
			and not behavior.fight.into_the_shots(behavior._entry.state.into)):
		# Shot at before it crossed: no time to stack. (Once crossing it finishes the crossing; into
		# the shots it stacks.)
		_cancel_detour()
	elif resume.is_empty() and not pending and behavior._entry.state.phase == "approach":
		_guard_approach()


## Whether the running primitive (not an entry) is on a walk the entry guard covers this tick: the
## guard on, the NPC stepping, a move, defend or ambush not yet arrived, an engage, an interaction
## or a throw's walk to its throw spot, and not a retreat (`tuning.entry_guard.enabled: false`).
func _walk_guarded() -> bool:
	var task: RunningLeaf = behavior.task
	var perception: Node = behavior._perception
	if (not behavior.tuning.entry_guard.enabled
			or perception == null
			or not behavior.tuning.entry.enabled):
		return false
	match task.primitive:
		&"move", &"defend", &"ambush":
			if task.arrived:
				return false  # Holding at the destination, or covering the room by sight.
		&"engage", &"interact":
			pass
		&"throw":
			if behavior._combat.throw.stage != "walk":
				return false  # Throwing where it stands: no walk to guard.
		_:
			return false
	return not ((behavior._character.movement.move_input as Vector2).length() < 0.1
			or not bool(task.params.get("entry_guard", true)))


## An ENTER order's own walk to its stack (E15): a doorway it goes past on the way (in a corridor,
## not the one it is stacking at) is secured first like any other walk's. The entry pauses (it told
## the stack it gave its claim up and starts again afterwards). Not for a member heading for a stack
## that others have claimed, or that its order names others for: the team goes to its door as one,
## and a member that left it to cover a door on the way would leave the point to go in alone. (An
## ordered stack reads its whole way for both before it claims, `_detour_first`; this catches what
## comes up on the walk.) An ordered stack's walk (`docs/leadership.md` LD9, D4), whatever
## `tuning.entry.enabled` says, also goes into a room that is not cleared on its way by entry first,
## as any walk does (E9), team or none, and its entry starts afresh after it.
func _guard_approach() -> void:
	var perception: Node = behavior._perception
	var ordered := Orders.ordered_entry(behavior.task.params)
	if (not behavior.tuning.entry_guard.enabled
			or not (behavior.tuning.entry.enabled or ordered)
			or (behavior._character.movement.move_input as Vector2).length() < 0.1
			or perception.under_fire()):
		return
	var walk: Dictionary = behavior._loco.path_ahead()
	if walk.is_empty():
		return
	var gate := {}
	if ordered:
		gate = _other_threshold(walk["path"], walk["index"], behavior.tuning.entry_guard.reach)
	var team_coming: bool = (perception.entry_stack(behavior._entry.state.opening).claimed()
			or (ordered and _recipients_coming()))
	var passing := {} if team_coming else _passing_gate(walk, gate)
	if (not passing.is_empty()
			and passing["opening"] != behavior._entry.state.opening
			and str(passing["into"]) != behavior._entry.state.into):
		gate = passing
	if gate.is_empty():
		return
	behavior._entry.abandon()
	_begin_detour(gate)


## The doorway the walk goes past before it reaches `gate` (the doorway it crosses, {} for none), as
## a gate to secure (E15), or {}: one in a room not cleared, nearer along the walk than the
## crossing, that no teammate is working (an ally on its radio is entering it) and that was not just
## secured or given up.
func _passing_gate(walk: Dictionary, gate: Dictionary) -> Dictionary:
	var perception: Node = behavior._perception
	var passing: Dictionary = perception.passing_ahead(
		walk["path"], walk["index"], behavior.tuning.entry_guard.reach,
	)
	if (passing.is_empty()
			or (not gate.is_empty() and float(passing["dist"]) >= float(gate["dist"]))):
		return {}
	if (float(_guard_off.get(passing["opening"], -1.0)) > guard_clock
			or perception.entry_stack(passing["opening"]).claimed()):
		return {}
	passing["secure"] = true
	return passing


## Pause the running order and go through doorway `gate` (`{ opening, into }`) by tactical entry
## first. The order is kept whole in `resume` and comes back when the entry ends (`finish`).
## A new decision replaces it and lets the entry carry on (`set_leaf`), unless it is one the guard
## does not apply to: then the detour is dropped (`drop_detour`). Into a room the NPC suspects (the
## shots' room among them), the entry is a bang one when the stack carries a stun (E17,
## `Entry.begin`).
func _begin_detour(gate: Dictionary) -> void:
	var task: RunningLeaf = behavior.task
	stash_order()
	task.primitive = &"entry"
	task.params = {
		"opening": gate["opening"],
		"into": gate["into"],
		"secure": bool(gate.get("secure", false)),
	}
	pending = true


## Give a detour's entry up (the stack is told) and carry on with the paused order, which walks
## straight through.
func _cancel_detour() -> void:
	var opening := str(behavior.task.params.get("opening", behavior._entry.state.opening))
	_guard_off[opening] = guard_clock + behavior.tuning.entry_guard.rearm
	pending = false
	behavior._entry.abandon()
	_resume_order()


## Keep the running order whole in `resume`, to come back when the entry ends.
func stash_order() -> void:
	var task: RunningLeaf = behavior.task
	resume = {
		"primitive": task.primitive, "params": task.params,
		"path": task.path, "labels": task.labels,
		"point": task.point, "arrived": task.arrived, "look_around": task.look_around,
		"arrive_room": task.arrive_room, "act_armed": behavior.errand.act_armed,
		# An ENTER order that is paused starts afresh when it comes back.
		"entry_pending": task.primitive == &"entry",
	}


## A new decision (or no decision to be had) ends a detour: the paused order is gone, and the
## doorway it was stacking at is left alone for `tuning.entry_guard.rearm` s so a fight that cut the
## entry short does not restart it every decision.
func drop_detour() -> void:
	if resume.is_empty():
		return
	var opening := str(behavior.task.params.get("opening", behavior._entry.state.opening))
	_guard_off[opening] = guard_clock + behavior.tuning.entry_guard.rearm
	resume = {}
