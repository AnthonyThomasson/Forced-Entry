extends RefCounted
## AI BEHAVIOUR sub-domain — the behaviour's gait, its part `gait`: whether the NPC runs
## (`should_run`, a follower's catch-up included) and the posture it takes (`apply_posture`), both a
## manner of carrying out the leaf, judged after the primitive has steered; and how it ran and stood
## last tick, for the read-outs. Built once with its `Behavior`, it holds it (a node, so no
## reference cycle) for the running leaf, the body and the tuning.

## The running leaf's data (the behaviour's `task`).
const RunningLeaf := preload("res://scenes/ai/behavior/running_leaf.gd")

## The behaviour it belongs to.
var behavior: Node
## A follower running to catch up (LD21): set when its follow run starts, it holds through a tick
## with no step (a give-way, a `keep_off` stop, a held walk) and is cleared once the follower is
## within `SquadFollowConfig.caught_up` of its live spot or its walk is over short of it, when a
## gate drops the run (a shot to take, a reload due, its stamina dry) or when the primitive changes.
var catching_up := false
## The character was running last tick (for the status line).
var running := false
## The character's posture last tick (for the status line and overlays).
var posture: StringName = &"stand"
## Seconds before a crouch may be swapped for standing (no flicker).
var _posture_hold := 0.0


func _init(npc_behavior: Node) -> void:
	behavior = npc_behavior


## Take the posture `_wanted_posture` asks for. Standing back up is never delayed (a run, the end of
## a fight); a crouch is held for `tuning.pace.posture_dwell` before it is dropped, so a
## peek-and-duck does not flicker. A change the character refuses (its own pacing, an interaction)
## is simply asked again next tick.
func apply_posture(delta: float) -> void:
	var movement: CharacterMovement = behavior._character.movement
	_posture_hold = maxf(_posture_hold - delta, 0.0)
	var want := _wanted_posture()
	if want == movement.posture() or (want != &"stand" and _posture_hold > 0.0):
		return
	if movement.set_posture(want):
		_posture_hold = behavior.tuning.pace.posture_dwell


## The posture to take this tick: a manner of carrying out the leaf, not something Von chooses, so
## it works with the server down. Only a standing body runs, so anything on the move to a
## destination stands, and so does everything outside a fight. Fighting in place (an engaged NPC in
## position, or one holding / reloading while a hostile is known or shots are landing) it crouches:
## a smaller target, and it hides behind cover as high as a crouch. A member of a frag entry holding
## its slot for the burst crouches too (`Entry.holds_crouched`, LD14).
func _wanted_posture() -> StringName:
	var task: RunningLeaf = behavior.task
	if not behavior.grenades.evade.is_empty():
		return &"crouch" if behavior.grenades.evade_crouches() else &"stand"
	if not behavior.tuning.pace.posture_enabled or behavior._character.movement.run_input:
		return &"stand"
	if task.primitive == &"entry" and behavior._entry.holds_crouched():
		return &"crouch"  # Its slot held for the frag the stack threw into the room (LD14).
	if task.primitive == &"ambush" and task.arrived:
		return &"crouch"  # Waiting at its post, low (LD15).
	var perception: Node = behavior._perception
	var under_fire: bool = perception != null and perception.under_fire()
	if behavior.fight.hostiles.is_empty() and not under_fire:
		return &"stand"
	return &"crouch" if behavior.fight.fights_in_place() else &"stand"


## Whether to sprint this tick, judged after the primitive has steered and the watch stage has
## picked its threat: only while travelling to a destination (a move or engage approach that hasn't
## arrived, a melee closing in; never an ambush, peek, room search, interaction, hold or tactical
## entry — a running character cannot shoot, so an entrant walks with its gun up from the moment it
## heads for the door), when the leaf asks for it (`params.run`) or the NPC is under fire, the
## destination is farther than `tuning.pace.run_min_distance`, and a run can be started (stamina
## `tuning.pace.run_start_fraction`, or already running). It never sprints with a shot to take or an
## empty gun to reload (a running character can do neither), except a retreat
## (`params.run_through_fire`), which is about leaving the line, not trading shots. The Character
## spends the stamina and runs
## dry on its own. A follower runs to catch up once it has fallen `SquadFollowConfig.step` behind
## its spot, whatever the leaf, and keeps on (`catching_up`) until it is back within `caught_up` of
## it, through a tick with no step; the gates still drop that run.
func should_run() -> bool:
	var movement: CharacterMovement = behavior._character.movement
	if catching_up and movement.stamina_fraction() <= 0.0:
		catching_up = false  # Its stamina ran dry on the last frame's run.
	if not behavior.tuning.pace.run_enabled or movement.move_input == Vector2.ZERO:
		return false
	var go := _run_now()
	if behavior.task.primitive == &"follow":
		catching_up = go
	return go


## `should_run`'s judgement on a tick the NPC steps: the primitive's destination, the leaf's ask
## or fire, the distance, a shot or reload due and the stamina.
func _run_now() -> bool:
	if not _travelling():
		return false
	var task: RunningLeaf = behavior.task
	var character: Node = behavior._character
	var squad: Node = behavior.orders.squad
	var dest: Vector2 = behavior.fight.engage_pos if task.primitive == &"melee" else task.point
	var near: float = behavior.tuning.pace.run_min_distance
	var run: bool = task.params.get("run", false)
	var sprinting: bool = character.movement.is_running()
	if task.primitive == &"follow":
		# A follower runs to catch up once it has fallen a place behind its spot, and keeps on
		# until it has caught up: a stop on the way keeps the catch-up, and its next step runs on
		# whatever stamina is left.
		dest = squad.follow_spot(character)
		near = SquadFollowConfig.caught_up if catching_up else SquadFollowConfig.step
		sprinting = catching_up
		run = true
	var perception: Node = behavior._perception
	if not run and not (perception != null and perception.under_fire()):
		return false
	if character.global_position.distance_to(dest) <= near:
		return false
	var threat: Dictionary = behavior._watch.threat
	var combat: RefCounted = behavior._combat
	if not threat.is_empty() and not bool(task.params.get("run_through_fire", false)) \
			and (combat.can_fire_at(threat) or combat.reload_due()):
		# A shot (or the reload an empty gun needs) is on: a running character can do neither, so
		# walk and take it.
		return false
	return (sprinting
			or character.movement.stamina_fraction() >= behavior.tuning.pace.run_start_fraction)


## Whether the running primitive is still travelling to a destination it may run to: a move (not a
## room search) or an engage, defend, ambush or follow not yet arrived, or a melee closing in.
func _travelling() -> bool:
	var task: RunningLeaf = behavior.task
	match task.primitive:
		&"move":
			return not (task.arrived or task.look_around)
		&"engage", &"defend", &"ambush", &"follow":
			return not task.arrived
		&"melee":
			return true
	return false
