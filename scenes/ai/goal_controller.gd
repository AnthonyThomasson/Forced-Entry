extends Node
## AI domain ORCHESTRATOR: a generic, goal-driven controller for a non-player character. It is the
## AI's own composition root (the `main.gd` of the AI domain): it wires the three sub-domains it
## builds (the fourth, debug/, reads its `debug_*` getters) and runs the SENSE → THINK → ACT loop,
## but holds almost no behaviour itself. It satisfies the character's controller contract
## (`control(character, delta)`) and writes only the intent the player controller writes
## (`movement.move_input`/`movement.aim_point`) plus the same public actions — all of that done by
## the behaviour sub-domain. It is the single authoring surface: `goal` and every tunable, the
## tunables in its `Tuning` child's topic nodes (`tuning`, `scenes/ai/tuning/`), so a defender or
## invader preset is all data on this one node, read by the sub-domains it builds (their
## `apply_config(tuning)`) — and read again each decision, so a tunable retuned at runtime (a
## behaviour test, the dev command server) takes effect without a rebuild.
##
## The three sub-domains it builds (see their `domain-ai-<name>` skills; the fourth, DEBUG (debug/),
## is the draw-only overlays, children of the NPC that read this node's `debug_*` getters):
##   • PERCEPTION (perception/) — SENSE. What the NPC knows: sight, hostility, event memory, the
##     known-contacts view, combat geometry, and the decision SNAPSHOT (state sections, facts and
##     option groups). The NPC is NOT omniscient — it acts on last-KNOWN positions and forgets what
##     decays.
##   • DECISION (decision/) — THINK. The decision TREE and its planner: Von picks top-down, one
##     `choice` request per level — a broad mode (combat / investigate / search / idle), the
##     hostile, a tactic (engage / flank / advance / retreat / reload …), then a concrete option —
##     ending in one behaviour primitive.
##   • BEHAVIOUR (behavior/) — ACT. Runs the chosen primitive (move / engage / melee / interact /
##     reload / entry / throw / hold) as movement + actions, and holds the System-Two state Von
##     lacks: the engaged contact, peek-and-cover, the interaction in progress, and the commitment
##     that keeps a choice running.
##
## This file keeps only the ORCHESTRATION: the control loop, the decide cadence, forcing a
## re-decision on a salient event or a finished task (interrupting a walk in flight when the
## situation now calls for a different starting point — e.g. under fire → straight to combat), the
## EventBus intake (hits, footfalls and allies' radio callouts) and posting this NPC's own callouts.
## The behaviour is pure DATA — `goal` plus the generic primitives and decision config of its
## `tuning`; a house defender and a house invader are the same code with different data.

const AgentPerception := preload("res://scenes/ai/perception/agent_perception.gd")
const DecisionClient := preload("res://scenes/ai/decision/decision_client.gd")
const DecisionPlanner := preload("res://scenes/ai/decision/decision_planner.gd")
## The frame's snapshot count (DecisionBudget).
const Budget := preload("res://scenes/ai/decision/decision_budget.gd")
const Behavior := preload("res://scenes/ai/behavior/behavior.gd")
## The entry claim's wire format (an entry step's callout fields).
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
const ZoneList := preload("res://scenes/ai/debug/zone_list.gd")

## The behaviour to pursue, in plain language — what Von ranks every level of the decision against.
## `{gun}` stands for whatever gun the NPC carries ("shoot them with your {gun}"); read it filled in
## through `goal_text()`.
@export_multiline var goal: String = ("Deal with hostile characters: shoot them with your {gun}. " +
	"Otherwise go about your business.")
## The NPC's tunables (`scenes/ai/tuning/`): one topic node per concern under the `Tuning` child,
## each only exports (`tuning.hostility.on_sight`, `tuning.decision.pursue_hostiles`, ...). A
## preset authors them on its scene, a test sets one as an indexed path
## (`tuning:entry:ready_timeout`).
@export var tuning: NpcTuning
## NavigationAgent2D used for pathing (a sibling under the character); set in the NPC scene.
@export var nav_agent_path: NodePath

## World-space room rects (`{ key, type, rect }`) from its composer (`MatchBuilder.bind_npc`) — the
## sensor's map of the house.
var rooms: Array = []
## The house entrance in world space, injected by its composer (`MatchBuilder.bind_npc`) for NPCs
## that start outside. Handed to the perception once (it offers "the front entrance" as a search
## option while outside).
var entry_point: Vector2 = Vector2.ZERO
## The house's doorways (`{ pos, width, front, exit, rooms }`) from its composer
## (`MatchBuilder.bind_npc`), for tactical entry.
var openings: Array = []
## The NPC's side's squad (`ai/team/squad.gd`, `docs/leadership.md` LD3), handed in by its
## composer (`MatchBuilder.bind_squad`): who leads it and who is in it. The orders themselves come
## off the bus (`&"order"`), so an NPC with none still takes the ones that name it.
var squad: Node = null
## SENSE sub-domain: knowledge, the decision snapshot, combat geometry.
var _perception: Node
## THINK transport: the Von round-trip (decision/decision_client.gd).
var _client: Node
## THINK policy: the decision-tree walk (decision/decision_planner.gd).
var _planner: Node
## ACT sub-domain: runs the chosen primitive + holds commitment state.
var _behavior: Node
## The facts of the last decision snapshot, retained for `debug_state()`.
var _last_facts := {}
## The state sections of the last decision snapshot (the global ones: `goal`, `order`, ...), the
## text Von reads in any question of the walk, retained for `debug_state()`.
var _last_sections := {}
## The option groups of the last snapshot, retained for `debug_zones()`.
var _last_options := {}
## The tactical point an observer asked to highlight (`debug_focus`), or INF for none.
var _debug_focus := Vector2.INF
## Seconds until the next decision is allowed.
var _decide_timer := 0.0
## Force a decision now (task resolved or salient event).
var _force := false
## Why `_force` was last raised, kept (with `_force_ms`) for the brain overlay.
var _force_reason := ""
## Decision walks started so far (`debug_state()["decisions"]`).
var _decisions := 0
## `_decisions` when an order was last taken, while its decision has not landed (-1: none awaited);
## see `Behavior.await_order`.
var _order_from := -1
## Why the latest walk was started: the force reason, or "cadence"
## (`debug_state()["decision_reason"]`).
var _decision_reason := ""
## When `_force_reason` was raised (game msec, `GameClock.msec()`).
var _force_ms := 0
## The last callout this NPC radioed (`position`, `point`, `label`, `at` in game msec), for the
## hearing overlay.
var _last_callout := {}
## Known-hostile set + engaged contact's inside state, for edge detection.
var _salient_key := ""
## Whether _salient_key has been seeded.
var _salient_init := false
# EventBus events are queued here, then handed to perception on the next control() tick.
## The character this controller drives, captured on first control.
var _character: Node
## [topic, data] pairs awaiting processing once _character is known.
var _event_queue: Array = []
## The character was flash-blinded last tick, to re-decide the moment its sight returns.
var _was_blind := false
## Whether the NPC followed its squad's leader last tick (`Squad.follows`, LD19).
var _follows := false
## A fight off the leash forced a decision, and the NPC has not been back within the break since.
var _leash_broke := false
## The AI's one source of chance (the blind-fire roll, G15), seeded once at bind from the
## character's name and spawn spot, so a seeded match or a test that places the NPC the same way
## draws the same rolls.
var _rng := RandomNumberGenerator.new()


## Build the AI sub-domains and wire them together, then configure them from the tuning with
## _apply_config(). The sub-domains each own internal modules (perception's sight/hostility/memory/
## tactics, the behaviour's locomotion), so building and configuring are separate: _ready() builds
## once, _apply_config() configures (here and again each decision, so a tunable retuned at runtime
## still takes effect without a rebuild that would wipe memory or in-flight state).
func _ready() -> void:
	# The group the observers find an NPC's controller by (interface 7).
	add_to_group(&"npc_controllers")
	# SENSE: the perception sub-domain owns sight, hostility, memory and the combat geometry
	# internally.
	_perception = AgentPerception.new()
	add_child(_perception)
	_perception.setup()
	# THINK: the Von transport, and the planner that walks the decision tree through it.
	# node_overrides is baked into the tree at setup() (construction-time only); the rest of the
	# planner's config is applied by _apply_config(), which turns the policy primitives into tree
	# config (pursuit starts at COMBAT once a hostile is known and never idles; territory keeps
	# combat options inside the house).
	_client = DecisionClient.new()
	_client.configure(tuning.decision.server_url, tuning.decision.model, 3.0)
	add_child(_client)
	_planner = DecisionPlanner.new()
	_planner.node_overrides = tuning.decision.node_overrides
	add_child(_planner)
	# ACT: the behaviour sub-domain (owns its own locomotion). It reads the world via perception and
	# falls back to a steady stance when no decision can be had.
	_behavior = Behavior.new()
	var nav_agent: NavigationAgent2D = null
	if nav_agent_path != NodePath():
		nav_agent = get_node_or_null(nav_agent_path) as NavigationAgent2D
	add_child(_behavior)
	_behavior.setup(_perception, nav_agent)
	_apply_config()
	_planner.setup(_client)
	_planner.decided.connect(_on_decided)
	_planner.failed.connect(_behavior.fallback)
	EventBus.posted.connect(_on_event)


## Configure the sub-domains from the tuning. The controller is the single authoring surface —
## every tunable lives in a topic node of its `tuning` — and this is where they reach the
## sub-modules: the perception and the behaviour each take the hub (`apply_config(tuning)`, the
## behaviour with the squad) and set their own fields and their modules' from it, and the planner's
## config is worked out here. It only SETS config on
## already-built sub-domains (never rebuilds), so it is safe to call each decision: a tunable
## retuned at runtime (e.g. by the dev command server for a behaviour test) takes effect on the next
## one.
func _apply_config() -> void:
	_perception.apply_config(tuning)
	# The pursuit/territory primitives become planner config: pursuit disables IDLE and starts a
	# walk at COMBAT once a hostile is known; territory confines combat options inside the house.
	var disabled: Array[StringName] = []
	disabled.assign(tuning.decision.disabled_nodes)
	var rules := tuning.decision.entry_rules.duplicate()
	# An order (docs/leadership.md LD6) is carried out unless the NPC is shot at or fighting (the
	# fight rules above come first); it comes before `hostile_known`, which would otherwise hide it
	# whenever any hostile is known.
	if not rules.has(&"ordered") and not rules.has("ordered"):
		rules[&"ordered"] = &"order"
	if tuning.decision.pursue_hostiles:
		if not disabled.has(&"idle"):
			disabled.append(&"idle")
		if not rules.has(&"hostile_known") and not rules.has("hostile_known"):
			rules[&"hostile_known"] = &"combat"
	_planner.skip_single_option = tuning.decision.skip_single_option
	_planner.inside_only = tuning.decision.defend_territory
	var held: Dictionary = _perception.order()
	_planner.confine_room = (String(held.get("room", ""))
			if String(held.get("kind", "")) == "defend_room"
			else "")
	# A follower picks no goal of its own (LD20): it follows its leader after the fight and order
	# rules, and, holding no order, fights only within its leash of the leader (LD23).
	var lead := _leader_followed()
	if lead != null:
		for id in [&"investigate", &"search", &"idle"]:
			if not disabled.has(id):
				disabled.append(id)
		if not rules.has(&"follows") and not rules.has("follows"):
			rules[&"follows"] = &"follow"
	_planner.disabled_nodes = disabled
	_planner.entry_rules = rules
	var leash_lead := _leash_lead()
	_planner.leash_center = leash_lead.global_position if leash_lead != null else Vector2.INF
	_planner.leash = float(squad.leash) if leash_lead != null else 0.0
	_behavior.apply_config(tuning, squad)


## Buffer a world event for processing on the next control() tick (the signal can fire before the
## controller knows which character it drives): hits (combat awareness, gunfire heard), footfalls
## (footsteps heard; one out of earshot of every gait is dropped here, as they come many a second),
## allies' radio callouts, a grenade coming down or going off, and the leader's orders.
func _on_event(topic: StringName, data: Dictionary) -> void:
	if (topic == &"hit"
			or topic == &"callout"
			or topic == &"grenade"
			or topic == &"explosion"
			or topic == &"order"):
		_event_queue.append([topic, data])
	elif (topic == &"footfall"
			and _character != null
			and _character.global_position.distance_to(data.get("position", Vector2.INF))
				<= _perception.footfall_reach()):
		_event_queue.append([topic, data])


## Read-only: the goal as Von reads it, with `{gun}` filled in with the NPC's gun (the raw `goal`
## before it has acted).
func goal_text() -> String:
	if _perception == null or not is_instance_valid(_character):
		return goal.replace("{gun}", "gun")
	return _perception.fill_goal(goal)


## Read-only: the decision path the NPC is carrying out, as ids ("combat/t_12/flank/side_left").
func current_act() -> String:
	return _behavior.current_act() if _behavior != null else "hold"


## Read-only: the full decision path the NPC is carrying out, every level ("COMBAT - Intruder -
## FLANK - their left side (kitchen)"), plus its progress — for debug overlays/observers.
func debug_status() -> String:
	return _behavior.debug_status() if _behavior != null else "HOLD"


## Read-only: the WHOLE AI state as structured data — the deep counterpart to `debug_status()`'s
## one-line label, for an observer (the dev command server) to inspect on demand. It answers what a
## log line can't: the facts the last decision gated on and its state sections (`sections`: the text
## Von reads, also when no level asked, e.g. the `order` an ORDER walk took), every level of the
## last walk (the exact state and question Von saw, the options, its probabilities and pick,
## auto-picks and timings), what the NPC knows (`contacts`), the running primitive and pathing, how
## many decision walks it has started and why the latest one started (`decisions`,
## `decision_reason`: the force reason, e.g. "task resolved" or "way blocked", or "cadence"). Pure
## reads — never perturbs the loop.
func debug_state() -> Dictionary:
	var out := {
		"npc": _npc_name(),
		"goal": goal_text(),
		"decide_in": _decide_timer,
		"forced": _force,
		"decisions": _decisions,
		"decision_reason": _decision_reason,
		"facts": _last_facts,
		"sections": _last_sections,
	}
	if _planner != null:
		out["decision"] = _planner.debug_state()
	if _perception != null:
		out["under_fire"] = _perception.under_fire()
		out["engaged_fresh"] = _perception.engaged_fresh()
		out["memory_size"] = _perception.memory_size()
		out["contacts"] = _contact_digest()
	if _behavior != null:
		out.merge(_behavior.debug_state())
	return out


## Read-only: the tactical navigation ZONES the NPC's perception laid out for its last decision,
## flattened to world points tagged by kind (see `debug/zone_list.gd`), for the tactics debug
## overlay to draw. Empty until the first decision.
func debug_zones() -> Array:
	return ZoneList.from_options(_last_options)


## Highlight the tactical point at world `point` on the tactics overlay (the spectator inspector's
## clicked zone). Debug only: it changes nothing the NPC does.
func debug_focus(point: Vector2) -> void:
	_debug_focus = point


## Clear the highlighted tactical point (`debug_focus`).
func debug_clear_focus() -> void:
	_debug_focus = Vector2.INF


## Read-only: the tactical point highlighted (`debug_focus`), or INF for none, for the tactics
## overlay to ring.
func debug_focus_point() -> Vector2:
	return _debug_focus


## Read-only: the tactical ROOM zones — every room of the house tagged by how this NPC regards it
## now (`current` / `searched` / `unsearched` / `unknown`), each as a world-space `rect` with its
## `type`, for the tactics debug overlay to draw. It is the room reasoning the search / room / flank
## options are placed against. Empty until the controller knows its character. A pure read of the
## perception.
func debug_room_zones() -> Array:
	if _character == null or _perception == null:
		return []
	return _perception.room_status(rooms, _character.global_position)


## Read-only: the running tactical entry — the doorway (`opening`, `into`), the NPC's stack `slot`
## and `side`, whether it is going `solo`, its `phase`, what the pie saw (`seen_fraction`,
## `pie_sides`, `hidden_corners`), its `corner` and `stack_point`, as the behaviour reports it
## (typed values; `debug_state()["entry"]` is the JSON-safe copy). Empty when the NPC isn't entering
## a room.
func debug_entry() -> Dictionary:
	return _behavior.debug_entry() if _behavior != null else {}


## Read-only: the tactical entry and the entry guard as world-space data, for the entry debug
## overlays: `entry` (the doorway's slots, pie arc and corners, this NPC's role, timers, the team
## off the radio, the doorways it covers; {} when not entering) and `guard` (a running detour and
## the order it paused, the next uncleared doorway on the walk, the rooms regarded as cleared). See
## behavior.gd `debug_entry_view`.
func debug_entry_view() -> Dictionary:
	if _behavior == null or _character == null:
		return {}
	return _behavior.debug_entry_view()


## Read-only: the behaviour's running search-coverage state (which room sample points it has seen
## vs. still needs to, and the one it is looking at now), for the search debug overlay.
## Empty/inactive when the NPC isn't currently covering a room.
func debug_search_coverage() -> Dictionary:
	return _behavior.debug_coverage() if _behavior != null else {}


## Read-only: where the NPC's sight toward world point `to` is first blocked (over low cover, the
## perception's own sight rule), or `to` when it reaches it — for the vision overlay, so it draws
## the area the sense really covers.
func debug_sight_end(to: Vector2) -> Vector2:
	if _perception == null or _character == null:
		return to
	return _perception.sight_end(to)


## Read-only: what the NPC has heard and been told (gunfire heard, under-fire direction, ally
## callouts, lost hostiles, checked leads, radii) — for the contacts and hearing overlays. Empty
## before perception exists.
func debug_memory() -> Dictionary:
	return _perception.debug_memory() if _perception != null else {}


## Read-only: the behaviour's combat / movement / interaction state as world-space data — the
## engaged target, committed destination, aim and fire line, peek-and-cover phase, leash,
## move/interact targets — for the combat, territory and targets overlays. Empty until the
## controller knows its character.
func debug_combat() -> Dictionary:
	if _behavior == null or _character == null:
		return {}
	return _behavior.debug_combat()


## Read-only: the movement-progress sample (seconds stalled, recent trail) for the stuck overlay.
func debug_progress() -> Dictionary:
	return _behavior.debug_progress() if _behavior != null else {}


## Read-only: the NPC's grenade awareness for the grenade overlay: `known` (the live grenades it
## knows of, soonest first, each `{ point, kind, fuse_left, fuse, radius, source }`, `source` being
## `&"seen"` / `&"heard"` / `&"called"` / `&"own"`), `escape` (the safe spot it is running to,
## `Vector2.INF` when it is not running to one) and `throw` (the throw it is about to make,
## `{ from, to, kind, radius }`; {} when it is not making one, or once the grenade has left its
## hand).
func debug_grenades() -> Dictionary:
	if _perception == null or _behavior == null:
		return { "known": [], "escape": Vector2.INF, "throw": {} }
	return { "known": _perception.known_grenades(), "escape": _behavior.evade_spot(),
		"throw": _behavior.throw_plan() if _character != null else {} }


## Read-only: the last callout this NPC radioed (`position`, `point`, `label`, `at` msec), or empty.
func debug_sent_callout() -> Dictionary:
	return _last_callout


## Read-only: the decision machinery's live state for the brain overlay — whether Von is being asked
## (`pending`), the last walk's levels (state, offered options, probabilities, pick), whether it
## failed (the behaviour then holds steady), the decide/force timers and why the last force fired,
## and the facts.
func debug_brain() -> Dictionary:
	if _planner == null:
		return {}
	var d: Dictionary = _planner.debug_state()
	var timers: Dictionary = (_behavior.debug_combat().get("timers", {})
			if _character != null
			else {})
	return {
		"pending": d.get("pending", false),
		"failed": d.get("last_failed", false),
		"entry": d.get("entry", ""),
		"levels": d.get("levels", []),
		"decide_in": maxf(_decide_timer, 0.0),
		"decide_interval": tuning.decision.decide_interval,
		"forced": _force,
		"force_reason": _force_reason,
		"force_age": (GameClock.msec() - _force_ms) / 1000.0 if _force_reason != "" else INF,
		"timers": timers,
		"facts": _last_facts,
	}


## Full contact data for display in the spectator inspector: each entry has `node`, `pos`
## (last-known world position), `name`, `hostile`, `visible` (seen this tick) and `age` (seconds
## since last seen).
func known_contacts_for_display() -> Array:
	if _character == null or _perception == null:
		return []
	return _perception.all_seen_characters(_character.global_position)


## The known-contacts list flattened to the fields worth reading in a snapshot (who, whether hostile
## and why, whether seen this tick, and how far off). Empty until the controller knows its
## character.
func _contact_digest() -> Array:
	if _character == null:
		return []
	var self_pos: Vector2 = _character.global_position
	var out: Array = []
	for c in _perception.contacts(self_pos):
		out.append({
			"name": c["name"],
			"hostile": c["hostile"],
			"reason": c["reason"],
			"visible": c["visible"],
			"inside": c.get("inside", false),
			"dist": int((c["pos"] as Vector2).distance_to(self_pos)),
		})
	return out


## Called each physics frame by the character. Runs the SENSE → THINK → ACT loop: fold queued events
## in, perceive, let the behaviour resolve what it knows + honour its commitments, start a decision
## walk only when free to (or restart one a new situation has overtaken), then let the behaviour
## carry out the running primitive.
func control(character: Node, delta: float) -> void:
	if character.is_dead:
		return
	if _character == null:
		_bind_body(character)
	_decide_timer -= delta
	_sense(character, delta)
	# An active interaction holds the tick; when it or a move resolves, re-decide at once.
	if _behavior.service_interaction(delta, _force):
		return
	_take_resolved()
	_think()
	_act(delta)


## Takes `character` as the NPC's body on its first tick: seeds the controller's RNG from its name
## and spawn spot, and hands it to the perception and the behaviour.
func _bind_body(character: Node) -> void:
	_character = character
	_rng.seed = hash("%s %s" % [character.name, character.global_position.round()])
	_perception.bind(character)
	_behavior.bind(character)
	_client.set_npc_name(_npc_name())


## SENSE: folds the queued events in, perceives, and lets the behaviour adopt the hostiles it knows
## (reconsidering at once when the engaged contact is lost) before the salient-event check.
func _sense(character: Node, delta: float) -> void:
	_process_events()
	_follow_squad()
	_perception.openings = openings
	_perception.observe(rooms)
	_react_to_grenades()
	_behavior.rooms = rooms
	if entry_point != Vector2.ZERO:
		_perception.entry_point = entry_point # Hand the injected entrance to the perception once.
		entry_point = Vector2.ZERO
	var known: Array = _perception.contacts(character.global_position)
	if _behavior.update_known(known, delta):
		_force_now("lost the engaged contact") # Lost the engaged contact mid-fight → reconsider.
	_check_salient()


## A task the behaviour resolved forces a decision at once, with the reason it gives; a lead it
## reached is checked off.
func _take_resolved() -> void:
	var why: String = _behavior.resolve_reason()
	if _behavior.take_resolved():
		_force_now(why if why != "" else "task resolved")
		var lead: String = _behavior.reached_lead()
		if lead != "":
			_perception.check_lead(lead) # Reached it and found nothing: don't send it back there.


## THINK: restarts a decision walk a forced decision has overtaken, or starts one when free to.
func _think() -> void:
	if _planner.is_pending():
		if _force:
			_maybe_interrupt()
	elif _should_decide():
		_start_decision()


## ACT: the behaviour carries out the running primitive, then the entry turn, the entry and throw
## calls and the order's progress go out.
func _act(delta: float) -> void:
	_behavior.apply(delta)
	if _behavior.take_entry_turned():
		_on_entry_turned()
	for claim in _behavior.take_entry_calls():
		if tuning.radio.send_callouts:
			_post_entry_call(claim)
	for throw in _behavior.take_throw_calls():
		if tuning.radio.send_callouts:
			_post_throw_call(throw)
	_report_order()


## The progress of the order the NPC holds, on the radio (`docs/leadership.md` LD7): the steps the
## behaviour reports as it carries it out (`moving`, `in_position`), and `done` / `refused` once it
## has ended so; on the team radio, so only with `tuning.radio.send_callouts`.
func _report_order() -> void:
	var steps: Array = _behavior.take_order_steps()
	var ended: Dictionary = _perception.take_ended_order()
	if not ended.is_empty():
		steps.append({ "order_id": ended["id"], "step": ended["why"] })
	if tuning.radio.send_callouts:
		for step in steps:
			_post_order_step(step["order_id"], step["step"])


## Radio step `step` of order `order_id` as an `&"callout"` with `order_id` and `order_step`: the
## speaker, where it stands and what it is doing. Allies leave it out of what they weigh; its squad
## keeps it as the member's latest step.
func _post_order_step(order_id: Variant, step: String) -> void:
	_last_callout = {
		"position": _character.global_position, "point": _character.global_position,
		"label": "%s (%s)" % [_behavior.path_label(), step.replace("_", " ")],
		"at": GameClock.msec(),
	}
	var msg := _callout_header(
		", ".join(_status(false)), _behavior.current_act(), _behavior.path_label(),
		_character.global_position,
	)
	msg["order_id"] = order_id
	msg["order_step"] = step
	EventBus.post(&"callout", msg)


## The running ENTER became a bang one, its room suspect (`docs/tactical-entry.md` E17: at its
## start, or on a late reason): the order is re-adopted as the STUN ENTRY it now is
## (`search/stun_entry/<door>`, its label from the tree), so what the NPC is doing reads as it is.
## An entry the guard runs under another order (a walk's detour) keeps that order's name.
func _on_entry_turned() -> void:
	var order: Dictionary = _behavior.order()
	var path: Array = order["path"]
	if path.size() < 2 or str(path[0]) != "search" or str(path[1]) != "enter":
		return
	var labels: Array = order["labels"]
	path[1] = &"stun_entry"
	if labels.size() >= 2:
		labels[1] = _planner.label_of(&"stun_entry")
	_behavior.adopt_bang(path, labels)
	GameLog.say("%s (suspect room) %s" % [_npc_name(), " - ".join(labels)])


## Raise the force-decide flag and remember why, for the brain debug overlay.
func _force_now(reason: String) -> void:
	_force = true
	_force_reason = reason
	_force_ms = GameClock.msec()


## Whether a new decision may start now: never while crossing a doorway (a forced one waits until
## the NPC is through); always when forced; otherwise the behaviour decides whether its current
## commitment still holds (a fight, a move, an approach) or the decide cadence has elapsed. One that
## may must also get one of the frame's snapshots (`DecisionBudget`); refused, it keeps its wish
## (`_force`, the elapsed timer) and asks again next frame.
func _should_decide() -> bool:
	if _behavior.committed() or _behavior.evading() or _character.stun.is_blind():
		# A blinded NPC starts no new decision (G15), one running from a grenade none until the
		# burst (G16).
		return false
	if not _force and not _behavior.wants_decision(_decide_timer <= 0.0):
		return false
	if not _force and not _perception.routes_ready():
		# The routes it would weigh are still being measured (the avoid map is baking): a few
		# frames. A forced decision does not wait.
		return false
	return Budget.claim()


## A salient event arrived while a walk is in flight: restart the walk only when the situation now
## calls for a different starting node (e.g. it came under fire mid-way through choosing a room to
## search → straight to COMBAT). Otherwise the walk in flight already fits; let it finish.
func _maybe_interrupt() -> void:
	if _behavior.evading() or _character.stun.is_blind():
		return
	# An order taken since the walk in flight began always restarts it: that walk was made without
	# the order, and a walk the order replaces stands until one made with it lands.
	if (_order_from >= 0
			or _planner.entry_for(_perception.quick_facts()) != _planner.current_entry()):
		if Budget.claim():  # Else `_force` stays and the restart is tried again next frame.
			_start_decision()
	else:
		_force = false


## Sense the situation and start a decision walk over it. The planner answers asynchronously via
## `decided` / `failed` (the latter wired to the behaviour's steady-stance fallback).
func _start_decision() -> void:
	_decisions += 1
	_decision_reason = _force_reason if _force else "cadence"
	_force = false
	_decide_timer = tuning.decision.decide_interval
	_apply_config()  # Pick up any tunable retuned at runtime before sensing + deciding.
	var snapshot: Dictionary = _perception.sense(rooms, goal, _behavior.activity_text())
	_last_facts = snapshot["facts"]
	_last_sections = snapshot["sections"]
	_last_options = snapshot["options"]
	var held: Dictionary = _perception.order()
	if not held.is_empty() and (snapshot["options"]["order"]["options"] as Array).is_empty():
		# An order it cannot carry out (a room or doorway it does not know): said so, and dropped.
		_perception.end_order(held["id"], "refused")
		_last_facts["ordered"] = false
		# `_apply_config` confined the walk to the order's room: the walk is the NPC's own now.
		_planner.confine_room = ""
	_planner.begin(snapshot, _behavior.ongoing())


## Hand buffered EventBus events to the perception. A hit that is a relevant attack forces an
## immediate re-decision only when the NPC is NOT already fighting (to kick off a fight); while
## fighting it just refreshes the engagement, so a firefight doesn't re-ask Von every frame. Allies'
## callouts are folded in when this NPC listens to them.
func _process_events() -> void:
	if _event_queue.is_empty():
		return
	# A deafened NPC hears no gunfire, no footsteps, no hit elsewhere and no radio call (G15).
	var deaf: bool = _character.stun.is_deaf()
	for ev in _event_queue:
		match ev[0]:
			&"hit":
				if deaf and ev[1].get("victim") != _character:
					continue
				if _perception.process_hit(ev[1]) and not _behavior.in_combat():
					_force_now("attacked")
			&"callout":
				if tuning.radio.hear_callouts and not deaf:
					_perception.process_callout(ev[1])
			&"footfall":
				if not deaf:
					_perception.process_footfall(ev[1])
			&"grenade":
				_perception.process_grenade(ev[1], deaf)
			&"explosion":
				_perception.process_explosion(ev[1])
			&"order":
				# An order (LD5) reaches its recipients whatever their state, deaf included, and is
				# decided on at once, as a hit is (after a crossing or an evade, which hold every
				# decision).
				if _perception.process_order(ev[1]):
					_force_now("ordered")
					# A walk it replaces stands until a decision started from here on lands
					# (`_on_decided`).
					_order_from = _decisions
					_behavior.await_order(true)
	_event_queue.clear()


## The grenade reflex (G16) and the blind NPC (G15), every tick after the SEE pass: hand the
## behaviour the plan to get clear of the live grenade that threatens the NPC (or {}), radio the
## grenades it has seen or heard come down, roll once whether it fires blind the tick it goes blind,
## and re-decide the moment its sight returns.
func _react_to_grenades() -> void:
	_behavior.poll_throw()
	_behavior.set_evade(_perception.evade_plan())
	for grenade in _perception.grenade_announcements():
		if tuning.radio.send_callouts:
			_post_grenade_call(grenade)
	var blind: bool = _character.stun.is_blind()
	if blind and not _was_blind:
		# One draw per blinding, whatever the chance, so the sequence does not depend on it.
		var draw := _rng.randf()
		var chance := tuning.grenades.blind_fire_chance
		_behavior.set_blind_fire(draw < chance or chance >= 1.0)
	if _was_blind and not blind:
		_force_now("sight returned")
	_was_blind = blind


## The squad's follow reads, every tick (LD19, LD23): whether the NPC follows its leader (the
## perception's `follows`), deciding at once when that changes (it joined a squad's file, or the
## leader it followed died and it leads now), and the leash it fights within while it holds no
## order (`_leash_lead`). A leashed follower fighting farther than `leash_break` leashes from its
## leader, neither committed nor on its way somewhere, decides again, once until it has been back
## within that.
func _follow_squad() -> void:
	var follows: bool = (squad != null
			and is_instance_valid(squad)
			and squad.has_method("follows")
			and squad.follows(_character))
	_perception.follows = follows
	if follows != _follows:
		_follows = follows
		_force_now("follows its leader" if follows else "leads its squad")
	var lead := _leash_lead()
	if lead == null:
		_behavior.set_leash(Vector2.INF, 0.0)
		_leash_broke = false
		return
	_behavior.set_leash(lead.global_position, squad.leash)
	if (_character.global_position.distance_to(lead.global_position)
			<= squad.leash * squad.leash_break):
		_leash_broke = false
	elif (not _leash_broke
			and _behavior.in_combat()
			and not _behavior.committed()
			and not _behavior.walk_pending()):
		_leash_broke = true
		_force_now("off the leash")


## The leader the NPC follows (`Squad.leader`), or null when it follows none.
func _leader_followed() -> Node2D:
	if not _perception.follows:
		return null
	return squad.leader() as Node2D


## The leader whose leash the NPC fights within (LD23): the one it follows while it holds no order,
## else null (a member carrying an order, a held stack or a join included, goes where the order
## takes it).
func _leash_lead() -> Node2D:
	return _leader_followed() if _perception.order().is_empty() else null


## Force a re-decision when the NPC's BELIEF about hostiles changes: one is spotted, lost or newly
## categorized hostile, or the engaged contact crosses the house boundary (per its last sighting).
## These are the events worth interrupting a commitment for. The behaviour sub-domain packs that
## belief into a salient key; seeded on the first call so the initial state isn't a "change".
func _check_salient() -> void:
	var key: String = _behavior.salient_key()
	if not _salient_init:
		_salient_key = key
		_salient_init = true
		return
	if key != _salient_key:
		_salient_key = key
		_force_now("hostile belief changed")


## Adopt the planner's leaf: hand it to the behaviour, log the full decision path, and tell allies
## (a combat or investigation decision) over the radio.
func _on_decided(leaf: Dictionary) -> void:
	if _behavior.evading():
		return  # Overtaken by a grenade while Von was answering; the burst ends in a new decision.
	if _order_from >= 0 and _decisions <= _order_from:
		# A walk begun before the order came, which its restart superseded: the one made with the
		# order is on its way.
		return
	_order_from = -1
	_behavior.set_leaf(leaf)
	# The order just adopted sets (or clears) the engaged contact, which the salient key carries:
	# that is not a change of belief about hostiles, and the decision just made already weighed what
	# the NPC knows. Re-take the key so it does not start another.
	if _salient_init:
		_salient_key = _behavior.salient_key()
	GameLog.say("%s (Von) %s  [%s]"
			% [_npc_name(), " - ".join(leaf["labels"]), _planner.walk_digest()])
	if tuning.radio.send_callouts and _character != null and not leaf["path"].is_empty() \
			and str(leaf["path"][0]) in ["combat", "investigate"]:
		_post_callout(leaf)


## Broadcast this NPC's decision as an `&"callout"` EventBus event (interface 10): who is speaking
## and where, its state, the decision path, its target and destination, and with a combat decision
## `target_pos` (where the hostile is as it knows it). Allies within range hear it.
func _post_callout(leaf: Dictionary) -> void:
	var params: Dictionary = leaf["params"]
	var status := _status(leaf["primitive"] == &"reload")
	_last_callout = {
		"position": _character.global_position,
		"point": params.get("point", _character.global_position),
		"label": " - ".join(leaf["labels"]), "at": GameClock.msec(),
	}
	var radio := _callout_header(
		", ".join(status), "/".join(leaf["path"]), " - ".join(leaf["labels"]),
		params.get("point", _character.global_position), params.get("target_id", 0),
	)
	if str(leaf["path"][0]) == "combat":
		# Where the hostile is, as the speaker knows it: an ally weighing the room it is in hears it
		# (docs/grenades.md G18).
		radio["target_pos"] = _perception.target_pos(params.get("target_id", 0))
	EventBus.post(&"callout", radio)


## Radio a live grenade the NPC has seen or heard come down (`{ point, kind }`) as an `&"grenade"`
## callout: the spot it landed at and its kind, for the allies in its danger zone who neither saw
## nor heard it (G16). `point` is the landing.
func _post_grenade_call(grenade: Dictionary) -> void:
	var label := "a %s grenade" % grenade["kind"]
	_last_callout = {
		"position": _character.global_position,
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
func _post_throw_call(throw: Dictionary) -> void:
	var status := "frag_out" if throw["kind"] == &"frag" else "bang_out"
	var label := "%s!" % status.replace("_", " ")
	_last_callout = {
		"position": _character.global_position,
		"point": throw["point"],
		"label": label,
		"at": GameClock.msec(),
	}
	var msg := _callout_header(status, _behavior.current_act(), label, throw["point"])
	msg["kind"] = throw["kind"]
	EventBus.post(&"callout", msg)


## Radio one step of a tactical entry (`claim`, in `StackClaim`'s fields, from the behaviour) as an
## `&"callout"`: the callout's header (`_callout_header`) and the claim's entry fields, every one
## encoded by `StackClaim.encode` (the doorway, slot, side and `entry_step`, the bang's mode and
## grenades, the frame and spot it was claimed on, a move-up, the pie, the order it stacks under, a
## join's mark: stack/stack_claim.gd `DEFAULTS`). It is how the stack claims slots, waits for the
## team and crosses in order; "going in" is also said in `status`. `point` is where the speaker
## stands.
func _post_entry_call(claim: Dictionary) -> void:
	var status := _status(false)
	if claim["entry_step"] == "going_in":
		status.push_front("going in")
	var labels: String = _behavior.path_label()
	_last_callout = {
		"position": _character.global_position, "point": _character.global_position,
		"label": "%s (%s)" % [labels, String(claim["entry_step"]).replace("_", " ")],
		"at": GameClock.msec(),
	}
	var msg := _callout_header(
		", ".join(status), _behavior.current_act(), labels, _character.global_position,
	)
	msg.merge(StackClaim.encode(claim))
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
	return {
		"speaker": _character,
		"faction": _character.faction,
		"position": _character.global_position,
		"status": status,
		"path": path,
		"label": label,
		"target_id": target_id,
		"point": point,
	}


## The speaker's state for a callout: under fire, wounded, reloading.
func _status(reloading: bool) -> Array:
	var status: Array = []
	if _perception.under_fire():
		status.append("under fire")
	var dmg: float = _character.damage_taken()
	if dmg >= tuning.context.critical_threshold:
		status.append("badly wounded")
	elif dmg >= tuning.context.hurt_threshold:
		status.append("hurt")
	if reloading or _character.ammo.is_reloading():
		status.append("reloading")
	return status


## The driven character's name, for log lines.
func _npc_name() -> String:
	return str(_character.name) if _character != null else "NPC"
