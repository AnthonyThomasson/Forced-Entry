extends RefCounted
## AI orchestrator: the controller's radio, a part it builds once in its `_ready` and holds as
## `_comms`. It hands the EventBus events the controller queued (`event_queue`) to the perception
## each tick, and radios the NPC's own callouts (interface 10): a decision, a grenade seen or heard
## come down, a throw, a tactical entry's steps and the progress of the order it holds; it also
## re-adopts an ENTER that turned into a bang. Built once with its controller, it holds it (a node,
## so no reference cycle) for the NPC's body, perception, planner, behaviour, cadence and tuning.

## The entry claim's wire format (an entry step's callout fields).
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")

## The controller it belongs to.
var controller: Node
## [topic, data] pairs awaiting processing once the controller knows its character.
var event_queue: Array = []
## The last callout this NPC radioed (`position`, `point`, `label`, `at` in game msec), for the
## hearing overlay.
var last_callout := {}


func _init(brain: Node) -> void:
	controller = brain


## Hand buffered EventBus events to the perception. A hit that is a relevant attack forces an
## immediate re-decision only when the NPC is NOT already fighting (to kick off a fight); while
## fighting it just refreshes the engagement, so a firefight doesn't re-ask Von every frame. Allies'
## callouts are folded in when this NPC listens to them.
func process_events() -> void:
	if event_queue.is_empty():
		return
	var perception: Node = controller._perception
	var behavior: Node = controller._behavior
	var cadence: RefCounted = controller._cadence
	# A deafened NPC hears no gunfire, no footsteps, no hit elsewhere and no radio call (G15).
	var deaf: bool = controller._character.stun.is_deaf()
	for ev in event_queue:
		match ev[0]:
			&"hit":
				if deaf and ev[1].get("victim") != controller._character:
					continue
				if perception.process_hit(ev[1]) and not behavior.in_combat():
					cadence.force("attacked")
			&"callout":
				if controller.tuning.radio.hear_callouts and not deaf:
					perception.process_callout(ev[1])
			&"footfall":
				if not deaf:
					perception.process_footfall(ev[1])
			&"grenade":
				perception.process_grenade(ev[1], deaf)
			&"explosion":
				perception.process_explosion(ev[1])
			&"order":
				# An order (LD5) reaches its recipients whatever their state, deaf included, and is
				# decided on at once, as a hit is (after a crossing or an evade, which hold every
				# decision).
				if perception.process_order(ev[1]):
					cadence.force("ordered")
					# A walk it replaces stands until a decision started from here on lands
					# (`_on_decided`).
					cadence.order_from = cadence.decisions
					behavior.orders.await_next(true)
	event_queue.clear()


## The progress of the order the NPC holds, on the radio (`docs/leadership.md` LD7): the steps the
## behaviour reports as it carries it out (`moving`, `in_position`), and `done` / `refused` once it
## has ended so; on the team radio, so only with `tuning.radio.send_callouts`.
func report_order() -> void:
	var steps: Array = controller._behavior.orders.take_steps()
	var ended: Dictionary = controller._perception.take_ended_order()
	if not ended.is_empty():
		steps.append({ "order_id": ended["id"], "step": ended["why"] })
	if controller.tuning.radio.send_callouts:
		for step in steps:
			_post_order_step(step["order_id"], step["step"])


## The running ENTER became a bang one, its room suspect (`docs/tactical-entry.md` E17: at its
## start, or on a late reason): the order is re-adopted as the STUN ENTRY it now is
## (`search/stun_entry/<door>`, its label from the tree), so what the NPC is doing reads as it is.
## An entry the guard runs under another order (a walk's detour) keeps that order's name.
func on_entry_turned() -> void:
	var order: Dictionary = controller._behavior.order()
	var path: Array = order["path"]
	if path.size() < 2 or str(path[0]) != "search" or str(path[1]) != "enter":
		return
	var labels: Array = order["labels"]
	path[1] = &"stun_entry"
	if labels.size() >= 2:
		labels[1] = controller._planner.label_of(&"stun_entry")
	controller._behavior.entries.adopt_bang(path, labels)
	GameLog.say("%s (suspect room) %s" % [controller._npc_name(), " - ".join(labels)])


## Broadcast this NPC's decision as an `&"callout"` EventBus event (interface 10): who is speaking
## and where, its state, the decision path, its target and destination, and with a combat decision
## `target_pos` (where the hostile is as it knows it). Allies within range hear it.
func post_callout(leaf: Dictionary) -> void:
	var character: Node = controller._character
	var params: Dictionary = leaf["params"]
	var status := _status(leaf["primitive"] == &"reload")
	last_callout = {
		"position": character.global_position,
		"point": params.get("point", character.global_position),
		"label": " - ".join(leaf["labels"]), "at": GameClock.msec(),
	}
	var radio := _callout_header(
		", ".join(status), "/".join(leaf["path"]), " - ".join(leaf["labels"]),
		params.get("point", character.global_position), params.get("target_id", 0),
	)
	if str(leaf["path"][0]) == "combat":
		# Where the hostile is, as the speaker knows it: an ally weighing the room it is in hears it
		# (docs/grenades.md G18).
		radio["target_pos"] = controller._perception.target_pos(params.get("target_id", 0))
	EventBus.post(&"callout", radio)


## Radio a live grenade the NPC has seen or heard come down (`{ point, kind }`) as an `&"grenade"`
## callout: the spot it landed at and its kind, for the allies in its danger zone who neither saw
## nor heard it (G16). `point` is the landing.
func post_grenade_call(grenade: Dictionary) -> void:
	var label := "a %s grenade" % grenade["kind"]
	last_callout = {
		"position": controller._character.global_position,
		"point": grenade["point"],
		"label": label,
		"at": GameClock.msec(),
	}
	var msg := _callout_header("grenade", "", label, grenade["point"])
	msg["kind"] = grenade["kind"]
	EventBus.post(&"callout", msg)


## Radio a grenade this NPC has just thrown (`{ kind, point }` from the behaviour) as a `frag_out` /
## `bang_out` `&"callout"`: where it is going to land and its kind, for the allies near it to get
## clear of (G16, G17). `point` is the landing.
func post_throw_call(throw: Dictionary) -> void:
	var status := "frag_out" if throw["kind"] == &"frag" else "bang_out"
	var label := "%s!" % status.replace("_", " ")
	last_callout = {
		"position": controller._character.global_position,
		"point": throw["point"],
		"label": label,
		"at": GameClock.msec(),
	}
	var msg := _callout_header(status, controller._behavior.current_act(), label, throw["point"])
	msg["kind"] = throw["kind"]
	EventBus.post(&"callout", msg)


## Radio one step of a tactical entry (`claim`, in `StackClaim`'s fields, from the behaviour) as an
## `&"callout"`: the callout's header (`_callout_header`) and the claim's entry fields, every one
## encoded by `StackClaim.encode` (the doorway, slot, side and `entry_step`, the bang's mode and
## grenades, the frame and spot it was claimed on, a move-up, the pie, the order it stacks under, a
## join's mark: stack/stack_claim.gd `DEFAULTS`). It is how the stack claims slots, waits for the
## team and crosses in order; "going in" is also said in `status`. `point` is where the speaker
## stands.
func post_entry_call(claim: Dictionary) -> void:
	var character: Node = controller._character
	var status := _status(false)
	if claim["entry_step"] == "going_in":
		status.push_front("going in")
	var labels: String = controller._behavior.path_label()
	last_callout = {
		"position": character.global_position, "point": character.global_position,
		"label": "%s (%s)" % [labels, String(claim["entry_step"]).replace("_", " ")],
		"at": GameClock.msec(),
	}
	var msg := _callout_header(
		", ".join(status), controller._behavior.current_act(), labels, character.global_position,
	)
	msg.merge(StackClaim.encode(claim))
	EventBus.post(&"callout", msg)


## Radio step `step` of order `order_id` as an `&"callout"` with `order_id` and `order_step`: the
## speaker, where it stands and what it is doing. Allies leave it out of what they weigh; its squad
## keeps it as the member's latest step.
func _post_order_step(order_id: Variant, step: String) -> void:
	var character: Node = controller._character
	var behavior: Node = controller._behavior
	last_callout = {
		"position": character.global_position, "point": character.global_position,
		"label": "%s (%s)" % [behavior.path_label(), step.replace("_", " ")],
		"at": GameClock.msec(),
	}
	var msg := _callout_header(
		", ".join(_status(false)), behavior.current_act(), behavior.path_label(),
		character.global_position,
	)
	msg["order_id"] = order_id
	msg["order_step"] = step
	EventBus.post(&"callout", msg)


## The fields every callout of this NPC's starts with (interface 10): the speaker, its faction and
## where it stands, its `status`, the decision `path`, the `label`, the `target_id` and the `point`.
func _callout_header(
	status: String,
	path: String,
	label: String,
	point: Vector2,
	target_id: Variant = 0,
) -> Dictionary:
	var character: Node = controller._character
	return {
		"speaker": character,
		"faction": character.faction,
		"position": character.global_position,
		"status": status,
		"path": path,
		"label": label,
		"target_id": target_id,
		"point": point,
	}


## The speaker's state for a callout: under fire, wounded, reloading.
func _status(reloading: bool) -> Array:
	var status: Array = []
	if controller._perception.under_fire():
		status.append("under fire")
	var dmg: float = controller._character.damage_taken()
	if dmg >= controller.tuning.context.critical_threshold:
		status.append("badly wounded")
	elif dmg >= controller.tuning.context.hurt_threshold:
		status.append("hurt")
	if reloading or controller._character.ammo.is_reloading():
		status.append("reloading")
	return status
