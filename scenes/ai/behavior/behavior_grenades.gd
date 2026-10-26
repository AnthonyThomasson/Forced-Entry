extends RefCounted
## AI BEHAVIOUR sub-domain — the behaviour's grenades, its part `grenades`: the `throw` primitive
## (the GRENADE tactic, `docs/grenades.md` G17: the walk to the throw spot, the throw, its radio
## call, the wait for the burst) and the evade reflex (G16: the plan to get clear of a live grenade,
## carried out over every primitive), with their read-outs and the blind roll (G15). Built once with
## its `Behavior`, it holds it (a node, so no reference cycle) for the running leaf, the body, the
## perception, the locomotion and `Combat`, whose throw part throws.

## The running leaf's data (the behaviour's `task`).
const RunningLeaf := preload("res://scenes/ai/behavior/running_leaf.gd")
## Seconds past a grenade's fuse that the thrower waits for the burst before it gives up waiting.
const THROW_WAIT_MARGIN := 1.0
## How close (px) an evade walks into its safe spot: the spot is out of the burst's line with only a
## little room to spare either side of it, so a body that stops the agent's usual stride short of it
## can still be in the line (`AgentThrow`).
const EVADE_REACH := 6.0

## The behaviour it belongs to.
var behavior: Node
## The plan to get clear of a live grenade being carried out ({} = none); see `set_evade`.
var evade := {}
## The evade reached its safe spot.
var _evade_arrived := false
## The grenade being thrown (`throw` leaf): &"frag" / &"stun".
var _throw_kind: StringName = &""
## Where it is thrown to.
var _throw_spot := Vector2.ZERO
## Throws to radio since the last `take_throw_calls()`: { kind, point }.
var _throw_calls: Array = []
## Seconds left waiting out the grenade's fuse once it has left the hand (-1: not thrown yet).
var throw_wait := -1.0
## The grenade thrown has been seen in the world (it is its own, always known): the wait ends when
## it is gone.
var _throw_seen := false


func _init(npc_behavior: Node) -> void:
	behavior = npc_behavior


## The hostile a running throw order was offered on (its `target_id`), also while an entry detour
## has paused it, while the perception still holds it as lost (aged out of the contacts, not dead:
## `contacts.lost_hostiles()` drops the dead); 0 for none. The throw is aimed at that hostile's
## last-known spot and keeps it when the contact ages out on the way (G17).
func throw_target() -> int:
	var task: RunningLeaf = behavior.task
	var perception: Node = behavior._perception
	var id := 0
	if task.primitive == &"throw":
		id = int(task.params.get("target_id", 0))
	elif task.primitive == &"entry" and behavior.entries.resume.get("primitive") == &"throw":
		id = int((behavior.entries.resume["params"] as Dictionary).get("target_id", 0))
	if (id == 0
			or perception == null
			or not perception.contacts.lost_hostiles().any(func(c): return c["id"] == id)):
		return 0
	return id


## Where a throw stands: walking to its throw spot, throwing, or waiting for the grenade to go off.
func throw_progress() -> String:
	if behavior._combat.throw.stage == "walk":
		return "walking to the throw spot"
	return "throwing it" if throw_wait < 0.0 else "waiting for it to go off"


## Start the throw order in `task.params` afresh: with a throw spot (`walk`), from the walk to it (a
## throw resumed after a detour's entry, whose bang may have used the throwing hands, starts here
## too).
func begin_throw_order() -> void:
	var task: RunningLeaf = behavior.task
	_throw_kind = task.params.get("kind", &"")
	_throw_spot = task.params.get("point", Vector2.ZERO)
	_throw_seen = false
	throw_wait = -1.0
	var from: Vector2 = (task.params.get("from", Vector2.INF)
			if task.params.get("walk", false)
			else Vector2.INF)
	behavior._combat.throw.begin(
		int(task.params.get("slot", -1)),
		_throw_spot,
		behavior._perception.grenades.reach(_throw_kind),
		Vector2.INF if from == Vector2.INF else behavior._loco.reachable(from),
	)


## A throw order not yet in its wind-up whose target the NPC no longer knows of at all, neither as a
## contact nor as lost (it died, or was forgotten): there is nobody left on its spot, so the throw
## ends and the NPC re-decides (G17).
func throw_target_gone() -> bool:
	var task: RunningLeaf = behavior.task
	if task.primitive != &"throw" or behavior._combat.throw.stage in ["windup", "away"]:
		return false
	var id := int(task.params.get("target_id", 0))
	return (id != 0
			and not behavior.fight.hostiles.any(func(c): return c["id"] == id)
			and throw_target() == 0)


## Throw (docs/grenades.md G17): with a throw spot (`params.walk`), walk there first, the gun in
## hand and the watch stage on a threat; then take the grenade in hand, aim at the spot and throw it
## (`Combat`'s `throw.step`), radio it as it leaves the hand, then stand with the gun back in hand
## until the grenade has gone off. The evade reflex carries the thrower off if the burst reaches it
## (it replaces this order); one the burst does not reach has nothing more to do. Then the NPC
## re-decides. A throw that cannot be made (the lob is blocked now, none left, the hand never free)
## is given up at once and the NPC re-decides. A thrower that has drifted a few px out of range
## since the spot was offered closes in on it (`Combat`'s `throw.step`) instead; once the wind-up
## has begun the throw is committed, standing where it is.
func apply_throw(delta: float) -> void:
	var character: Node = behavior._character
	var perception: Node = behavior._perception
	var combat: RefCounted = behavior._combat
	if combat.throw.stage != "away":
		var blocked: bool = (combat.throw.stage == "aim"
				and not perception.grenades.throw_clear(character.global_position, _throw_spot))
		if blocked or combat.throw.step(delta) == &"failed":
			end_throw()
		return
	character.movement.move_input = Vector2.ZERO
	if throw_wait < 0.0:
		end_throw()
		return
	throw_wait -= delta
	var live: bool = perception.grenades.known().any(func(g): return g["source"] == &"own")
	_throw_seen = _throw_seen or live
	if (_throw_seen and not live) or throw_wait <= 0.0:
		end_throw()


## Called every tick before the evade reflex is handed its plan: whether the grenade being thrown
## has left the hand (the end of the wind-up). Then it is radioed, and the wait for the burst
## begins. This has to come first: a grenade just thrown is a live one the thrower may be inside the
## zone of, and the evade replaces the throw order the same tick. A frag entry's thrower (LD14)
## radios its frag the same way, the tick after it left the hand (`Entry.take_thrown`).
func poll_throw() -> void:
	var task: RunningLeaf = behavior.task
	if task.primitive == &"throw" and behavior._combat.throw.released():
		_throw_calls.append({ "kind": _throw_kind, "point": _throw_spot })
		throw_wait = behavior._perception.grenades.fuse(_throw_kind) + THROW_WAIT_MARGIN
	elif task.primitive == &"entry":
		var thrown: Dictionary = behavior._entry.take_thrown()
		if not thrown.is_empty():
			_throw_calls.append(thrown)  # A frag entry's frag (LD14), radioed as any thrown frag.


## The throw is over (the burst, or it could not be made): the NPC re-decides.
func end_throw() -> void:
	var task: RunningLeaf = behavior.task
	behavior._combat.throw.end()
	task.primitive = &"hold"
	throw_wait = -1.0
	task.resolved = true


## The throws to radio since the last call, `{ kind, point }`: the controller posts each as a
## `frag_out` / `bang_out` callout.
func take_throw_calls() -> Array:
	var out := _throw_calls
	_throw_calls = []
	return out


## Read-only: the throw the NPC is about to make, `{ from, to, kind, radius }` (empty once it has
## left the hand, or when the NPC is not throwing), for the grenade overlay.
func throw_plan() -> Dictionary:
	var task: RunningLeaf = behavior.task
	var character: Node = behavior._character
	var combat: RefCounted = behavior._combat
	if task.primitive != &"throw" or combat.throw.stage == "away":
		return {}
	var from: Vector2 = (task.params.get("from", character.global_position)
			if combat.throw.stage == "walk"
			else character.global_position)
	return {
		"from": from,
		"to": _throw_spot,
		"kind": _throw_kind,
		"radius": float(task.params.get("radius", 0.0)),
	}


## Whether the NPC is running from, or holding out of the way of, a live grenade.
func evading() -> bool:
	return not evade.is_empty()


## The safe spot the evade runs to (`Vector2.INF` when none: not evading, or no spot to reach in
## time).
func evade_spot() -> Vector2:
	return evade.get("spot", Vector2.INF)


## Whether the NPC fires blind while this blinding lasts (`docs/grenades.md` G15): the controller's
## roll, handed in the tick it goes blind. False: it holds its fire (no gun round, no burst carried
## on) until it can see.
func set_blind_fire(on: bool) -> void:
	behavior._combat.blind_fire = on


## Take the perception's plan to get clear of a live grenade (`{}`: nothing threatens the NPC),
## every tick. It takes priority over every primitive, committed or not: the order running is given
## up (an entry in progress too, the stack is told) and the NPC runs for the plan's spot. The plan
## stands while the grenade lives, so the NPC holds its spot to the burst; when the plan ends the
## NPC re-decides. One wait: the NPC's own grenade in the wind-up cannot be called back and leaves
## the hand at most a wind-up (0.3 s) later, toward where it is aimed; turning away for the evade
## meanwhile would throw it the wrong way. The evade starts the tick it leaves the hand
## (`poll_throw` runs first).
func set_evade(plan: Dictionary) -> void:
	var task: RunningLeaf = behavior.task
	if plan.is_empty():
		if not evade.is_empty():
			evade = {}
			task.resolved = true
		return
	if evade.is_empty() and task.primitive == &"throw" and behavior._combat.throw.stage == "windup":
		# Its own grenade is about to leave the hand, toward the spot: thrown first, then the run.
		return
	if evade.is_empty() and task.primitive == &"entry" and behavior._entry.expects_burst(plan):
		# The stun (or frag, its slot out of the zone) a bang entry threw into its room: the stack
		# holds turned away from the door for it already.
		return
	if evade.is_empty():
		behavior.entries.drop_detour()
		behavior.entries.pending = false
		behavior._entry.abandon()
		_evade_arrived = false
		task.primitive = &"hold"
		task.params = {}
		task.path = ["evade"]
		task.labels = ["EVADE", "a live %s grenade" % plan.get("kind", "")]
		task.leaf_ms = GameClock.msec()
		behavior.errand.target_obj = null
	elif (plan["spot"] as Vector2) != (evade["spot"] as Vector2):
		_evade_arrived = false  # A new spot (the grenade moved): run to that one.
	evade = plan


## Whether the evade crouches the NPC: it is behind cover that shields a crouched body only, or it
## is caught in the open by a frag with no way out (a smaller target, at least).
func evade_crouches() -> bool:
	if evade_spot() == Vector2.INF:
		return evade.get("kind") == &"frag"
	return _evade_arrived and bool(evade.get("crouch", false))


## Carry the evade out: run to the spot (its back to the grenade, looking away from it all the way),
## then hold it, crouched when the spot is cover. With no spot to reach in time it stays and turns
## its back (a stun's flash then blinds it for the back-turned share only).
func apply_evade(delta: float) -> void:
	var character: Node = behavior._character
	var loco: Node = behavior._loco
	if character.use.is_busy():
		# Up off the chair: a grenade outranks what it was doing, whoever started it.
		character.use.end_interaction()
		behavior.errand.in_interaction = false
	behavior._watch.threat = {}
	behavior._watch.gaze = "evade"
	var spot: Vector2 = evade_spot()
	var here: Vector2 = character.global_position
	var away: Vector2 = here - (evade["point"] as Vector2)
	away = away.normalized() if away.length() > 1.0 else -(character.facing as Vector2)
	var running := false
	if spot != Vector2.INF:
		if not _evade_arrived:
			_evade_arrived = loco.reached(spot, EVADE_REACH)
		if not _evade_arrived:
			loco.move_to(spot, EVADE_REACH)
			running = _evade_runs()
	if spot == Vector2.INF or _evade_arrived:
		character.movement.move_input = Vector2.ZERO
	# Its back to the burst all the way, running or holding: a flash blinds the face.
	character.movement.aim_point = here + away * 100.0
	character.movement.run_input = running
	behavior.entries.guard_clock += delta
	behavior.gait.apply_posture(delta)
	behavior.gait.running = character.movement.is_running()
	behavior.gait.posture = character.movement.posture()
	behavior.fight.reloading = character.ammo.is_reloading()


## Whether the evade runs to its spot: running is on and a run can go on or start (stamina
## `tuning.pace.run_start_fraction`).
func _evade_runs() -> bool:
	var movement: CharacterMovement = behavior._character.movement
	return (behavior.tuning.pace.run_enabled
			and (movement.is_running()
					or movement.stamina_fraction() >= behavior.tuning.pace.run_start_fraction))
