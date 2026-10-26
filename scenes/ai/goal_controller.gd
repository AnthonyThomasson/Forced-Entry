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
const DecisionPlanner := preload("res://scenes/ai/decision/decision_planner.gd")
## The frame's snapshot count (DecisionBudget).
const Budget := preload("res://scenes/ai/decision/decision_budget.gd")
const Behavior := preload("res://scenes/ai/behavior/behavior.gd")
## The decide cadence (`_cadence`).
const Cadence := preload("res://scenes/ai/npc_cadence.gd")
## The radio: the event intake and the NPC's own callouts (`_comms`).
const Comms := preload("res://scenes/ai/npc_comms.gd")
## The reflexes outside the decision walk: following, the grenade and the blind roll (`_reflexes`).
const Reflexes := preload("res://scenes/ai/npc_reflexes.gd")
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
## The tactical point an observer asked to highlight on the tactics overlay (the spectator
## inspector's clicked zone), or `Vector2.INF` for none. Debug only: it changes nothing the NPC
## does.
var debug_focus := Vector2.INF
## SENSE sub-domain: knowledge, the decision snapshot, combat geometry.
var _perception: Node
## THINK policy: the decision-tree walk (decision/decision_planner.gd), which owns the Von
## transport.
var _planner: Node
## ACT sub-domain: runs the chosen primitive + holds commitment state.
var _behavior: Node
## The character this controller drives, captured on first control.
var _character: Node
## The decide cadence: when the next decision is allowed, why one is forced, the walks started, the
## salient key and what the last snapshot held (npc_cadence.gd).
var _cadence: RefCounted
## The radio: the EventBus events queued for the perception, and the NPC's own callouts
## (npc_comms.gd).
var _comms: RefCounted
## The reflexes outside the decision walk: following the squad's leader, the grenade evade and the
## blind roll (npc_reflexes.gd).
var _reflexes: RefCounted


## Build the AI sub-domains and wire them together, then configure them from the tuning with
## _apply_config(). The sub-domains each own internal modules (perception's sight/hostility/memory/
## tactics, the behaviour's locomotion), so building and configuring are separate: _ready() builds
## once, _apply_config() configures (here and again each decision, so a tunable retuned at runtime
## still takes effect without a rebuild that would wipe memory or in-flight state).
func _ready() -> void:
	# The group the observers find an NPC's controller by (interface 7).
	add_to_group(&"npc_controllers")
	_cadence = Cadence.new()
	_comms = Comms.new(self)
	_reflexes = Reflexes.new(self)
	# SENSE: the perception sub-domain owns sight, hostility, memory and the combat geometry
	# internally.
	_perception = AgentPerception.new()
	add_child(_perception)
	_perception.setup()
	# THINK: the planner that walks the decision tree, through the Von transport it builds.
	# node_overrides is baked into the tree at setup() (construction-time only); the rest of the
	# planner's config is applied by _apply_config(), which turns the policy primitives into tree
	# config (pursuit starts at COMBAT once a hostile is known and never idles; territory keeps
	# combat options inside the house).
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
	_behavior.setup(_perception, nav_agent, tuning)
	_apply_config()
	_planner.setup(tuning.decision)
	_planner.decided.connect(_on_decided)
	_planner.failed.connect(_behavior.fallback)
	EventBus.posted.connect(_on_event)


## Configure the sub-domains from the tuning. The controller is the single authoring surface —
## every tunable lives in a topic node of its `tuning` — and this is where they reach the
## sub-modules: the perception takes the hub (`apply_config(tuning)`), reads its own tunables and
## the snapshot's live and sets its modules' from it, the behaviour and its modules read it live
## (handed in at `setup`) and take the squad (`apply_config(squad)`), and the planner's config is
## worked out here. It only SETS config on already-built sub-domains (never rebuilds), so it is safe
## to call each decision: a tunable retuned at runtime (e.g. by the dev command server for a
## behaviour test) takes effect on the next one.
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
	_planner.confines.inside_only = tuning.decision.defend_territory
	var held: Dictionary = _perception.orders.current()
	_planner.confines.room = (String(held.get("room", ""))
			if String(held.get("kind", "")) == "defend_room"
			else "")
	# A follower picks no goal of its own (LD20): it follows its leader after the fight and order
	# rules, and, holding no order, fights only within its leash of the leader (LD23).
	var lead: Node2D = _reflexes.leader_followed()
	if lead != null:
		for id in [&"investigate", &"search", &"idle"]:
			if not disabled.has(id):
				disabled.append(id)
		if not rules.has(&"follows") and not rules.has("follows"):
			rules[&"follows"] = &"follow"
	_planner.disabled_nodes = disabled
	_planner.entry_rules = rules
	var leash_lead: Node2D = _reflexes.leash_lead()
	var lead_at: Vector2 = leash_lead.global_position if leash_lead != null else Vector2.INF
	_planner.confines.leash_center = lead_at
	_planner.confines.leash = float(SquadFollowConfig.leash) if leash_lead != null else 0.0
	_behavior.apply_config(squad)


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
		_comms.event_queue.append([topic, data])
	elif (topic == &"footfall"
			and _character != null
			and _character.global_position.distance_to(data.get("position", Vector2.INF))
				<= _perception.hearing.footfall_reach()):
		_comms.event_queue.append([topic, data])


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
		"decide_in": _cadence.decide_timer,
		"forced": _cadence.forced,
		"decisions": _cadence.decisions,
		"decision_reason": _cadence.decision_reason,
		"facts": _cadence.last_facts,
		"sections": _cadence.last_sections,
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
	return ZoneList.from_options(_cadence.last_options)


## Read-only: the tactical ROOM zones — every room of the house tagged by how this NPC regards it
## now (`current` / `searched` / `unsearched` / `unknown`), each as a world-space `rect` with its
## `type`, for the tactics debug overlay to draw. It is the room reasoning the search / room / flank
## options are placed against. Empty until the controller knows its character. A pure read of the
## perception.
func debug_room_zones() -> Array:
	if _character == null or _perception == null:
		return []
	return _perception.house.room_status(rooms, _character.global_position)


## Read-only: the running tactical entry — the doorway (`opening`, `into`), the NPC's stack `slot`
## and `side`, whether it is going `solo`, its `phase`, what the pie saw (`seen_fraction`,
## `pie_sides`, `hidden_corners`), its `corner` and `stack_point`, as the behaviour reports it
## (typed values; `debug_state()["entry"]` is the JSON-safe copy). Empty when the NPC isn't entering
## a room.
func debug_entry() -> Dictionary:
	return _behavior.entries.debug() if _behavior != null else {}


## Read-only: the tactical entry and the entry guard as world-space data, for the entry debug
## overlays: `entry` (the doorway's slots, pie arc and corners, this NPC's role, timers, the team
## off the radio, the doorways it covers; {} when not entering) and `guard` (a running detour and
## the order it paused, the next uncleared doorway on the walk, the rooms regarded as cleared). See
## behavior_entries.gd `debug_view`.
func debug_entry_view() -> Dictionary:
	if _behavior == null or _character == null:
		return {}
	return _behavior.entries.debug_view()


## Read-only: the behaviour's running search-coverage state (which room sample points it has seen
## vs. still needs to, and the one it is looking at now), for the search debug overlay.
## Empty/inactive when the NPC isn't currently covering a room.
func debug_search_coverage() -> Dictionary:
	return _behavior.errand.debug_coverage() if _behavior != null else {}


## Read-only: where the NPC's sight toward world point `to` is first blocked (over low cover, the
## perception's own sight rule), or `to` when it reaches it — for the vision overlay, so it draws
## the area the sense really covers.
func debug_sight_end(to: Vector2) -> Vector2:
	if _perception == null or _character == null:
		return to
	return _perception.sight.sight_end(to)


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
	return _behavior.fight.debug_combat()


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
	return { "known": _perception.grenades.known(), "escape": _behavior.grenades.evade_spot(),
		"throw": _behavior.grenades.throw_plan() if _character != null else {} }


## Read-only: the last callout this NPC radioed (`position`, `point`, `label`, `at` msec), or empty.
func debug_sent_callout() -> Dictionary:
	return _comms.last_callout


## Read-only: the decision machinery's live state for the brain overlay — whether Von is being asked
## (`pending`), the last walk's levels (state, offered options, probabilities, pick), whether it
## failed (the behaviour then holds steady), the decide/force timers and why the last force fired,
## and the facts.
func debug_brain() -> Dictionary:
	if _planner == null:
		return {}
	var d: Dictionary = _planner.debug_state()
	var timers: Dictionary = (_behavior.fight.debug_combat().get("timers", {})
			if _character != null
			else {})
	return {
		"pending": d.get("pending", false),
		"failed": d.get("last_failed", false),
		"entry": d.get("entry", ""),
		"levels": d.get("levels", []),
		"decide_in": maxf(_cadence.decide_timer, 0.0),
		"decide_interval": tuning.decision.decide_interval,
		"forced": _cadence.forced,
		"force_reason": _cadence.force_reason,
		"force_age": ((GameClock.msec() - _cadence.force_ms) / 1000.0
				if _cadence.force_reason != ""
				else INF),
		"timers": timers,
		"facts": _cadence.last_facts,
	}


## Full contact data for display in the spectator inspector: each entry has `node`, `pos`
## (last-known world position), `name`, `hostile`, `visible` (seen this tick) and `age` (seconds
## since last seen).
func known_contacts_for_display() -> Array:
	if _character == null or _perception == null:
		return []
	return _perception.contacts.all_seen_characters(_character.global_position)


## The known-contacts list flattened to the fields worth reading in a snapshot (who, whether hostile
## and why, whether seen this tick, and how far off). Empty until the controller knows its
## character.
func _contact_digest() -> Array:
	if _character == null:
		return []
	var self_pos: Vector2 = _character.global_position
	var out: Array = []
	for c in _perception.contacts.known(self_pos):
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
	var due: bool = _cadence.due(delta)
	_sense(character, delta)
	# An active interaction holds the tick; when it or a move resolves, re-decide at once.
	if _behavior.errand.service_interaction(delta, _cadence.forced):
		return
	_take_resolved()
	_think(due)
	_act(delta)


## Takes `character` as the NPC's body on its first tick: seeds the reflexes' RNG from its name and
## spawn spot, hands it to the perception and the behaviour, and its name to the planner.
func _bind_body(character: Node) -> void:
	_character = character
	_reflexes.bind(character)
	_perception.bind(character)
	_behavior.bind(character)
	_planner.bind(_npc_name())


## SENSE: folds the queued events in, perceives, and lets the behaviour adopt the hostiles it knows
## (reconsidering at once when the engaged contact is lost) before the salient-event check.
func _sense(character: Node, delta: float) -> void:
	_comms.process_events()
	_reflexes.follow_squad()
	_perception.house.openings = openings
	_perception.observe(rooms)
	_reflexes.react_to_grenades()
	_behavior.rooms = rooms
	if entry_point != Vector2.ZERO:
		# Hand the injected entrance to the perception's house once.
		_perception.house.entry_point = entry_point
		entry_point = Vector2.ZERO
	var known: Array = _perception.contacts.known(character.global_position)
	if _behavior.update_known(known, delta):
		# Lost the engaged contact mid-fight → reconsider.
		_cadence.force("lost the engaged contact")
	_check_salient()


## A task the behaviour resolved forces a decision at once, with the reason it gives; a lead it
## reached is checked off.
func _take_resolved() -> void:
	var why: String = _behavior.task.resolve_reason
	if _behavior.task.take_resolved():
		_cadence.force(why if why != "" else "task resolved")
		var lead: String = _behavior.errand.reached_lead()
		if lead != "":
			_perception.check_lead(lead) # Reached it and found nothing: don't send it back there.


## THINK: restarts a decision walk a forced decision has overtaken, or starts one when free to
## (`due`: the decide cadence has elapsed).
func _think(due: bool) -> void:
	if _planner.is_pending():
		if _cadence.forced:
			_maybe_interrupt()
	elif _should_decide(due):
		_start_decision()


## ACT: the behaviour carries out the running primitive, then the entry turn, the entry and throw
## calls and the order's progress go out.
func _act(delta: float) -> void:
	_behavior.apply(delta)
	if _behavior.entries.take_turned():
		_comms.on_entry_turned()
	for claim in _behavior.entries.take_calls():
		if tuning.radio.send_callouts:
			_comms.post_entry_call(claim)
	for throw in _behavior.grenades.take_throw_calls():
		if tuning.radio.send_callouts:
			_comms.post_throw_call(throw)
	_comms.report_order()


## Whether a new decision may start now: never while crossing a doorway (a forced one waits until
## the NPC is through); always when forced; otherwise the behaviour decides whether its current
## commitment still holds (a fight, a move, an approach) or the decide cadence has elapsed. One that
## may must also get one of the frame's snapshots (`DecisionBudget`); refused, it keeps its wish
## (`forced`, the elapsed timer) and asks again next frame. `due`: the decide cadence has elapsed.
func _should_decide(due: bool) -> bool:
	if _behavior.committed() or _behavior.grenades.evading() or _character.stun.is_blind():
		# A blinded NPC starts no new decision (G15), one running from a grenade none until the
		# burst (G16).
		return false
	if not _cadence.forced and not _behavior.wants_decision(due):
		return false
	if not _cadence.forced and not _perception.views.routes_ready():
		# The routes it would weigh are still being measured (the avoid map is baking): a few
		# frames. A forced decision does not wait.
		return false
	return Budget.claim()


## A salient event arrived while a walk is in flight: restart the walk only when the situation now
## calls for a different starting node (e.g. it came under fire mid-way through choosing a room to
## search → straight to COMBAT). Otherwise the walk in flight already fits; let it finish.
func _maybe_interrupt() -> void:
	if _behavior.grenades.evading() or _character.stun.is_blind():
		return
	# An order taken since the walk in flight began always restarts it: that walk was made without
	# the order, and a walk the order replaces stands until one made with it lands.
	if (_cadence.order_from >= 0
			or _planner.entry_for(_perception.quick_facts()) != _planner.current_entry()):
		if Budget.claim():  # Else `forced` stays and the restart is tried again next frame.
			_start_decision()
	else:
		_cadence.forced = false


## Sense the situation and start a decision walk over it. The planner answers asynchronously via
## `decided` / `failed` (the latter wired to the behaviour's steady-stance fallback).
func _start_decision() -> void:
	_cadence.decisions += 1
	_cadence.decision_reason = _cadence.force_reason if _cadence.forced else "cadence"
	_cadence.forced = false
	_cadence.decide_timer = tuning.decision.decide_interval
	_apply_config()  # Pick up any tunable retuned at runtime before sensing + deciding.
	var snapshot: Dictionary = _perception.sense(rooms, goal, _behavior.activity_text())
	_cadence.last_facts = snapshot["facts"]
	_cadence.last_sections = snapshot["sections"]
	_cadence.last_options = snapshot["options"]
	var held: Dictionary = _perception.orders.current()
	if not held.is_empty() and (snapshot["options"]["order"]["options"] as Array).is_empty():
		# An order it cannot carry out (a room or doorway it does not know): said so, and dropped.
		_perception.orders.end(held["id"], "refused")
		_cadence.last_facts["ordered"] = false
		# `_apply_config` confined the walk to the order's room: the walk is the NPC's own now.
		_planner.confines.room = ""
	_planner.begin(snapshot, _behavior.ongoing())


## Force a re-decision when the NPC's BELIEF about hostiles changes: one is spotted, lost or newly
## categorized hostile, or the engaged contact crosses the house boundary (per its last sighting).
## These are the events worth interrupting a commitment for. The behaviour sub-domain packs that
## belief into a salient key; seeded on the first call so the initial state isn't a "change".
func _check_salient() -> void:
	var key: String = _behavior.salient_key()
	if not _cadence.salient_init:
		_cadence.salient_key = key
		_cadence.salient_init = true
		return
	if key != _cadence.salient_key:
		_cadence.salient_key = key
		_cadence.force("hostile belief changed")


## Adopt the planner's leaf: hand it to the behaviour, log the full decision path, and tell allies
## (a combat or investigation decision) over the radio.
func _on_decided(leaf: Dictionary) -> void:
	if _behavior.grenades.evading():
		return  # Overtaken by a grenade while Von was answering; the burst ends in a new decision.
	if _cadence.order_from >= 0 and _cadence.decisions <= _cadence.order_from:
		# A walk begun before the order came, which its restart superseded: the one made with the
		# order is on its way.
		return
	_cadence.order_from = -1
	_behavior.set_leaf(leaf)
	# The order just adopted sets (or clears) the engaged contact, which the salient key carries:
	# that is not a change of belief about hostiles, and the decision just made already weighed what
	# the NPC knows. Re-take the key so it does not start another.
	if _cadence.salient_init:
		_cadence.salient_key = _behavior.salient_key()
	GameLog.say("%s (Von) %s  [%s]"
			% [_npc_name(), " - ".join(leaf["labels"]), _planner.walk_digest()])
	if tuning.radio.send_callouts and _character != null and not leaf["path"].is_empty() \
			and str(leaf["path"][0]) in ["combat", "investigate"]:
		_comms.post_callout(leaf)


## The driven character's name, for log lines.
func _npc_name() -> String:
	return str(_character.name) if _character != null else "NPC"
