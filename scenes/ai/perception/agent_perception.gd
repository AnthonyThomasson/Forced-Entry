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
## knowledge only through its own methods and its parts (`hearing`, `orders`, `contacts`,
## `grenades`), each built once in `setup()` and holding it. It holds NO policy: it never decides,
## gates by goal or picks — and the measured wording Von reads lives in the snapshot author, not
## here. The controller calls `setup()` once, then hands it the NPC's tuning
## (`apply_config(tuning)`): the perception and the snapshot's vocabulary read their tunables live
## off the topic nodes (the single authoring surface), and it sets its modules' straight from them.

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
## The parts (`hearing`, `orders`, `contacts`, `grenades`).
const PerceptionHearing := preload("res://scenes/ai/perception/perception_hearing.gd")
const PerceptionOrders := preload("res://scenes/ai/perception/perception_orders.gd")
const PerceptionContacts := preload("res://scenes/ai/perception/perception_contacts.gd")
const PerceptionGrenades := preload("res://scenes/ai/perception/perception_grenades.gd")
## The entry claims heard on the radio, and their wire format (scenes/ai/perception/stack/).
const ClaimLedger := preload("res://scenes/ai/perception/stack/claim_ledger.gd")
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
## The BUILD half: turns what the NPC knows + the combat geometry into the decision snapshot Von
## walks.
const AgentSnapshot := preload("res://scenes/ai/perception/agent_snapshot.gd")
const HouseRooms := preload("res://scenes/ai/perception/house_rooms.gd")
## Physics frames between an unfamiliar NPC's looks for rooms and furniture it does not know yet.
## Learning is permanent and a decision looks again first, so a glimpse shorter than this still
## counts when it is the moment of a decision.
const LEARN_EVERY_FRAMES := 6
## Physics frames between two sight tests of a character that stays inside an NPC's view cone. The
## range and cone test runs every frame, so one that enters the cone is tested at once and one that
## leaves it is dropped at once; only the line of sight and the sighting written from it are renewed
## this often, offset per NPC and target so a squad does not test on the same frame. What the NPC
## holds of a character it sees is at most this many frames old.
const SIGHT_EVERY_FRAMES := 3
## The longest (game ms, `GameClock`) a decision waits for the avoid map its routes are measured on
## (`routes_ready`).
const WARM_CAP_MS := 3000

## The house entrance in world space (injected by its composer for an invader), offered while
## outside.
var entry_point: Vector2 = Vector2.ZERO
## The house's doorways (`WorldGen.get_openings`, injected by its composer), for tactical entry.
var openings: Array = []
## The NPC's tuning topics (`NpcTuning`), handed in by apply_config(): the tunables the perception
## reads itself, read live (`tuning.memory.contact_ttl`).
var tuning: NpcTuning
## Whether the NPC is walking an ordered stack's way to its door (`docs/leadership.md` LD9), set
## each tick by the behaviour: that walk keeps out of the doorway views whatever
## `tuning.entry.enabled` says (D4), and for an NPC that does not clear rooms by entry
## (`tuning.entry.enabled` off) a room it has stood in lately and seen no hostile in counts as clear
## for passing (`_seen_empty`, D11); the room its stack holds always does (`_stack_room`).
var ordered_walk := false:
	set(value):
		if value != ordered_walk:
			ordered_walk = value
			_sync_walks()
## Whether the NPC follows its squad's leader (`Squad.follows`), set each tick by the controller:
## the snapshot's and `quick_facts()`'s `follows`.
var follows := false
## `_stack_room()` this frame...
var _held_room := ""
## ... worked out on this physics frame.
var _held_room_frame := -1
## The NPC's body, handed in once by bind().
var _character: Node
## The sight sense (FOV/range/LoS); see agent_vision.gd.
var _vision: RefCounted
## The event memory; see agent_memory.gd.
var _memory: RefCounted
## The combat geometry; see agent_tactics.gd.
var _tactics: RefCounted
## The doorway geometry; see agent_entry.gd.
var _entry: RefCounted
## The allies' entry claims heard on the radio; see stack/claim_ledger.gd.
var _ledger: RefCounted
## The doorway views and the walk that keeps out of them; see agent_door_views.gd.
var _views: RefCounted
## When (`GameClock.msec()`) the decision began waiting for the avoid map; -1: not waiting.
var _warming_since := -1
## The BUILD half: writes the decision snapshot; see agent_snapshot.gd.
var _snapshot: RefCounted
## The house's rooms, as handed to the latest observe().
var _rooms: Array = []
## The NPC's spawn position, captured on the first observe() call.
var _post := Vector2.ZERO
## Whether _post has been captured yet.
var _post_set := false
## Cached world objects that advertise interactions (static furniture).
var _interactables: Array = []
## Whether the one-time interactable scan has run.
var _scanned := false
## Whether the familiar-NPC house-knowledge seed has run.
var _seeded := false
## First physics frame the next look for unknown rooms and furniture may run.
var _learn_next := 0
## Physics frame of the latest such look (-1 = none yet).
var _learned_frame := -1
## Instance ids of characters visible on the latest observe() tick.
var _visible_now := {}
## The same one tick earlier (what a character not due for a sight test keeps).
var _visible_before := {}
## Instance ids of characters in the view cone that have had a sight test since they entered it.
var _looked := {}
## Per-character movement track: id → { pos, vel, t, f } (last seen, game msec and game frame).
var _tracks := {}
## The NPC was flash-blinded on the latest observe() tick: it sees nothing new.
var _blind := false
## What it hears and is told; see perception_hearing.gd.
var hearing: PerceptionHearing
## The leader's order it holds; see perception_orders.gd.
var orders: PerceptionOrders
## The characters it knows of; see perception_contacts.gd.
var contacts: PerceptionContacts
## The grenades: what it carries and knows, and the plan to get clear; see perception_grenades.gd.
var grenades: PerceptionGrenades


## Build the owned sensing modules. The controller calls this once in its _ready(); it then hands
## its tuning to apply_config(), which sets the modules' tunables (here, and again each decision so
## a runtime retune takes effect). Building and configuring are separate so apply_config() never
## rebuilds a module — that would wipe the event memory and the sight state.
func setup() -> void:
	_vision = AgentVision.new()
	hearing = PerceptionHearing.new(self)
	orders = PerceptionOrders.new(self)
	contacts = PerceptionContacts.new(self)
	grenades = PerceptionGrenades.new(self)
	contacts.hostility = AgentHostility.new()
	_memory = AgentMemory.new()
	_tactics = AgentTactics.new()
	_tactics.vision = _vision
	_views = AgentDoorViews.new()
	_views.vision = _vision
	_entry = AgentEntry.new()
	_entry.vision = _vision
	_entry.views = _views
	grenades.throw = AgentThrow.new()
	grenades.throw.vision = _vision
	grenades.live = AgentGrenades.new()
	grenades.live.setup(grenades.throw)
	hearing.suspicion = AgentSuspicion.new()
	hearing.suspicion.memory = _memory
	hearing.suspicion.entry = _entry
	_ledger = ClaimLedger.new()
	_snapshot = AgentSnapshot.new()
	var sources := SnapshotSources.new()
	sources.memory = _memory
	sources.tactics = _tactics
	sources.entry = _entry
	sources.views = _views
	sources.throw = grenades.throw
	sources.suspicion = hearing.suspicion
	sources.ledger = _ledger
	_snapshot.setup(sources)


## Hand the perception the NPC's tuning topics (`npc_tuning`, the one authoring surface), which it
## and the snapshot's vocabulary read live, and set its modules' tunables straight from them.
## Idempotent and state-free (it only sets tunables, never the memory log or hostility faction), so
## the controller may call it every decision to keep the modules in step with a tunable retuned at
## runtime (e.g. by the dev command server).
func apply_config(npc_tuning: NpcTuning) -> void:
	tuning = npc_tuning
	_ledger.setup({ "range": npc_tuning.radio.callout_range, "ttl": npc_tuning.radio.callout_ttl })
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
	_vision.enabled = npc_tuning.senses.vision_enabled
	_vision.view_distance = npc_tuning.senses.view_distance
	_vision.fov_degrees = npc_tuning.senses.fov_degrees
	_vision.awareness_radius = npc_tuning.senses.awareness_radius
	_vision.see_over_coverage = npc_tuning.senses.see_over_coverage
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
## rules into the views (`_sync_walks`).
func _apply_doorways(npc_tuning: NpcTuning) -> void:
	_entry.stack_spacing = npc_tuning.entry_geometry.stack_spacing
	_entry.wall_standoff = npc_tuning.entry_geometry.wall_standoff
	_entry.pie_radius = npc_tuning.entry_geometry.pie_radius
	_entry.pie_steps = npc_tuning.entry_geometry.pie_steps
	_entry.corner_inset = npc_tuning.entry_geometry.corner_inset
	_entry.short_room = npc_tuning.entry_geometry.short_room
	_views.door_view_depth = npc_tuning.entry_guard.door_view_depth
	_views.door_avoid_ratio = npc_tuning.entry_guard.door_avoid_ratio
	_views.door_avoid_slack = npc_tuning.entry_guard.door_avoid_slack
	_sync_walks()


## Push the walk rules into the doorway views: walks keep out of the doorway views where the entry
## guard runs (`tuning.entry_guard.enabled`, with `tuning.entry.enabled` or on an ordered stack's
## walk, D4), and a room counts as clear for passing when it was cleared lately (`_is_pass_clear`)
## or, on an ordered walk, when its stack holds it (`_stack_room`) or, for an NPC that does not
## clear rooms by entry, it has seen it empty (`_seen_empty`, D11).
func _sync_walks() -> void:
	if _views == null:
		return
	_views.avoid_views = tuning.entry_guard.enabled and (tuning.entry.enabled or ordered_walk)
	# Its way round the room it stacks on is taken however long (D4).
	_views.ordered_approach = ordered_walk
	_views.pass_clear = ((_passable if not tuning.entry.enabled else _pass_clear_ordered)
			if ordered_walk
			else _is_pass_clear)


## Hand the perception the NPC's body, which every sense and query reads from then on, and tell the
## hostility rules its faction (so allies are never hostile). The controller calls this once it
## knows which character it drives.
func bind(character: Node) -> void:
	_character = character
	contacts.hostility.faction = character.faction
	_ledger.setup({ "faction": character.faction, "listener": character })
	grenades.throw.bind(character)
	grenades.live.bind(character)
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


## Debug read: every room tagged by how this NPC regards it right now — the one it stands in
## (`current`), a room it has seen and searched recently (`searched`) or seen but not searched
## (`unsearched`), or one it has not yet seen at all (`unknown`). This is the room reasoning the
## search/room/flank options are placed against, exposed for the tactics debug overlay to draw as
## zones. A pure read of knowledge + the visited-room memory; never perturbs it.
func room_status(rooms: Array, self_pos: Vector2) -> Array:
	var known := _known_room_keys()
	var here := HouseRooms.at(self_pos, rooms)
	var out: Array = []
	for room in rooms:
		var status: StringName
		if not here.is_empty() and room["key"] == here["key"]:
			status = &"current"
		elif not known.has(room["key"]):
			status = &"unknown"
		elif _memory.age_of(&"visited_room", "key", room["key"]) > tuning.memory.search_ttl:
			status = &"unsearched"
		else:
			status = &"searched"
		out.append({
			"rect": room["rect"],
			"type": str(room["type"]).replace("_", " "),
			"status": status,
		})
	return out


# --- SEE -------------------------------------------------------------------------------------


## SEE pass — run every tick. Test what is visible via `vision` and remember it, so the agent's
## knowledge stays fresh while it can see and decays once it can't; each character sighting is also
## categorized by `hostility`. A familiar NPC's house knowledge is seeded on the first call. People
## are never seeded — they are known only once seen.
func observe(rooms: Array) -> void:
	_take_in_house(rooms)
	var self_pos: Vector2 = _character.global_position
	var space: PhysicsDirectSpaceState2D = _character.get_world_2d().direct_space_state
	var exclude := [_character.get_rid()]
	_see_characters(rooms)

	# The room the NPC stands in counts as searched (superseded while it stays there).
	var here := HouseRooms.at(self_pos, rooms)
	if not here.is_empty():
		_memory.remember(
			&"visited_room",
			{ "key": here["key"] },
			tuning.memory.search_ttl,
			str(here["key"]),
		)

	grenades.live.observe(_vision, space, exclude, _blind)
	if (not tuning.memory.familiar_with_house
			and not _blind
			and Engine.get_physics_frames() >= _learn_next):
		_learn_by_sight(rooms)
	orders.end_ambush_on_contact()


## Before a look: capture the NPC's post on the first call, scan the interactables once, learn the
## grenades carried and the body's heights, seed a familiar NPC's house knowledge, hand the house to
## the doorway geometry (laying the doorways ahead while `tuning.entry.enabled`) and keep `rooms`.
func _take_in_house(rooms: Array) -> void:
	if not _post_set:
		_post = _character.global_position
		_post_set = true
	_ensure_interactables()
	grenades.throw.learn_carried()
	grenades.throw.learn_body()
	_seed_house(rooms)
	_entry.set_house(openings, rooms)
	if tuning.entry.enabled:
		var world: World2D = _character.get_world_2d()
		# Lay the doorways before a decision needs them.
		_entry.warm_geometry(world.navigation_map, world.direct_space_state)
	_rooms = rooms


## Every other character (the player included): one sighting per character, superseded while it
## stays visible. Dead characters are skipped — corpses add no tactical information. A
## flash-blinded NPC (G15) sees nothing: no new sighting, and nothing is visible, so what it holds
## stays where it was last seen.
func _see_characters(rooms: Array) -> void:
	var self_pos: Vector2 = _character.global_position
	var facing: Vector2 = _character.facing
	var space: PhysicsDirectSpaceState2D = _character.get_world_2d().direct_space_state
	var exclude := [_character.get_rid()]
	var now := GameClock.msec()
	var frame := Engine.get_physics_frames()
	var swap := _visible_before
	_visible_before = _visible_now
	_visible_now = swap
	_visible_now.clear()
	_blind = _character.stun.is_blind()
	if _blind:
		_looked.clear()
	for other in (_other_characters() if not _blind else []):
		if not _due_for_sight(other, self_pos, facing, frame):
			continue
		if not _vision.can_see_node(other, self_pos, facing, space, exclude):
			continue
		var sighting := _sighting_of(other, rooms, now)
		_visible_now[sighting["id"]] = true
		_memory.remember(
			&"saw_character",
			sighting,
			maxf(tuning.memory.contact_ttl, tuning.memory.lead_ttl),
			str(sighting["id"]),
		)
		contacts.hostility.classify(sighting, _memory)


## Whether character `other` gets a sight test on physics frame `frame`, keeping the view-cone
## bookkeeping: a dead one or one out of the cone is dropped (its next look is at once); one tested
## since it entered the cone is tested again every `SIGHT_EVERY_FRAMES` frames, offset per NPC and
## target, and until then stays what the last look saw.
func _due_for_sight(other: Node, self_pos: Vector2, facing: Vector2, frame: int) -> bool:
	var id: int = other.get_instance_id()
	if other.get("is_dead") == true:
		_looked.erase(id)
		return false
	if not _vision.in_view(self_pos, facing, other.global_position):
		_looked.erase(id)  # Out of the cone: not seen, and its next look is at once.
		return false
	if _looked.has(id) and (frame + get_instance_id() + id) % SIGHT_EVERY_FRAMES != 0:
		if _visible_before.has(id):
			_visible_now[id] = true  # Not due: still what the last look saw.
		return false
	_looked[id] = true
	return true


## The sighting of character `other`, seen now (game msec `now`): where it is and its movement
## track, its facing, visible wounds, room, held item, reload and posture.
func _sighting_of(other: Node, rooms: Array, now: int) -> Dictionary:
	var id: int = other.get_instance_id()
	var pos: Vector2 = other.global_position
	var room := HouseRooms.at(pos, rooms)
	var item = other.inventory.current_item()
	var f = other.get("faction")
	return {
		"id": id,
		"node": other,
		"name": str(other.name),
		"faction": f if f != null else &"",
		"ally": contacts.hostility.is_ally(f if f != null else &""),
		"pos": pos,
		"vel": _track(id, pos, now),
		"facing": other.get("facing") if other.get("facing") is Vector2 else Vector2.ZERO,
		"wound_dmg": other.damage_taken(),
		"inside": not room.is_empty(),
		"room_type": room.get("type", "") if not room.is_empty() else "",
		"item": item.display_name if item != null else "nothing",
		"reloading": other.ammo.is_reloading(),
		"posture": other.movement.posture(),
	}


## An unfamiliar NPC learns the rooms and objects it can see (permanent once learned). Runs every
## `LEARN_EVERY_FRAMES` frames from `observe()`, offset per NPC so a squad does not look on the same
## frame, and at the start of every decision, so what it knows when it decides is what it sees at
## that moment.
func _learn_by_sight(rooms: Array) -> void:
	var frame := Engine.get_physics_frames()
	if frame == _learned_frame:
		return
	_learn_next = frame + (LEARN_EVERY_FRAMES
			if _learned_frame >= 0
			else 1 + get_instance_id() % LEARN_EVERY_FRAMES)
	_learned_frame = frame
	var self_pos: Vector2 = _character.global_position
	var facing: Vector2 = _character.facing
	var space: PhysicsDirectSpaceState2D = _character.get_world_2d().direct_space_state
	var exclude := [_character.get_rid()]
	# Read once: what is learned here is permanent and only grows.
	var known_rooms := _known_room_keys()
	for room in rooms:
		if known_rooms.has(room["key"]):
			continue  # Already learned: looking again would change nothing.
		var rect: Rect2 = room["rect"]
		var centre := rect.position + rect.size * 0.5
		if rect.has_point(self_pos) or _vision.can_see(self_pos, facing, centre, space, exclude):
			known_rooms[room["key"]] = true
			_learn_room(room)
	var known_objects := _known_object_ids()
	for obj in _interactables:
		if not is_instance_valid(obj) or known_objects.has(obj.get_instance_id()):
			continue
		if _vision.can_see_node(obj, self_pos, facing, space, exclude):
			known_objects[obj.get_instance_id()] = true
			_learn_object(obj)


## Update character `id`'s movement track with a sighting at `pos` (game msec `now`) and return its
## smoothed velocity, both measured on the game clock (`GameClock`). A sighting after a long gap
## restarts the track (no velocity across the gap). `tuning.context.track_smoothing` is the share of
## a new velocity taken per game frame, so a sighting that comes several frames after the last takes
## the share they add up to.
func _track(id: int, pos: Vector2, now: int) -> Vector2:
	var frame := GameClock.frame()
	var vel := Vector2.ZERO
	var track = _tracks.get(id)
	if track != null:
		var dt: float = (now - track["t"]) / 1000.0
		if dt > 0.0 and dt < 0.5:
			var steps: int = maxi(frame - int(track["f"]), 1)
			var smoothing: float = tuning.context.track_smoothing
			var share := smoothing if steps == 1 else 1.0 - pow(1.0 - smoothing, steps)
			vel = (track["vel"] as Vector2).lerp((pos - track["pos"]) / dt, share)
		elif dt == 0.0:
			vel = track["vel"]
	_tracks[id] = { "pos": pos, "vel": vel, "t": now, "f": frame }
	return vel


# --- BUILD (delegated to the snapshot author) ------------------------------------------------


## BUILD pass — run at the start of each decision. Gather what the NPC currently knows (contacts,
## allies' callouts, learned house knowledge, lost hostiles) and hand it, with the goal and the
## behaviour's current-activity line, to the snapshot author (agent_snapshot.gd), which turns it
## into the decision snapshot the planner walks: { facts, sections, sections_per_target, options }.
## The author reads this knowledge and the combat geometry only — it writes no memory and holds no
## policy.
func sense(rooms: Array, goal: String, activity: String) -> Dictionary:
	if not tuning.memory.familiar_with_house and not _character.stun.is_blind():
		_learn_by_sight(rooms)
	var self_pos: Vector2 = _character.global_position
	var carried := PerceptionGrenades.carried(_character)
	var knowledge := {
		"known_rooms": _known_rooms(rooms),
		"known_room_keys": _known_room_keys(),
		"known_object_ids": _known_object_ids(),
		"interactables": _interactables,
		"post": _post,
		"entry_point": entry_point,
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
	return _snapshot.build(rooms, goal, activity, knowledge)


## The goal text as Von reads it: `{gun}` filled with what the NPC calls its gun.
func fill_goal(goal: String) -> String:
	return _snapshot.fill_goal(goal)


# --- House knowledge -------------------------------------------------------------------------


## Seed a familiar NPC's house knowledge once: remember every room and interactable as already-known
## (permanent ttl). An unfamiliar NPC skips this and learns by sight in observe(). Needs the rooms
## list, so it runs on the first observe() (not _ready).
func _seed_house(rooms: Array) -> void:
	if _seeded or not tuning.memory.familiar_with_house:
		return
	_seeded = true
	for room in rooms:
		_learn_room(room)
	for obj in _interactables:
		if is_instance_valid(obj):
			_learn_object(obj)


## Remember a room as known (permanent).
func _learn_room(room: Dictionary) -> void:
	if not _known_room_keys().has(room["key"]):
		_memory.remember(&"saw_room", { "key": room["key"] }, 0.0, str(room["key"]))


## Remember an interactable object as known (permanent), keyed by instance id.
func _learn_object(obj: Object) -> void:
	if not _known_object_ids().has(obj.get_instance_id()):
		_memory.remember(
			&"saw_object",
			{ "id": obj.get_instance_id() },
			0.0,
			str(obj.get_instance_id()),
		)


## The rooms the NPC knows (all of `rooms` whose key it has learned), in `rooms` order.
func _known_rooms(rooms: Array) -> Array:
	var known := _known_room_keys()
	return rooms.filter(func(r): return known.has(r["key"]))


## The set of room keys the NPC currently knows (from `saw_room` memory), as a lookup dict.
func _known_room_keys() -> Dictionary:
	var out := {}
	for data in _memory.recall_all(&"saw_room"):
		out[data.get("key")] = true
	return out


## The set of interactable instance ids the NPC currently knows (from `saw_object` memory).
func _known_object_ids() -> Dictionary:
	var out := {}
	for data in _memory.recall_all(&"saw_object"):
		out[data.get("id")] = true
	return out


## Scan the world once for objects that advertise interactions (static furniture), caching the refs.
## Positions are read live each tick; the set itself doesn't change during a run.
func _ensure_interactables() -> void:
	if _scanned:
		return
	_scanned = true
	_interactables.clear()
	var root: Node = _character.world_root()
	if root != null:
		_collect(root)


## Recursively gather descendants whose get_interactions() is non-empty into `_interactables`.
func _collect(node: Node) -> void:
	for child in node.get_children():
		if (child.has_method("get_interactions")
				and not (child.get_interactions() as Array).is_empty()):
			_interactables.append(child)
		_collect(child)


## Every other character in the world (the group `characters`, interface 7) under the shared world
## root, excluding the NPC itself, in tree order. Used by observe() to test each for visibility.
func _other_characters() -> Array:
	var root: Node = _character.world_root()
	if root == null:
		return []
	var out: Array = []
	for c: Node in _character.get_tree().get_nodes_in_group(&"characters"):
		if c != _character and root.is_ancestor_of(c):
			out.append(c)
	return out


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


## Of world `points`, the subset the NPC can SEE right now from where it stands — view cone + clear
## line of sight over low cover, the same sight rule used to spot characters (agent_vision.gd). The
## behaviour uses it to track which parts of a room a searcher has covered. Builds the sight query
## from the NPC's body; the NPC excludes itself.
func visible_points(points: Array) -> Array:
	if points.is_empty():
		return []
	var space: PhysicsDirectSpaceState2D = _character.get_world_2d().direct_space_state
	var exclude := [_character.get_rid()]
	var self_pos: Vector2 = _character.global_position
	var facing: Vector2 = _character.facing
	var seen: Array = []
	for p in points:
		if _vision.can_see(self_pos, facing, p, space, exclude):
			seen.append(p)
	return seen


## Where the NPC's sight from where it stands toward world point `to` is first blocked — over low
## cover, the same rule that spots characters (agent_vision.gd) — or `to` itself when the line
## reaches it. The NPC excludes itself. What the vision overlay draws its visible area from; a pure
## read.
func sight_end(to: Vector2) -> Vector2:
	var space: PhysicsDirectSpaceState2D = _character.get_world_2d().direct_space_state
	var hit: Dictionary = _vision.sight_hit(
		space,
		_character.global_position,
		to,
		[_character.get_rid()],
	)
	return hit["position"] if not hit.is_empty() else to


## The geometry of going through doorway `opening_id` into room `into` (see agent_entry.gd
## `geometry`): the door's frame, the stack slots and pie arc on either side, and the room's corners
## tagged hard or soft. {} when unknown.
func entry_geometry(opening_id: String, into: String) -> Dictionary:
	return _entry.geometry(
		opening_id,
		into,
		_character.get_world_2d().navigation_map,
		_character.get_world_2d().direct_space_state,
	)


## Mark room `key` cleared: its entry was carried through to the end (or searched by sight to the
## end), by this NPC or by an ally who radioed it. Not the same as having stood in it
## (`visited_room`): a room walked through unprepared is visited, not cleared. It lapses after
## `tuning.memory.search_ttl`, like a searched room. A stack order into it is done.
func mark_cleared(key: String) -> void:
	_memory.remember(&"cleared_room", { "key": key }, tuning.memory.search_ttl, key)
	var held := orders.current()
	if String(held.get("kind", "")) == "stack" and String(held.get("into", "")) == key:
		# A stack order ends at its room cleared (LD9), by this NPC or by an ally who radioed it.
		orders.end(held["id"], "done")


## Whether room `key` is cleared (see `mark_cleared`).
func is_cleared(key: String) -> bool:
	return _memory.age_of(&"cleared_room", "key", key) <= tuning.memory.search_ttl


## The first doorway on the walk `path` (from waypoint `from_idx`, `max_dist` px of it at most) that
## leads into a room that is not cleared (nor, on an ordered walk, the room its stack holds, or for
## an NPC that does not clear rooms by entry seen empty: D11), as `{ opening, into, dist }`,
## or {} (see agent_door_views.gd `threshold_ahead`).
func threshold_ahead(path: PackedVector2Array, from_idx: int, max_dist: float) -> Dictionary:
	var clear := is_cleared
	if ordered_walk:
		# The room its stack holds is passed through (D20), and, for an NPC that does not clear
		# rooms by entry, a room seen empty (D11).
		clear = func(key: String) -> bool:
			return (
				is_cleared(key)
				or key == _stack_room()
				or (not tuning.entry.enabled and _seen_empty(key))
			)
	return _views.threshold_ahead(path, from_idx, _character.global_position, clear, max_dist)


## The first doorway view the walk `path` goes into without entering the room behind it, as
## `{ opening, into, dist }`, or {} (see agent_door_views.gd `passing_ahead`): a doorway to be
## secured before the NPC crosses its view (E15, E18).
func passing_ahead(path: PackedVector2Array, from_idx: int, max_dist: float) -> Dictionary:
	return _views.passing_ahead(
		path, from_idx, _character.global_position, max_dist, _character.get_world_2d()
	)


## Whether room `key` counts as safe to walk past: cleared within
## `tuning.entry_guard.pass_clear_time` (a room cleared longer ago is cleared for the entry,
## `is_cleared`, but a doorway into it is not safe to walk past again).
func _is_pass_clear(key: String) -> bool:
	return _memory.age_of(&"cleared_room", "key", key) <= tuning.entry_guard.pass_clear_time


## Whether the NPC has stood in room `key` within `tuning.entry_guard.pass_clear_time` and has seen
## no hostile in it since (the latest sighting of each hostile it knows of, within that time, lies
## elsewhere): a room seen empty (`docs/leadership.md` D11). A room only glimpsed through its
## doorway was not stood in, so it is not.
func _seen_empty(key: String) -> bool:
	if _memory.age_of(&"visited_room", "key", key) > tuning.entry_guard.pass_clear_time:
		return false
	for c in contacts.sightings(null, tuning.entry_guard.pass_clear_time, -1.0, true):
		if HouseRooms.key_at(c["pos"], _rooms) == key:
			return false
	return true


## Whether room `key` counts as clear for passing on an ordered walk of an NPC that does not clear
## rooms by entry (D11): cleared lately, seen empty, or held by its stack (`_stack_room`).
func _passable(key: String) -> bool:
	return _pass_clear_ordered(key) or _seen_empty(key)


## Whether room `key` counts as clear for passing on an ordered stack's walk: cleared lately, or the
## room its stack holds (`_stack_room`).
func _pass_clear_ordered(key: String) -> bool:
	return _is_pass_clear(key) or key == _stack_room()


## The room an ordered stack holds (`docs/leadership.md` D20): on the walk of a member to the stack
## its live order names (`ordered_walk`), the room that stack stands in once a member under the same
## order holds its slot there (its claim radioed `ready`, or `bang`): that room counts as cleared
## for passing, so the walk is not sent into it by entry. "" for none (outside the house, no slot
## held yet, or no ordered walk). Worked out once a physics frame.
func _stack_room() -> String:
	var frame := Engine.get_physics_frames()
	if frame == _held_room_frame:
		return _held_room
	_held_room_frame = frame
	_held_room = ""
	var held := orders.current()
	if not ordered_walk or str(held.get("kind", "")) != "stack":
		return _held_room
	var opening := str(held.get("opening", ""))
	for m in entry_stack(opening).team:
		if m["order_id"] == str(held.get("id", "")) and StackClaim.in_slot(m["step"]):
			_held_room = str(entry_geometry(opening, str(held.get("into", ""))).get("from", ""))
			break
	return _held_room


## Whether the routes a snapshot measures can be the ones the NPC will walk (see agent_door_views.gd
## `warm`): the avoid map for the doorway views from the room it stands in is baked. Asking starts
## the bake. After `WARM_CAP_MS` of waiting it is true anyway, so a decision never waits for good.
func routes_ready() -> bool:
	var world: World2D = _character.get_world_2d()
	if _views.warm(_character.global_position, world.navigation_map, world.direct_space_state):
		_warming_since = -1
		return true
	var now := GameClock.msec()
	if _warming_since < 0:
		_warming_since = now
	return now - _warming_since > WARM_CAP_MS


## The doorway views the NPC's walks keep out of from where it stands, each `{ id, into, poly }`
## (see agent_door_views.gd `avoided`): what the entry plan overlay draws.
func avoided_views() -> Array:
	var world: World2D = _character.get_world_2d()
	return (_views.views_from(
		_character.global_position, world.navigation_map, world.direct_space_state,
	)
			if _views.avoid_views
			else [])


## The route the NPC walks from where it stands to `to` (see agent_door_views.gd `walk_route`): the
## plain one, or the one that keeps out of the views of the doorways into rooms not clear for
## passing when there is one within the cap. `entering` (`"<opening id>><room key>"`): the entry the
## walk is the approach of, which keeps out of that room and its doorway's view. `from` (INF: where
## the NPC stands) is where the walk sets out from, for a leg of a walk read ahead.
func walk_route(to: Vector2, entering := "", from := Vector2.INF) -> Dictionary:
	var world: World2D = _character.get_world_2d()
	var at: Vector2 = _character.global_position if from == Vector2.INF else from
	return _views.walk_route(at, to, world.navigation_map, world.direct_space_state, entering)


## Whether the NPC can walk from where it stands to `to` with a body standing at each of `bodies` in
## its way (see agent_entry.gd `slot_reach`): 1 yes, 0 no, -1 not known yet (its map is being
## baked).
func entry_slot_reach(to: Vector2, bodies: Array) -> int:
	return _entry.slot_reach(
		_character.global_position,
		to,
		_character.get_world_2d().navigation_map,
		bodies,
	)


## The doorways out of the cleared room `into` that lead on into a room that is not cleared, other
## than `opening_id` (the one the NPC came in by): what the team covers once the room is clear, as
## `{ id, into, pos, width }` (see agent_entry.gd `watch_doors`).
func entry_watch_doors(into: String, opening_id: String) -> Array:
	return _entry.watch_doors(into, opening_id, is_cleared)


## Every doorway of room `room_key`, outer doors included, as `{ id, pos, width }` (see
## agent_entry.gd `room_doorways`): the places a resting NPC watches.
func room_doorways(room_key: String) -> Array:
	return _entry.room_doorways(room_key)


## The stack at doorway `opening_id` into room `into` as the radio describes it
## (stack/door_stack.gd): the allies' live claims on it (stack/claim_ledger.gd `claims`) over its
## geometry (`entry_geometry`), every slot rule settled the one way. One per doorway a frame. With
## `into` "" it has no geometry: only what the claims alone answer (`team`, `claimed`, `stacking`,
## `going_in`, `released`, `crossing`, `order_claim`) may be asked of it.
func entry_stack(opening_id: String, into := "") -> RefCounted:
	return _ledger.stack(opening_id, entry_geometry(opening_id, into) if into != "" else {})


## The side of a doorway (`geometry` from `entry_geometry`) point `p` is on, 1 / -1 along its wall:
## the radio claims' `side` (see agent_entry.gd `side_of`).
func entry_side_of(geometry: Dictionary, p: Vector2) -> int:
	return AgentEntry.side_of(geometry, p)


## The side of a doorway the NPC stacks on from where it stands in `stack` (`entry_stack`): the
## team's, unless its way there crosses the doorway's view, then its own (a split stack, see
## agent_entry.gd `stack_side_from`).
func entry_stack_side(stack: RefCounted) -> int:
	var world: World2D = _character.get_world_2d()
	return _entry.stack_side_from(
		stack, _character.global_position, world.navigation_map, world.direct_space_state,
	)


## Whether point `p` is ground a stack going in by `geometry` may walk on to its slot
## (`AgentEntry.slots.on_stack_side`: on the stack side, in its room, out of every other doorway's
## funnel).
func entry_on_stack_side(geometry: Dictionary, p: Vector2) -> bool:
	return _entry.slots.on_stack_side(_entry, geometry, p)


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
