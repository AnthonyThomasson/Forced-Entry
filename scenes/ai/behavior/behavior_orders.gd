extends RefCounted
## AI BEHAVIOUR sub-domain — the behaviour's orders, its part `orders` (`docs/leadership.md`): the
## squad, the `defend`, `ambush` and `follow` primitives, the order steps it radios, the walk an
## order replaces (`await_next`), an ordered stack and a join, and their read-outs. Built once with
## its `Behavior`, it holds it (a node, so no reference cycle) for the running leaf, the body, the
## perception, the locomotion and `Combat`.

## The running leaf's data (the behaviour's `task`).
const RunningLeaf := preload("res://scenes/ai/behavior/running_leaf.gd")
## The entry claim's wire format (whether an entry leaf is a join).
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
## How close (px) a defender walks into its defend spot.
const DEFEND_REACH := 8.0
## How far (px) a defender at its post may be pushed off its defend spot before it walks back.
const DEFEND_DRIFT := 24.0

## The behaviour it belongs to.
var behavior: Node
## The NPC's squad (`ai/team/squad.gd`), null without one: where a follower keeps to.
var squad: Node = null
## Where a follower's walk is going: its follow spot as last re-aimed (`Vector2.INF`: not yet).
var follow_to := Vector2.INF
## When (game s, `GameClock`) the follower last came to a stop at its spot.
var _follow_stood := 0.0
## Progress on the order being carried out, to radio since the last `take_steps()`: { order_id,
## step }.
var _steps: Array = []
## The last step said of an order (`{ id, step }`), so a step is said once until the next differs.
var _said := {}
## An order was just taken and its decision has not landed: a walk it replaces stops
## (`await_next`).
var awaiting := false


func _init(npc_behavior: Node) -> void:
	behavior = npc_behavior


## Where a defend, an ambush or a follow stands: on its way, or at its post or its spot.
func post_progress() -> String:
	var task: RunningLeaf = behavior.task
	match task.primitive:
		&"defend":
			return "holding the room" if task.arrived else "on the way to its post"
		&"ambush":
			return "waiting in ambush" if task.arrived else "on the way to its post"
	return "by its leader" if task.arrived else "keeping up with its leader"


## The order leaf the NPC is carrying out (a walk that began at the ORDER node, `docs/leadership.md`
## LD6), as `{ path, primitive, params, paused }` (JSON-safe; `paused` while an entry detour of the
## entry guard holds it, its primitive and params then the paused order's, not the detour's), or {}
## when it carries out no order. `debug_state()`'s own `primitive` and `params` are always the
## running ones.
func order_leaf() -> Dictionary:
	var task: RunningLeaf = behavior.task
	if task.path.is_empty() or str(task.path[0]) != "order":
		return {}
	var paused: bool = task.primitive == &"entry" and not behavior.entries.resume.is_empty()
	return {
		"path": behavior.current_act(),
		"primitive": String(behavior.entries.resume["primitive"] if paused else task.primitive),
		"params": behavior._json_safe(behavior.entries.resume["params"] if paused else task.params),
		"paused": paused,
	}


## Whether `leaf` is the ordered stack the NPC is already carrying out (the same `order_id`), its
## entry running or paused behind a detour of the entry guard (`docs/leadership.md` LD9).
func same(leaf: Dictionary) -> bool:
	var task: RunningLeaf = behavior.task
	var id = (leaf.get("params", {}) as Dictionary).get("order_id")
	if id == null or leaf.get("primitive") != &"entry":
		return false
	var running: Dictionary = (behavior.entries.resume
			if not behavior.entries.resume.is_empty()
			else { "primitive": task.primitive, "params": task.params })
	if (running["primitive"] != &"entry"
			or str((running["params"] as Dictionary).get("order_id", "")) != str(id)):
		return false
	return (not behavior.entries.resume.is_empty()
			or behavior.entries.pending
			or not behavior._entry.state.phase in ["", "done"])


## Whether the NPC is on an ordered stack's way to its door (`docs/leadership.md` LD9): running the
## entry an order gave it, or a detour of the entry guard paused in front of one. Its walk is
## guarded whatever `tuning.entry.enabled` says (D4).
func ordered_stack() -> bool:
	var task: RunningLeaf = behavior.task
	if task.primitive == &"entry" and ordered_entry(task.params):
		return true
	return (not behavior.entries.resume.is_empty()
			and behavior.entries.resume["primitive"] == &"entry"
			and ordered_entry(behavior.entries.resume["params"]))


## Whether the running entry is a join (LD24) whose order has ended (done: the room cleared by the
## rest of the stack) while the member is still on its way to the stack or in it, where its entry
## would never end on its own (LD25, D26): once per leaf.
func join_over() -> bool:
	return (StackClaim.is_join(behavior.task.params)
			and not behavior.entries.join_done
			and not _live()
			and behavior._entry.state.phase in ["approach", "stack"])


## Whether an entry leaf's `params` are an ordered stack's, which goes in the order's way (LD9): an
## order's that is no join (a join is the member's own entry joining its leader's stack, LD24).
static func ordered_entry(params: Dictionary) -> bool:
	return params.has("order_id") and not StackClaim.is_join(params)


## `wants_decision` for a defend or an ambush, held at its post as long as its order stands.
func post_wants_decision() -> bool:
	var task: RunningLeaf = behavior.task
	if task.primitive == &"ambush":
		# It holds its post as long as the order stands; first contact ends the order (D18), and
		# the NPC then fights on its own.
		return not _live() or (not task.arrived and task.commit_timer <= 0.0)
	# On the way, the walk's safety cap; at its post it holds as long as the order stands, until a
	# fight it began from there (its shots keep it engaged) is the decision's to weigh, in the room
	# (LD8).
	if not task.arrived:
		return task.commit_timer <= 0.0
	return behavior._perception.engaged_fresh()


## An order was taken (`on`, the frame it arrives: `docs/leadership.md` LD5) or the decision made
## knowing it has landed (`set_leaf` and `fallback` clear it too): until then a walk the order
## replaces stops (the behaviour's `_walking`), as an arrived move stands, while a fight goes on (a
## move chosen under COMBAT included); the watch stage still looks and shoots. A crossing or a
## bang's throw (`committed()`) is not stopped in the doorway.
func await_next(on: bool) -> void:
	awaiting = on


## Defend (LD8): walk to the defend spot (a guarded walk where the entry guard applies, as any
## walk), then hold it, still; the watch stage keeps the gun on its doorway, or turns it among the
## room's doorways, and on a threat in sight. Pushed off the spot, it walks back. It says
## `in_position` on the radio once there. An empty gun is reloaded meanwhile, as in a hold. An
## ambush (LD15) is the same walk and hold at its post, crouched, its gun on the threshold.
func apply_defend() -> void:
	var task: RunningLeaf = behavior.task
	var character: Node = behavior._character
	var loco: Node = behavior._loco
	if task.arrived and character.global_position.distance_to(task.point) > DEFEND_DRIFT:
		task.arrived = false
	if not task.arrived:
		task.arrived = loco.reached(task.point, DEFEND_REACH)
		if task.arrived:
			say_step("in_position")
	if not task.arrived:
		loco.move_to(task.point, DEFEND_REACH)
		behavior.errand.aim_move()
		return
	character.movement.move_input = Vector2.ZERO
	behavior._combat.reload_if_dry()


## Whether the NPC is a primed ambusher (LD15): its running leaf the `ambush` of its live order, at
## its post.
func primed() -> bool:
	return behavior.task.primitive == &"ambush" and behavior.task.arrived and _live()


## Whether the order the running leaf carries out (its `order_id`) is still the NPC's live order
## (`AgentPerception.orders.current`).
func _live() -> bool:
	var task: RunningLeaf = behavior.task
	return (task.params.has("order_id")
			and str(behavior._perception.orders.current().get("id", ""))
					== str(task.params["order_id"]))


## Note step `step` of the order the running leaf carries out (its `order_id`), once until the next
## step differs, for the controller to radio (`take_steps`, `docs/leadership.md` LD7). Nothing for a
## leaf that is no order.
func say_step(step: String) -> void:
	var task: RunningLeaf = behavior.task
	if not task.params.has("order_id"):
		return
	var id = task.params["order_id"]
	if str(_said.get("id", "")) == str(id) and _said.get("step", "") == step:
		return
	_said = { "id": id, "step": step }
	_steps.append({ "order_id": id, "step": step })


## The order steps to radio since the last call (`{ order_id, step }`).
func take_steps() -> Array:
	var out := _steps
	_steps = []
	return out


## Follow (LD20 to LD22): keep to the spot the squad gives the NPC (`Squad.follow_spot`). The walk
## is re-aimed only once that spot has moved `SquadFollowConfig.retarget` from where it is going,
## and is over within `arrive` of it or where its path ends short of one it cannot reach; a
## follower catching up (`gait.catching_up`) whose walk target lagged its live spot re-aims at that
## spot there, until it is within `caught_up` of it. Its walk over, its catch-up is over too.
## There it stands facing away from its leader (its confinement's leash centre, the leader's live
## position) and, at rest with nothing to fight, tops up a low magazine. The watch stage shoots what
## it sees on the way. Its spot gone (it leads now, or left the squad): re-decide.
func apply_follow() -> void:
	var task: RunningLeaf = behavior.task
	var character: Node = behavior._character
	var combat: RefCounted = behavior._combat
	var loco: Node = behavior._loco
	var spot: Vector2 = (squad.follow_spot(character)
			if squad != null and is_instance_valid(squad)
			else Vector2.INF)
	if spot == Vector2.INF:
		character.movement.move_input = Vector2.ZERO
		task.primitive = &"hold"
		task.resolved = true
		return
	if follow_to == Vector2.INF or spot.distance_to(follow_to) > SquadFollowConfig.retarget:
		follow_to = spot
		task.arrived = false
	if not task.arrived:
		task.arrived = loco.reached(follow_to, SquadFollowConfig.arrive)
		if (task.arrived and behavior.gait.catching_up
				and follow_to.distance_to(spot) > SquadFollowConfig.arrive
				and character.global_position.distance_to(spot) > SquadFollowConfig.caught_up):
			# Catching up, it is not there until it has caught up: on to its live spot.
			follow_to = spot
			task.arrived = false
		_follow_stood = GameClock.seconds()
	if not task.arrived:
		loco.move_to(follow_to, SquadFollowConfig.arrive)
		behavior.errand.aim_move()
		return
	behavior.gait.catching_up = false
	character.movement.move_input = Vector2.ZERO
	var here: Vector2 = character.global_position
	var lead: Vector2 = behavior._perception.confinement.leash_center
	if lead != Vector2.INF and here.distance_to(lead) > 1.0:
		character.movement.aim_point = here + (here - lead).normalized() * 100.0
	# At rest once it has stood as long as a still leader does (a file walk stops between re-aims).
	if (GameClock.seconds() - _follow_stood >= SquadFollowConfig.still_time
			and behavior._watch.threat.is_empty()
			and not behavior._perception.under_fire()
			and combat.magazine_low(behavior.tuning.context.low_ammo_fraction)):
		combat.top_off()


## Whether the running primitive is on its way somewhere it chose: a move or an engage not yet
## there, or a throw's walk to its throw spot.
func walk_pending() -> bool:
	var task: RunningLeaf = behavior.task
	match task.primitive:
		&"move", &"engage":
			return not task.arrived
		&"throw":
			return behavior._combat.throw.stage == "walk"
	return false
