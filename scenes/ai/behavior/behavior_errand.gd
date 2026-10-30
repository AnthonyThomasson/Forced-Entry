extends RefCounted
## AI BEHAVIOUR sub-domain — the behaviour's errands, its part `errand`: the walks and uses that are
## not a fight, an entry, a throw or an order (the `move`, `interact` and `hold` primitives, a
## search move's room coverage, `coverage`), what a walk accounts for (`set_up_walk`), where a
## walker looks (`aim_move`), the interaction in progress (`service_interaction`) and their
## read-outs. Built once with its `Behavior`, it holds it (a node, so no reference cycle) for the
## running leaf, the body, the perception and the locomotion.

## The running leaf's data (the behaviour's `task`).
const RunningLeaf := preload("res://scenes/ai/behavior/running_leaf.gd")
## How near (px) a contact out of sight must have been last seen for a walk to check that it is
## still there (`_walk_bodies`).
const WALK_BODY_RANGE := 450.0

## The behaviour it belongs to.
var behavior: Node
## Room coverage by sight for a search move; see search_coverage.gd.
var coverage: RefCounted
## The object to approach + use (interact), else null.
var target_obj: Node
## The interaction id to run on `target_obj`.
var interact_id := ""
## Delays an interaction one frame so facing settles first.
var act_armed := false
## Committed to an active object interaction.
var in_interaction := false
## Seconds left before ending the current interaction.
var interaction_timer := 0.0


func _init(npc_behavior: Node) -> void:
	behavior = npc_behavior


## Where a move, a melee, an interaction or a reload stands ("en route", "closing in to punch", …).
func walk_progress() -> String:
	var task: RunningLeaf = behavior.task
	var running: bool = behavior.gait.running
	match task.primitive:
		&"move":
			return "reached it" if task.arrived else ("running" if running else "en route")
		&"melee":
			return "running in to punch" if running else "closing in to punch"
		&"interact":
			return "using it" if in_interaction else "walking to it"
	return "reloading"


## Read-only: the running search-coverage state, for the search debug overlay. `active` is true only
## while a `look_around` move is actually covering a room (arrived, not yet resolved); `points` are
## all the room's sample points, `unseen` the ones still to be seen, `target` the one being looked
## at now.
func debug_coverage() -> Dictionary:
	var task: RunningLeaf = behavior.task
	var out: Dictionary = coverage.debug()
	out["active"] = (
		(task.primitive == &"move" and task.look_around and task.arrived and not task.resolved)
		or (task.primitive == &"entry" and behavior._entry.state.phase == "clear")
	)
	return out


## The characters a walk accounts for: every contact the NPC knows of, less one out of sight whose
## last-known spot, near enough to matter (`WALK_BODY_RANGE`), it can see now with nobody on it (it
## has moved on unseen).
func _walk_bodies() -> Array:
	var here: Vector2 = behavior._character.global_position
	var spots: Array = []
	for c in behavior.fight.known:
		if not c["visible"] and (c["pos"] as Vector2).distance_to(here) <= WALK_BODY_RANGE:
			spots.append(c["pos"])
	if spots.is_empty():
		return behavior.fight.known
	var empty: Array = behavior._perception.sight.visible_points(spots)
	if empty.is_empty():
		return behavior.fight.known
	return behavior.fight.known.filter(func(c): return c["visible"] or not empty.has(c["pos"]))


## Advance an active interaction: hold it until its dwell runs out, the character leaves it, or the
## controller forces a rethink (`force`); then end it and flag the task resolved. Returns true while
## the NPC is STILL interacting (the controller should do nothing more this tick).
func service_interaction(delta: float, force: bool) -> bool:
	var character: Node = behavior._character
	if not in_interaction:
		return false
	interaction_timer -= delta
	if (force
			or not character.use.is_busy()
			or interaction_timer <= 0.0
			or not behavior.grenades.evade.is_empty()):
		character.use.end_interaction()
		in_interaction = false
		# Pick the next step right away rather than wait out the cadence.
		behavior.task.resolved = true
		return false
	return true


## The investigation lead the running move has reached (its `lead` param), or "" — so the controller
## can tell perception it was checked.
func reached_lead() -> String:
	var task: RunningLeaf = behavior.task
	return str(task.params.get("lead", "")) if task.primitive == &"move" and task.arrived else ""


## Tell the locomotion what this tick's walk accounts for: the bodies it knows of, the one a melee
## closes on, and whether it keeps out of the doorway views (and the room an entry goes into, or the
## one a held stack is to enter).
func set_up_walk(delta: float) -> void:
	var task: RunningLeaf = behavior.task
	var loco: Node = behavior._loco
	loco.stall.sample(delta)  # Observation only (stuck overlay); never alters the tick.
	# Every walk accounts for the characters the NPC knows of, and only those.
	loco.crowd.bodies = _walk_bodies()
	# A melee closes on its target: no walk round it.
	loco.crowd.ignore_id = behavior.fight.engage_id if task.primitive == &"melee" else 0
	behavior._perception.views.ordered = behavior.orders.ordered_stack()
	loco.doors.avoid_doors = behavior.entries.keeps_out_of_views()
	loco.doors.keep_out = _held_entry()
	var entry_state: RefCounted = behavior._entry.state
	loco.doors.avoid_entering = ("%s>%s" % [entry_state.opening, entry_state.into]
			if task.primitive == &"entry" and entry_state.opening != ""
			else "")


## The held stack whose room the walk keeps out of (`"<opening id>><room key>"`, "" for none): a
## member of a stack held for its leader's go fights on the stack's side of the doorway (D31, the
## room its confinement keeps it out of, `keep_out`), so a walk its fight takes (an engage's
## reposition, a retreat, under fire too) whose plain way goes into that room goes round it
## (`Locomotion`'s `doors.keep_out`), however long the way round (D4). Not an evade.
func _held_entry() -> String:
	var room: String = behavior._perception.confinement.keep_out
	if room == "" or not behavior.in_combat() or not behavior.grenades.evade.is_empty():
		return ""
	var opening := String(behavior._perception.orders.current().get("opening", ""))
	return "%s>%s" % [opening, room] if opening != "" else ""


## Move: walk to the destination (or into the destination room), aiming as the leaf asks (a threat
## in sight takes the eyes and the gun in the watch stage). A `look_around` move (search / explore)
## walks all the way to the interior point and, on arrival, COVERS the room by sight — turning and
## relocating until it has seen (near-)every sampled point (see `search_coverage.gd`) — before
## flagging the task resolved; any other move stops on arrival and flags resolved at once.
func apply_move(delta: float) -> void:
	var task: RunningLeaf = behavior.task
	var character: Node = behavior._character
	var loco: Node = behavior._loco
	if not task.arrived:
		_note_move_arrival()
	if not task.arrived:
		loco.move_to(task.point)
	elif not task.look_around:
		# Arrived: stand. (The last steering input would walk it on into the wall ahead.)
		character.movement.move_input = Vector2.ZERO
	else:
		if coverage.step(delta):  # Look around until the room is covered by sight.
			task.look_around = false
			task.resolved = true
			var confinement: RefCounted = behavior._perception.confinement
			var covered: String = confinement.room_at(character.global_position)
			if covered != "":
				# Seen all of it: cleared, as by an entry.
				behavior._perception.entry.mark_cleared(covered)
		return
	aim_move()


## Whether a move still on its way has arrived (in its `arrive_room`, or at its point): a
## `look_around` move then begins covering the room, any other is resolved.
func _note_move_arrival() -> void:
	var task: RunningLeaf = behavior.task
	var loco: Node = behavior._loco
	if task.arrive_room != "" and not task.look_around:
		var here: Vector2 = behavior._character.global_position
		task.arrived = behavior._perception.confinement.room_at(here) == task.arrive_room
	if not task.arrived:
		task.arrived = loco.reached(task.point)
	if task.arrived:
		if task.look_around:
			coverage.begin()
		else:
			task.resolved = true


## Where a moving NPC looks when no threat has its eyes (`Watch.apply` puts one there): its target,
## the nearest known threat, the destination, or (default) a few paces down its path, so its view
## cone sweeps the way it is going.
func aim_move() -> void:
	var task: RunningLeaf = behavior.task
	var character: Node = behavior._character
	match task.params.get("aim", &"travel"):
		&"target":
			if behavior.fight.engage_id != 0:
				character.movement.aim_point = behavior.fight.engage_pos
				return
		&"threat":
			if not behavior.fight.hostiles.is_empty():
				character.movement.aim_point = behavior.fight.hostiles[0]["pos"]
				return
		&"point":
			character.movement.aim_point = task.point
			return
	var ahead: Vector2 = behavior._watch.travel_point()
	if ahead != Vector2.INF:
		character.movement.aim_point = ahead
	elif character.movement.move_input != Vector2.ZERO:
		var walk: Vector2 = character.movement.move_input
		character.movement.aim_point = character.global_position + walk * 100.0


## Interact: walk to the chosen object facing it (or a known hostile, to keep eyes on them); once
## its action is in reach, face it, run it and hold the interaction. Ends (and re-decides) if the
## object is gone or the action can't start.
func apply_interact() -> void:
	var task: RunningLeaf = behavior.task
	var character: Node = behavior._character
	if target_obj == null or not is_instance_valid(target_obj):
		task.primitive = &"hold"
		task.resolved = true
		character.movement.move_input = Vector2.ZERO
		return
	if not interaction_in_reach():
		character.movement.aim_point = (behavior.fight.hostiles[0]["pos"]
				if not behavior.fight.hostiles.is_empty()
				else target_obj.global_position)
		behavior._loco.move_to(target_obj.global_position)
		return
	character.movement.move_input = Vector2.ZERO
	# face the object to perform the interaction
	character.movement.aim_point = target_obj.global_position
	if not act_armed:
		act_armed = true  # Let facing settle before acting.
		return
	if character.use.interact_with(target_obj, interact_id):
		in_interaction = true
		interaction_timer = behavior.tuning.decision.interaction_dwell
	else:
		task.primitive = &"hold"
		task.resolved = true


## Hold: stand still. Where it looks is the watch stage's (`Watch.apply`): a threat if one has its
## eyes, else the doors. An empty gun is reloaded meanwhile, so a steady NPC (no decision to be had)
## isn't left unarmed.
func apply_hold() -> void:
	behavior._character.movement.move_input = Vector2.ZERO
	behavior._combat.reload_if_dry()


## Whether the chosen interaction on `target_obj` is currently reachable (lets the approach stop
## and the action begin).
func interaction_in_reach() -> bool:
	for entry in behavior._character.use.interactions_in_reach():
		if entry["object"] != target_obj:
			continue
		for spec in entry["specs"]:
			if spec.get("id", "") == interact_id:
				return true
	return false
