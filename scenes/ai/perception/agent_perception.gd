extends Node
## AI domain: perception/sensor for a goal-driven NPC. It has two halves. `observe()` is the SEE
## pass — run every tick, it tests what is currently visible (via the vision sense,
## agent_vision.gd), deposits sightings into the agent's memory (agent_memory.gd) — every other
## character (`saw_character`, with a smoothed movement track, its facing and raw hit-damage) and,
## for an NPC that must learn its surroundings, rooms and objects (`saw_room` / `saw_object`) —
## notes the rooms it has searched, and runs each character sighting through the hostility rules
## (agent_hostility.gd). `contacts.known()` is the resulting view: every character the agent knows
## of, hostile or not. `sense()` is the BUILD pass — run at the start of each decision, it gathers
## what the agent knows (contacts, callouts, learned house knowledge) and hands it to the SNAPSHOT
## AUTHOR (agent_snapshot.gd), which turns it into the SNAPSHOT the decision planner walks (facts /
## sections / option groups). The NPC knows only what it has perceived — sight, nearby hits, gunfire
## and footsteps within earshot, and its allies' radio callouts — and that knowledge decays as the
## memory does.
##
## This is the PERCEPTION sub-domain's public face: it OWNS the sight sense (agent_vision.gd), the
## hostility rules (agent_hostility.gd), the event memory (agent_memory.gd), the combat geometry
## (agent_tactics.gd), the doorway geometry (agent_entry.gd), the doorway views and the walk round
## them (agent_door_views.gd), the grenade geometry (agent_throw.gd), the live grenades known
## (agent_grenades.gd) and the snapshot author (agent_snapshot.gd) as internal modules, and surfaces
## knowledge only through its own methods and its parts (`sight`, `house`, `hearing`, `orders`,
## `contacts`, `grenades`, `entry`, `views`), each built once in `setup()` and holding it. It holds
## NO policy: it never decides, gates by goal or picks — and the measured wording Von reads lives in
## the snapshot author, not here. The controller calls `setup()` once, then hands it the NPC's
## tuning (`apply_config(tuning)`): the perception and the snapshot's vocabulary read their tunables
## live off the topic nodes (the single authoring surface), and it sets its modules' straight from
## them.

## The internal modules this sub-domain owns (built in setup() from the config fields).
const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
const AgentHostility := preload("res://scenes/ai/perception/agent_hostility.gd")
const AgentMemory := preload("res://scenes/ai/perception/agent_memory.gd")
const AgentTactics := preload("res://scenes/ai/perception/agent_tactics.gd")
const AgentEntry := preload("res://scenes/ai/perception/agent_entry.gd")
const AgentDoorViews := preload("res://scenes/ai/perception/agent_door_views.gd")
const AgentThrow := preload("res://scenes/ai/perception/agent_throw.gd")
const AgentGrenades := preload("res://scenes/ai/perception/agent_grenades.gd")
const AgentSuspicion := preload("res://scenes/ai/perception/agent_suspicion.gd")
## The parts (`sight`, `house`, `hearing`, `orders`, `contacts`, `grenades`, `entry`, `views`).
const PerceptionSight := preload("res://scenes/ai/perception/perception_sight.gd")
const PerceptionHouse := preload("res://scenes/ai/perception/perception_house.gd")
const PerceptionHearing := preload("res://scenes/ai/perception/perception_hearing.gd")
const PerceptionOrders := preload("res://scenes/ai/perception/perception_orders.gd")
const PerceptionContacts := preload("res://scenes/ai/perception/perception_contacts.gd")
const PerceptionGrenades := preload("res://scenes/ai/perception/perception_grenades.gd")
const PerceptionEntry := preload("res://scenes/ai/perception/perception_entry.gd")
const PerceptionViews := preload("res://scenes/ai/perception/perception_views.gd")
const PerceptionConfinement := preload("res://scenes/ai/perception/perception_confinement.gd")
## The entry claims heard on the radio (scenes/ai/perception/stack/).
const ClaimLedger := preload("res://scenes/ai/perception/stack/claim_ledger.gd")
## The BUILD half: turns what the NPC knows + the combat geometry into the decision snapshot Von
## walks.
const AgentSnapshot := preload("res://scenes/ai/perception/agent_snapshot.gd")
const HouseRooms := preload("res://scenes/ai/perception/house_rooms.gd")

## The NPC's tuning topics (`NpcTuning`), handed in by apply_config(): the tunables the perception
## reads itself, read live (`tuning.memory.contact_ttl`).
var tuning: NpcTuning
## Whether the NPC follows its squad's leader (`Squad.follows`), set each tick by the controller:
## the snapshot's and `quick_facts()`'s `follows`.
var follows := false
## The NPC's body, handed in once by bind().
var _character: Node
## The event memory; see agent_memory.gd.
var _memory: RefCounted
## The combat geometry; see agent_tactics.gd.
var _tactics: RefCounted
## The BUILD half: writes the decision snapshot; see agent_snapshot.gd.
var _snapshot: RefCounted
## What is in view, the tracks, the blind state and the sight cadence; see perception_sight.gd.
var sight: PerceptionSight
## What it knows of the house, its post, and learning by sight; see perception_house.gd.
var house: PerceptionHouse
## What it hears and is told; see perception_hearing.gd.
var hearing: PerceptionHearing
## The leader's order it holds; see perception_orders.gd.
var orders: PerceptionOrders
## The characters it knows of; see perception_contacts.gd.
var contacts: PerceptionContacts
## The grenades: what it carries and knows, and the plan to get clear; see perception_grenades.gd.
var grenades: PerceptionGrenades
## The doorway geometry and the entry claims heard; see perception_entry.gd.
var entry: PerceptionEntry
## The doorway views and the walk that keeps out of them; see perception_views.gd.
var views: PerceptionViews
## Where it may act (its territory, the room it defends, its leash), refreshed each tick by the
## controller; see perception_confinement.gd.
var confinement: PerceptionConfinement


## Build the owned sensing modules. The controller calls this once in its _ready(); it then hands
## its tuning to apply_config(), which sets the modules' tunables (here, and again each decision so
## a runtime retune takes effect). Building and configuring are separate so apply_config() never
## rebuilds a module — that would wipe the event memory and the sight state.
func setup() -> void:
	sight = PerceptionSight.new(self)
	house = PerceptionHouse.new(self)
	sight.vision = AgentVision.new()
	hearing = PerceptionHearing.new(self)
	orders = PerceptionOrders.new(self)
	contacts = PerceptionContacts.new(self)
	grenades = PerceptionGrenades.new(self)
	entry = PerceptionEntry.new(self)
	views = PerceptionViews.new(self)
	confinement = PerceptionConfinement.new()
	contacts.hostility = AgentHostility.new()
	_memory = AgentMemory.new()
	_tactics = AgentTactics.new()
	_tactics.vision = sight.vision
	views.views = AgentDoorViews.new()
	views.views.vision = sight.vision
	entry.doorways = AgentEntry.new()
	entry.doorways.vision = sight.vision
	entry.doorways.views = views.views
	grenades.throw = AgentThrow.new()
	grenades.throw.vision = sight.vision
	grenades.live = AgentGrenades.new()
	grenades.live.setup(grenades.throw)
	hearing.suspicion = AgentSuspicion.new()
	hearing.suspicion.memory = _memory
	hearing.suspicion.entry = entry.doorways
	entry.ledger = ClaimLedger.new()
	_snapshot = AgentSnapshot.new()
	var sources := SnapshotSources.new()
	sources.memory = _memory
	sources.tactics = _tactics
	sources.entry = entry.doorways
	sources.views = views.views
	sources.throw = grenades.throw
	sources.suspicion = hearing.suspicion
	sources.ledger = entry.ledger
	_snapshot.setup(sources)


## Hand the perception the NPC's tuning topics (`npc_tuning`, the one authoring surface), which it
## and the snapshot's vocabulary read live, and set its modules' tunables straight from them.
## Idempotent and state-free (it only sets tunables, never the memory log or hostility faction), so
## the controller may call it every decision to keep the modules in step with a tunable retuned at
## runtime (e.g. by the dev command server).
func apply_config(npc_tuning: NpcTuning) -> void:
	tuning = npc_tuning
	entry.ledger.setup({
		"range": npc_tuning.radio.callout_range,
		"ttl": npc_tuning.radio.callout_ttl,
	})
	_apply_senses(npc_tuning)
	_apply_tactics(npc_tuning)
	_apply_doorways(npc_tuning)
	grenades.throw.evade_margin = npc_tuning.grenades.evade_margin
	grenades.live.enabled = npc_tuning.grenades.enabled
	grenades.live.hear_grenade = npc_tuning.grenades.hear_grenade
	hearing.suspicion.still_speed = npc_tuning.context.still_speed
	hearing.suspicion.extrapolate_cap = npc_tuning.context.extrapolate_cap
	_snapshot.vocab.tuning = npc_tuning


## Set the sight sense's, the hostility rules' and the memory's tunables from `npc_tuning`.
func _apply_senses(npc_tuning: NpcTuning) -> void:
	sight.vision.enabled = npc_tuning.senses.vision_enabled
	sight.vision.view_distance = npc_tuning.senses.view_distance
	sight.vision.fov_degrees = npc_tuning.senses.fov_degrees
	sight.vision.awareness_radius = npc_tuning.senses.awareness_radius
	sight.vision.see_over_coverage = npc_tuning.senses.see_over_coverage
	contacts.hostility.on_sight = npc_tuning.hostility.on_sight
	contacts.hostility.trespass = npc_tuning.hostility.on_trespass
	contacts.hostility.retaliate = npc_tuning.hostility.on_attack
	contacts.hostility.ttl = npc_tuning.hostility.ttl
	_memory.capacity = npc_tuning.memory.capacity


## Set the combat geometry's tunables from `npc_tuning`.
func _apply_tactics(npc_tuning: NpcTuning) -> void:
	_tactics.cover_min = npc_tuning.tactics.cover_min
	_tactics.flank_distance = npc_tuning.tactics.flank_distance
	_tactics.flank_arc = npc_tuning.tactics.flank_arc
	_tactics.flank_ally_radius = npc_tuning.tactics.flank_ally_radius
	_tactics.shoot_range = npc_tuning.combat.shoot_range
	_tactics.combat_ring_radius = npc_tuning.combat.ring_radius
	_tactics.combat_ring_count = npc_tuning.combat.ring_count
	_tactics.still_speed = npc_tuning.context.still_speed
	_tactics.route_clearance = npc_tuning.tactics.route_clearance
	_tactics.watch_arc = npc_tuning.tactics.watch_arc
	_tactics.fire_spot_distances = npc_tuning.tactics.fire_spot_distances
	_tactics.throw_spot_walk = npc_tuning.grenades.throw_spot_walk


## Set the doorway geometry's and the doorway views' tunables from `npc_tuning`, then push the walk
## rules into the views (`views.sync_walks`).
func _apply_doorways(npc_tuning: NpcTuning) -> void:
	entry.doorways.stack_spacing = npc_tuning.entry_geometry.stack_spacing
	entry.doorways.wall_standoff = npc_tuning.entry_geometry.wall_standoff
	entry.doorways.pie_radius = npc_tuning.entry_geometry.pie_radius
	entry.doorways.pie_steps = npc_tuning.entry_geometry.pie_steps
	entry.doorways.corner_inset = npc_tuning.entry_geometry.corner_inset
	entry.doorways.short_room = npc_tuning.entry_geometry.short_room
	views.views.door_view_depth = npc_tuning.entry_guard.door_view_depth
	views.views.door_avoid_ratio = npc_tuning.entry_guard.door_avoid_ratio
	views.views.door_avoid_slack = npc_tuning.entry_guard.door_avoid_slack
	views.sync_walks()


## Hand the perception the NPC's body, which every sense and query reads from then on, and tell the
## hostility rules its faction (so allies are never hostile). The controller calls this once it
## knows which character it drives.
func bind(character: Node) -> void:
	_character = character
	contacts.hostility.faction = character.faction
	entry.ledger.setup({ "faction": character.faction, "listener": character })
	grenades.throw.bind(character)
	grenades.live.bind(character)
	entry.doorways.posts.crouch = character.movement.posture_coverage(&"crouch")
	entry.doorways.posts.body = character
	_snapshot.bind(character)


## Refresh the combat engagement (called by the behaviour when it fires or adopts a fight), so an
## active firefight stays committed between decisions.
func note_engaged() -> void:
	_memory.remember(&"engaged", {}, tuning.combat.engage_dwell, "latest")


## Whether the NPC is still committed to a fight (an `engaged` event is fresh).
func engaged_fresh() -> bool:
	return _memory.engaged()


## Whether the NPC is currently under fire (a recent incoming/nearby hit).
func under_fire() -> bool:
	return _memory.under_fire()


## The cheap facts the controller needs between decisions (e.g. to see whether a new situation
## should interrupt the decision in flight), without building the whole snapshot.
func quick_facts() -> Dictionary:
	var hostile_known := contacts.known(_character.global_position).any(
		func(c): return c["hostile"]
	)
	return {
		"under_fire": under_fire(),
		"engaged": engaged_fresh(),
		"hostile_known": hostile_known,
		"threat_known": hostile_known or under_fire(),
		"ordered": not orders.current().is_empty(),
		"follows": follows,
	}


## The NPC reached investigation lead `lead_id` (its option carried the id in `params.lead`):
## remember it as checked, so it isn't offered again until something newer happens there.
func check_lead(lead_id: String) -> void:
	_memory.remember(&"checked_lead", { "id": lead_id }, tuning.memory.lead_ttl, lead_id)


## Number of events in memory, for the debug snapshot.
func memory_size() -> int:
	return _memory.size()


## Debug read: what the NPC has heard and been told, for the hearing/contacts overlays — gunfire
## heard (`pos`, `age`), footsteps heard (`footsteps`: `pos`, `age`), where shots at it came from
## (`shot_from`: `pos` the end of the line back, `at` where the shot landed, `age`), the live
## under-fire event (`from` direction, `hit`, seconds `left`), ally callouts heard (`pos`, `point`,
## `label`, `name`, `age`), checked leads, the hostiles it has lost track of, and the
## hearing/awareness radii. A pure read of memory; never writes it.
func debug_memory() -> Dictionary:
	var gunfire := hearing.heard_points(&"heard_gunfire")
	var footsteps := hearing.heard_points(&"heard_footsteps")
	var shot_from: Array = []
	for rec in _memory.recall_aged(&"shot_from"):
		shot_from.append({
			"pos": rec["data"].get("pos", Vector2.ZERO),
			"at": rec["data"].get("at", Vector2.ZERO),
			"age": rec["age"],
		})
	var fresh := _debug_fresh()
	var callouts: Array = []
	for c in hearing.callouts():
		callouts.append({
			"name": c["name"], "age": c["age"], "label": c.get("label", ""),
			"pos": c.get("position", Vector2.ZERO), "point": c.get("point", Vector2.ZERO),
		})
	var lost: Array = []
	for c in contacts.lost_hostiles():
		lost.append({
			"pos": c["pos"],
			"vel": c.get("vel", Vector2.ZERO),
			"age": c["age"],
			"name": c["name"],
		})
	return {
		"gunfire": gunfire,
		"footsteps": footsteps,
		"shot_from": shot_from,
		"under_fire": fresh["under_fire"],
		"callouts": callouts,
		"checked_leads": fresh["checked_leads"],
		"lost": lost,
		"hearing_radius": tuning.senses.hearing_radius,
		"hit_awareness_radius": tuning.combat.hit_awareness_radius,
		"callout_range": tuning.radio.callout_range,
		"contact_memory_ttl": tuning.memory.contact_ttl,
		"lead_memory_ttl": tuning.memory.lead_ttl,
		"extrapolate_cap": hearing.suspicion.extrapolate_cap,
	}


## Debug read of the live events: the newest under-fire event (`under_fire`: `from` direction,
## `hit`, seconds `left`; {} with none) and the ids of the checked leads (`checked_leads`).
func _debug_fresh() -> Dictionary:
	var now := GameClock.msec()
	var under := {}
	var checked: Array = []
	for e in _memory.fresh():
		if e["topic"] == &"under_fire" and under.is_empty():
			var left: float = (maxf((e["ttl"] - (now - e["at"]) / 1000.0), 0.0)
					if e["ttl"] > 0.0
					else 0.0)
			under = {
				"from": e["data"].get("from", Vector2.ZERO),
				"hit": e["data"].get("hit", false),
				"left": left,
			}
		elif e["topic"] == &"checked_lead":
			checked.append(str(e["data"].get("id", "")))
	return { "under_fire": under, "checked_leads": checked }


# --- SEE -------------------------------------------------------------------------------------


## SEE pass — run every tick. Test what is visible via `vision` and remember it, so the agent's
## knowledge stays fresh while it can see and decays once it can't; each character sighting is also
## categorized by `hostility`. A familiar NPC's house knowledge is seeded on the first call. People
## are never seeded — they are known only once seen.
func observe(rooms: Array) -> void:
	house.take_in(rooms)
	confinement.rooms = rooms
	var self_pos: Vector2 = _character.global_position
	var space: PhysicsDirectSpaceState2D = _character.get_world_2d().direct_space_state
	var exclude := [_character.get_rid()]
	sight.see(rooms)

	# The room the NPC stands in counts as searched (superseded while it stays there).
	var here := HouseRooms.at(self_pos, rooms)
	if not here.is_empty():
		_memory.remember(
			&"visited_room",
			{ "key": here["key"] },
			tuning.memory.search_ttl,
			str(here["key"]),
		)

	grenades.live.observe(sight.vision, space, exclude, sight.blind)
	if (not tuning.memory.familiar_with_house
			and not sight.blind
			and Engine.get_physics_frames() >= house.learn_next):
		house.learn_by_sight()
	orders.end_ambush_on_contact()


# --- BUILD (delegated to the snapshot author) ------------------------------------------------


## BUILD pass — run at the start of each decision. Gather what the NPC currently knows (contacts,
## allies' callouts, learned house knowledge, lost hostiles) and hand it, with the goal and the
## behaviour's current-activity line, to the snapshot author (agent_snapshot.gd), which turns it
## into the decision snapshot the planner walks: { facts, sections, sections_per_target, options },
## with a frozen copy of its `confinement`.
## The author reads this knowledge and the combat geometry only — it writes no memory and holds no
## policy.
func sense(goal: String, activity: String) -> Dictionary:
	if not tuning.memory.familiar_with_house and not _character.stun.is_blind():
		house.learn_by_sight()
	var self_pos: Vector2 = _character.global_position
	var carried := PerceptionGrenades.carried(_character)
	var knowledge := {
		"known_rooms": house.known_rooms(),
		"known_room_keys": house.known_room_keys(),
		"known_object_ids": house.known_object_ids(),
		"interactables": house.interactables,
		"post": house.post,
		"entry_point": house.entry_point,
		"entry_enabled": tuning.entry.enabled,
		"lost": contacts.lost_hostiles(),
		# The kinds of grenade it holds, and the bodies a throw's line goes through.
		"carried_grenades": carried,
		"character_rids": grenades.character_rids() if not carried.is_empty() else [],
		"order": orders.current(),
		"follows": follows,
	}
	knowledge["contacts"] = contacts.known(self_pos)
	knowledge["callouts"] = hearing.callouts()
	var snapshot: Dictionary = _snapshot.build(house.rooms, goal, activity, knowledge)
	# The walk decides over where it may act as it is now, whatever a later tick refreshes.
	snapshot["confinement"] = confinement.copy()
	return snapshot


## The goal text as Von reads it: `{gun}` filled with what the NPC calls its gun.
func fill_goal(goal: String) -> String:
	return _snapshot.fill_goal(goal)


# --- Combat geometry for the behaviour -------------------------------------------------------


## Whether the NPC has a clear line (no wall or solid furniture between) to a world `point` — the
## engaged contact's last-known position. The behaviour gates FIRING on this: once a contact is
## known, the NPC shoots when it has a clear line to where it knows they are, independent of its
## view cone. Both the NPC and `target` (the contact's body) are excluded, so the target doesn't
## block itself.
func has_line_to(target: Node2D, point: Vector2) -> bool:
	var space: PhysicsDirectSpaceState2D = _character.get_world_2d().direct_space_state
	var exclude := [_character.get_rid()]
	if target != null and is_instance_valid(target):
		exclude.append(target.get_rid())
	return not _tactics.blocked(space, _character.global_position, point, exclude)


## Candidate standing points on a ring around the NPC, classified for peek-and-cover against the
## engaged contact's KNOWN position `tgt_pos`: `fire` points have a clear line to it; `cover` points
## are shielded from it by a high-coverage solid. Both nearest-first (see agent_tactics.gd); the
## ring has `combat_ring_count` points.
func combat_spots(target: Node2D, tgt_pos: Vector2, radius: float) -> Dictionary:
	var exclude := [_character.get_rid()]
	if target != null and is_instance_valid(target):
		exclude.append(target.get_rid())
	var space: PhysicsDirectSpaceState2D = _character.get_world_2d().direct_space_state
	return _tactics.combat_spots(space, _character.global_position, tgt_pos, exclude, radius)
