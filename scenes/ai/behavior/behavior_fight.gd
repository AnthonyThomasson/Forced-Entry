extends RefCounted
## AI BEHAVIOUR sub-domain — the behaviour's fight, its part `fight`: the hostiles it knows this
## tick and the contact it fights (its body, its last-known spot, whether it was last seen inside),
## the `engage`, `melee` and `reload` primitives, whether the fight is held where it is, and the
## combat read-out (`debug_combat`). Built once with its `Behavior`, it holds it (a node, so no
## reference cycle) for the running leaf, the body, the perception, the locomotion and `Combat`,
## which does the shooting.

## The running leaf's data (the behaviour's `task`).
const RunningLeaf := preload("res://scenes/ai/behavior/running_leaf.gd")

## The behaviour it belongs to.
var behavior: Node
## Known hostile contacts this tick (nearest first), from perception.
var hostiles: Array = []
## Every contact the perception handed in this tick (`update_known`), hostile or not.
var known: Array = []
## Instance id of the contact being fought (0 = none).
var engage_id := 0
## That contact's body (excluded from line-of-fire rays).
var engage_node: Node2D
## That contact's last-KNOWN position (from memory).
var engage_pos := Vector2.ZERO
## Whether that contact was last seen inside the house.
var engage_inside := false
## The contact's last-known spot is where its confinement does not let it act (outside the house,
## the room it defends or its leash): it holds its ground instead of chasing there.
var hold_ground := false
## The character was reloading last tick (for the status line and overlay).
var reloading := false
## A `reload` leaf has seen its reload begin, so it ends when the reload does.
var reload_started := false


func _init(npc_behavior: Node) -> void:
	behavior = npc_behavior


## Where an engage stands: on its way into position, waiting in ambush, or peeking and ducking.
func engage_progress() -> String:
	var task: RunningLeaf = behavior.task
	if not task.arrived:
		return "running into position" if behavior.gait.running else "moving into position"
	if task.params.get("style", &"peek_cover") == &"ambush":
		return "in ambush, waiting for a shot"
	return "in position, %s" % ("ducking behind cover"
			if behavior._combat.phase == "cover"
			else "looking for a shot")


## Read-only: the running combat / movement / interaction state as world-space data (Vector2s, not
## the JSON-safe digest), for the combat, territory and targets debug overlays. The NPC's body gives
## its aim point and the fire-line query. A pure read — the line query only casts a ray.
func debug_combat() -> Dictionary:
	var task: RunningLeaf = behavior.task
	var character: Node = behavior._character
	var tuning: NpcTuning = behavior.tuning
	var combat: RefCounted = behavior._combat
	var engaged := engage_id != 0
	var in_range := false
	var fire_clear := false
	if engaged and character != null:
		in_range = character.global_position.distance_to(engage_pos) <= tuning.combat.shoot_range
		fire_clear = in_range and behavior._perception.has_line_to(engage_node, engage_pos)
	return {
		"primitive": task.primitive,
		"style": task.params.get("style", &"peek_cover") if task.primitive == &"engage" else &"",
		"engaged": engaged,
		"engage_pos": engage_pos,
		"engage_inside": engage_inside,
		"hold_ground": hold_ground,
		"in_range": in_range,
		"fire_clear": fire_clear,
		"shoot_range": tuning.combat.shoot_range,
		"punch_range": tuning.combat.punch_range,
		"combat_phase": combat.phase if task.primitive in [&"engage", &"melee"] else "",
		"cover_timer": combat.cover_timer,
		"cover_time": tuning.combat.cover_time,
		"fire_timer": combat.fire_timer,
		"fire_cooldown": tuning.combat.fire_cooldown,
		"combat_dest": combat.dest
			if task.primitive == &"engage" and task.arrived and combat.dest != Vector2.ZERO
			else null,
		"aim_point": character.movement.aim_point if character != null else Vector2.ZERO,
		"reloading": reloading,
		"requested_point": task.params["point"] if task.params.has("point") else null,
		"point": (task.point as Variant) if task.params.has("point") else null,
		"arrived": task.arrived,
		"arrive_room": task.arrive_room,
		"object_pos": _object_pos(),
		"in_interaction": behavior.errand.in_interaction,
		"interaction_timer": behavior.errand.interaction_timer,
		"interaction_dwell": tuning.decision.interaction_dwell,
		"watch_pos": hostiles[0]["pos"]
			if task.primitive == &"hold" and not hostiles.is_empty()
			else null,
		"reachable": behavior._loco.debug_state().get("reachable", true),
		"timers": { "commit": task.commit_timer, "tactic": task.tactic_timer },
	}


## Where the object the running interaction walks to stands, for `debug_combat` (null: no
## interaction, or its object is gone).
func _object_pos() -> Variant:
	var obj: Variant = behavior.errand.target_obj
	if behavior.task.primitive == &"interact" and is_instance_valid(obj) and obj is Node2D:
		return (obj as Node2D).global_position
	return null


## Whether a walk into room `into` is a walk into the shots (E9): the NPC was shot at from that
## room, whether it sees the shooter or not. Under fire it still goes in by entry, not straight
## through the doorway.
func into_the_shots(into: String) -> bool:
	return into != "" and behavior._perception.hearing.shots_from_room(into)


## Fight known contact `id`: capture its body and last-known position (no-op when it isn't known).
func engage(id: int) -> void:
	for c in hostiles:
		if c["id"] == id:
			engage_id = id
			engage_node = c["node"]
			engage_pos = c["pos"]
			engage_inside = c.get("inside", false)
			return


## Whether the running leaf is pointless without its target (a fight, or a move aimed at it).
func needs_target() -> bool:
	var task: RunningLeaf = behavior.task
	return (task.primitive in [&"engage", &"melee"]
			or (task.primitive == &"move" and task.params.get("aim") == &"target"))


## `wants_decision` for an engage or a melee: an engage still moving into position holds until its
## safety cap; in position (and a melee) it re-asks its tactic every
## `tuning.decision.tactic_interval` or when the engagement lapses.
func wants_decision() -> bool:
	var task: RunningLeaf = behavior.task
	if task.primitive == &"engage" and not task.arrived:
		return task.commit_timer <= 0.0
	return task.tactic_timer <= 0.0 or not behavior._perception.engaged_fresh()


## The gun ran dry mid-fight: the task is resolved, so the controller re-decides (the empty gun is
## in the snapshot now).
func on_dry() -> void:
	behavior.task.resolved = true


## Whether the running primitive fights where it stands (an engage or a defend in position, a hold,
## a reload), which crouches in a fight; anything else is on its way somewhere, standing.
func fights_in_place() -> bool:
	var task: RunningLeaf = behavior.task
	match task.primitive:
		&"engage", &"defend":
			return task.arrived
		&"hold", &"reload":
			return true
	return false


## Engage: walk to the chosen spot (shooting on the way when a line opens), then fight from it —
## peek-and-cover, or an ambush that holds the covered spot and fires the moment a line opens. Its
## confinement keeps where it fights (`hold_ground` against a contact where it may not act).
func apply_engage(delta: float) -> void:
	var task: RunningLeaf = behavior.task
	var combat: RefCounted = behavior._combat
	var loco: Node = behavior._loco
	if engage_id == 0:
		behavior.errand.apply_hold()
		return
	# Aim at where we last saw them, not their true position.
	behavior._character.movement.aim_point = engage_pos
	hold_ground = _keeps_in(engage_pos)
	if not task.arrived:
		task.arrived = loco.reached(task.point)
		if not task.arrived:
			loco.move_to(task.point)
			return
		# In position: the tactic gets its full run from here.
		task.tactic_timer = behavior.tuning.decision.tactic_interval
		behavior._perception.note_engaged()
	if task.params.get("style", &"peek_cover") == &"ambush":
		combat.ambush(engage_node, engage_pos)
		return
	combat.peek_cover(delta, engage_node, engage_pos)


## Melee: close to punch range and swing on the fire cooldown (no cover cycle for fists). While
## holding ground it won't chase a contact where its confinement does not let it act — it only
## swings if one is already in reach.
func apply_melee() -> void:
	if engage_id == 0:
		behavior.errand.apply_hold()
		return
	behavior._character.movement.aim_point = engage_pos
	hold_ground = _keeps_in(engage_pos)
	behavior._combat.melee(engage_pos)


## Whether the fight is held where it is against a contact at `pos`: its confinement does not let
## it act there.
func _keeps_in(pos: Vector2) -> bool:
	return not behavior._perception.confinement.allows(pos)


## Reload: stand and swap magazines, its eyes where the watch stage puts them (a threat, else the
## doors); when the reload ends (or can't start) the task is resolved and the NPC re-decides. A
## reload refused while the previous leaf's run is still winding down is retried the next tick.
func apply_reload() -> void:
	var task: RunningLeaf = behavior.task
	var character: Node = behavior._character
	character.movement.move_input = Vector2.ZERO
	if character.ammo.is_reloading():
		reload_started = true
		return
	if not reload_started:
		var gun: int = character.inventory.gun_slot()
		if gun >= 0:
			character.inventory.select_slot(gun)
		character.ammo.reload()
		if character.ammo.is_reloading():
			reload_started = true
			return
		if character.movement.is_running():
			return
	task.primitive = &"hold"
	task.resolved = true
