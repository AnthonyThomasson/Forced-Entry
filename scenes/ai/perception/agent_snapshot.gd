extends RefCounted
## AI PERCEPTION sub-domain — the SNAPSHOT AUTHOR. The BUILD half of perception: given what the NPC
## currently knows (contacts, memory, learned house knowledge) and the combat geometry, it writes
## the decision SNAPSHOT the planner walks — named boolean `facts` the tree gates on, named state
## `sections` Von reads, and named option `groups` (places and things with the attributes a choice
## turns on). It is a pure transform: it reads the event memory and the tactics module, holds no
## state between calls, and never writes memory, decides or picks. The work is split three ways
## under `snapshot/`: the shared vocabulary and tuning (`vocab`), the state text (`_sections`) and
## the option groups (`_options`, with the grenade throws in `_throws` and the leader's order in
## `_orders`); this file assembles them. `agent_perception.gd` (the SEE half)
## owns it, like it owns vision / hostility / memory / tactics, and calls `build()` once per
## decision.
##
## Everything Von reads is worded for a CLASSIFIER that picks the option whose text best matches the
## state and cannot do arithmetic: distances, routes and ages are BANDS ("in pistol range", "short
## route", "recently"); each option carries the facts that distinguish it from its siblings, in a
## fixed order; there are NO negations (an encoder reads "no cover" as "cover" — say "in the open",
## "line blocked", "free", "unsearched"); and the state uses the same canonical phrases the decision
## tree's situation descriptions are written in, so a fact in the state lights up the option it
## argues for. Options are places and things, never verbs — the decision tree decides what to do at
## them.

const SnapshotVocab = preload("res://scenes/ai/perception/snapshot/snapshot_vocab.gd")
const HouseRooms := preload("res://scenes/ai/perception/house_rooms.gd")
const SnapshotSections = preload("res://scenes/ai/perception/snapshot/snapshot_sections.gd")
const SnapshotOptions = preload("res://scenes/ai/perception/snapshot/snapshot_options.gd")
const SnapshotThrows = preload("res://scenes/ai/perception/snapshot/snapshot_throws.gd")
const SnapshotOrders = preload("res://scenes/ai/perception/snapshot/snapshot_orders.gd")
const SnapshotDemand = preload("res://scenes/ai/perception/snapshot/snapshot_demand.gd")
const StackClaim = preload("res://scenes/ai/perception/stack/stack_claim.gd")

## The shared vocabulary and tuning. The perception's apply_config() hands it the NPC's tuning
## (`vocab.tuning`), which it reads live; only the perception's geometry modules take copies.
var vocab := SnapshotVocab.new()
## The state text; see snapshot_sections.gd.
var _sections := SnapshotSections.new()
## The option groups; see snapshot_options.gd.
var _options := SnapshotOptions.new()
## The grenade option groups; see snapshot_throws.gd.
var _throws := SnapshotThrows.new()
## The ORDER option group; see snapshot_orders.gd.
var _orders := SnapshotOrders.new()
## The agent's event memory (read-only here); see agent_memory.gd.
var _memory: RefCounted
## The combat geometry; see agent_tactics.gd.
var _tactics: RefCounted
## The NPC's body, handed in once by `bind`.
var _character: Node


## Capture the collaborators the author reads (`sources`): the event memory, the combat geometry,
## the doorway geometry, the doorway views, the grenade geometry, why a room is suspect and the
## claims heard. Called once by the perception in its setup(), after it has built them. The config
## fields are set directly by the perception's apply_config() (like the other modules), so there is
## no separate configure step.
func setup(sources: SnapshotSources) -> void:
	_memory = sources.memory
	_tactics = sources.tactics
	_sections.setup(vocab, sources.memory, sources.tactics)
	_options.setup(vocab, sources)
	_throws.setup(vocab, sources)
	_orders.setup(vocab, sources)


## Hand in the NPC's body, for the author and the four parts that read it. Called once by
## `AgentPerception.bind()`.
func bind(character: Node) -> void:
	_character = character
	vocab.character = character
	_sections.bind(character)
	_options.bind(character)
	_orders.bind(character)


## BUILD pass — run at the start of each decision. Assemble the snapshot the decision planner walks,
## from what the agent currently sees and remembers (NOT from ground truth): `goal` is the behaviour
## string Von ranks against; `activity` is the behaviour's line for what the NPC is doing now. The
## perception hands in the knowledge this reads over (`knowledge`, see the perception's `sense()`):
## its `contacts`, the `callouts` heard, learned rooms/objects, interactables, the NPC's post and
## entry point, and lost hostiles. Returns { facts, sections, sections_per_target, options, gun,
## demand }: `demand` builds the groups and facts the walk reads rarely (`snapshot_demand.gd`) when
## it first reads them, so the snapshot holds those only once something has.
func build(rooms: Array, goal: String, activity: String, knowledge: Dictionary) -> Dictionary:
	var _decision: RefCounted = _options.begin_decision()
	vocab.rooms = rooms
	_options.know = knowledge
	_throws.know = knowledge
	_throws.begin()
	var ctx := _context(knowledge["contacts"], knowledge["callouts"])
	ctx["engaged_id"] = int(knowledge.get("engaged_id", 0))
	var parts := _per_target(ctx, rooms)
	parts.merge(_shared(ctx, knowledge))
	var facts := _facts(ctx, parts, knowledge)
	var options := _option_groups(ctx, parts, knowledge)
	var demand := SnapshotDemand.new()
	demand.options = _options
	demand.texts = _sections
	demand.throws = _throws
	demand.targets = parts["targets"]
	demand.per_sections = parts["per_sections"]
	demand.vocab = vocab
	demand.ctx = ctx
	demand.know = knowledge
	demand.rooms = rooms
	demand.stun_stack = parts["stun_stack"]
	demand.groups = options
	demand.facts = facts
	var sections := _state_sections(ctx, parts, goal, activity, knowledge)
	demand.sections = sections
	return {
		"facts": facts, "sections": sections, "sections_per_target": parts["per_sections"],
		"options": options, "gun": vocab.gun_noun(parts["gun"]), "demand": demand,
	}


## The decision's context every group reads: where the NPC stands, its world, space, map and body,
## the hostiles and allies among `known` (its contacts), the `callouts` heard, and each hostile's
## front.
func _context(known: Array, callouts: Array) -> Dictionary:
	var self_pos: Vector2 = _character.global_position
	var hostiles: Array = known.filter(func(c): return c["hostile"])
	var allies: Array = known.filter(func(c): return c["ally"] and not c["hostile"])
	var ctx := {
		"world": _character.get_world_2d(),
		"space": _character.get_world_2d().direct_space_state,
		"map": _character.get_world_2d().navigation_map,
		"self_pos": self_pos,
		"self_id": _character.get_instance_id(),
		"exclude": [_character.get_rid()],
		"hostiles": hostiles,
		"allies": allies,
		"callouts": callouts,
		"fronts": {},
		# hostile id -> whether this NPC is hidden from it where it stands (see agent_tactics.gd
		# `_watched_in_open`)
		"covered_from": {},
		# Snapshot-scoped tactics geometry: routes, self rings and per-(point, hostile) cover.
		"tactics_cache": {},
	}
	# Each hostile's front (its last-seen facing while recent, else toward this NPC): the frame its
	# flanks are measured in, and where it is looking when a spot is judged watched.
	for h in hostiles:
		ctx["fronts"][h["id"]] = _tactics.front_angle(
			h,
			self_pos,
			h["visible"] or h["age"] <= vocab.tuning.context.recency_bands.y,
		)
	return ctx


## Per known hostile: the combat geometry (`analyses`), the option groups (`per_target`) and the
## sections that follow from it (`per_sections`), each by hostile id; `targets` holds each hostile
## given full analysis with its geometry, for what `demand` builds of it later (its grenade throws
## and its exposure).
func _per_target(ctx: Dictionary, rooms: Array) -> Dictionary:
	var per_target := {}
	var per_sections := {}
	var analyses := {}
	var targets := {}
	var hostiles: Array = ctx["hostiles"]
	var selected := _analysed_ids(ctx)
	# Selection reserves the engaged slot; iteration keeps the contacts' nearest-first order.
	var listed: int = vocab.tuning.decision.max_options_per_level
	for i in hostiles.size():
		var t: Dictionary = hostiles[i]
		if not selected.has(t["id"]):
			# The hostile bind lists the nearest `max_options_per_level` hostiles and needs only
			# this cheap line fact of one beyond the cap; hostiles further out need nothing.
			if i < listed:
				analyses[t["id"]] = { "line": _line(ctx, t) }
			continue
		var a := _analyze(ctx, t)
		analyses[t["id"]] = a
		targets[t["id"]] = { "t": t, "a": a }
		per_target[t["id"]] = {
			"fire_positions": _options.fire_group(ctx, t, a),
			"flank_sides": _options.flank_group(t, a, rooms),
			"advance_positions": _options.advance_group(ctx, t, a),
			"melee": _options.melee_group(ctx["self_pos"], t),
		}
		per_sections[t["id"]] = _target_sections(ctx, t, a)
	return {
		"per_target": per_target, "per_sections": per_sections, "analyses": analyses,
		"targets": targets,
	}


## The ids of the hostiles that get full analysis (fire, flank, advance and melee options, and
## sections): the engaged one when known, then the nearest others, at most the smaller of
## `max_analysed_targets` and `max_options_per_level` in all.
func _analysed_ids(ctx: Dictionary) -> Array:
	var cap := mini(
		vocab.tuning.decision.max_analysed_targets, vocab.tuning.decision.max_options_per_level
	)
	var selected: Array = []
	var engaged_id: int = ctx["engaged_id"]
	if ctx["hostiles"].any(func(t): return t["id"] == engaged_id):
		selected.append(engaged_id)
	for t in ctx["hostiles"]:
		if selected.size() >= cap:
			break
		if not selected.has(t["id"]):
			selected.append(t["id"])
	return selected


## The sections re-framed around hostile `t` (geometry `a`) that need no throw: flanks and allies.
## Its exposure, which says what grenades it can throw, is `demand`'s.
func _target_sections(ctx: Dictionary, t: Dictionary, a: Dictionary) -> Dictionary:
	return {
		"flanks": _sections.flanks_text(t, a),
		"allies": _sections.allies_text(ctx, t, a),
	}


## What the whole decision shares beyond the hostiles: whether the stack has a stun (`stun_stack`),
## the damage taken (`dmg`), the gun it fights with (`gun`) and its rounds (`ammo`, -1 without one).
## The doorways to enter by, the leads, the throws and the other groups the walk reads rarely are
## `demand`'s.
func _shared(ctx: Dictionary, knowledge: Dictionary) -> Dictionary:
	var carried: Array = knowledge["carried_grenades"]
	var stun_stack: bool = (carried.has(&"stun")
			or ctx["callouts"].any(func(c): return int(StackClaim.decode(c).get("stuns", 0)) > 0))
	var dmg: float = _character.damage_taken()
	# Rounds in the gun it fights with (-1 without one): the AI shoots, reloads and plans around it.
	var gun: int = _character.inventory.gun_slot()
	var ammo: int = _character.ammo.rounds(gun) if gun >= 0 else -1
	return { "stun_stack": stun_stack, "dmg": dmg, "gun": gun, "ammo": ammo }


## The named facts a `requires` or an entry rule gates on, from the context and the `parts` worked
## out for this decision.
func _facts(ctx: Dictionary, parts: Dictionary, knowledge: Dictionary) -> Dictionary:
	var hostiles: Array = ctx["hostiles"]
	var self_pos: Vector2 = ctx["self_pos"]
	var primary: Dictionary = hostiles[0] if not hostiles.is_empty() else {}
	var line: Dictionary = (parts["analyses"][primary["id"]]["line"]
			if not primary.is_empty()
			else {})
	var gun: int = parts["gun"]
	var ammo: int = parts["ammo"]
	var facts := {
		"hostile_known": not hostiles.is_empty(),
		"threat_known": not hostiles.is_empty() or _memory.under_fire(),
		"gun_loaded": ammo > 0 and not _character.ammo.is_reloading(),
		"weapon_low": (
			ammo >= 0
			and ammo <= ceili(
				_character.ammo.capacity(gun) * vocab.tuning.context.low_ammo_fraction
			)
		),
		"can_reload": gun >= 0 and _character.ammo.can_reload(gun),
		"under_fire": _memory.under_fire(),
		"engaged": _memory.engaged(),
		"stack_has_stun": parts["stun_stack"],
		"hurt": parts["dmg"] >= vocab.tuning.context.hurt_threshold,
		"inside": not HouseRooms.at(self_pos, vocab.rooms).is_empty(),
		"exposed": line.get("clear", false) or (primary.is_empty() and _memory.under_fire()),
		"ordered": not (knowledge["order"] as Dictionary).is_empty(),
		"follows": knowledge["follows"],
	}
	return facts


## The named state-text sections Von reads, framed around the nearest hostile with full analysis
## (the engaged one when a cap of one leaves the nearest with line facts only).
func _state_sections(
	ctx: Dictionary,
	parts: Dictionary,
	goal: String,
	activity: String,
	knowledge: Dictionary,
) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var hostiles: Array = ctx["hostiles"]
	var rooms: Array = vocab.rooms
	var per_sections: Dictionary = parts["per_sections"]
	var primary: Dictionary = {}
	for h in hostiles:
		if per_sections.has(h["id"]):
			primary = h
			break
	return {
		"goal": fill_goal(goal),
		"situation": _sections.situation_text(rooms),
		"loadout": _sections.loadout_text(
			parts["gun"],
			parts["ammo"],
			knowledge["carried_grenades"],
		),
		"current": ("Current activity: %s." % activity) if activity != "" else "",
		"contacts": _sections.contacts_text(self_pos, knowledge["contacts"]),
		"allies": per_sections[primary["id"]]["allies"]
			if not primary.is_empty()
			else _sections.allies_text(ctx, {}, {}),
		"flanks": per_sections[primary["id"]]["flanks"] if not primary.is_empty() else "",
		"awareness": _sections.awareness_text(self_pos, not hostiles.is_empty()),
		"order": _sections.order_text(knowledge["order"], rooms, knowledge["keep_out"]),
	}


## The option groups the planner walks: per hostile (`per_target`) and for the whole decision.
func _option_groups(ctx: Dictionary, parts: Dictionary, knowledge: Dictionary) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var hostiles: Array = ctx["hostiles"]
	var rooms: Array = vocab.rooms
	var known_rooms: Array = knowledge["known_rooms"]
	return {
		"per_target": parts["per_target"],
		"threat": { "summary": _sections.threat_summary(self_pos, hostiles) },
		"hostiles": _options.hostile_group(ctx, hostiles, parts["analyses"]),
		"reload": _options.reload_group(parts["gun"]),
		"retreat_positions": _options.retreat_group(ctx, hostiles, known_rooms, parts["dmg"]),
		"shooter": _options.shooter_group(ctx, hostiles),
		"order": _orders.group(ctx, knowledge["order"], rooms),
	}


## The combat geometry around hostile `t`: its frame (front bearing), the line between the NPC and
## it, and the candidate fire / flank / advance positions.
func _analyze(ctx: Dictionary, t: Dictionary) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var front: float = ctx["fronts"][t["id"]]
	return {
		"front": front,
		"own_side": _tactics.side_of(t["pos"], front, self_pos),
		"line": _line(ctx, t),
		"fire": _tactics.fire_positions(ctx, t),
		"flanks": _tactics.flank_sides(ctx, t, front),
		"advance": _tactics.advance_positions(ctx, t),
	}


## The clear-shot line to hostile `t`, also computed for hostiles outside the full-analysis cap.
func _line(ctx: Dictionary, t: Dictionary) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var ex: Array = ctx["exclude"] + _tactics.body_rid(t)
	var obj = _tactics.blocker(ctx["space"], self_pos, t["pos"], ex)
	return {
		"clear": obj == null,
		"in_range": self_pos.distance_to(t["pos"]) <= vocab.tuning.combat.shoot_range,
		"cover": _tactics.object_label(obj) if _tactics.is_cover(obj) else "",
		"blocker": _tactics.object_label(obj),
	}


## The goal text with `{gun}` replaced by what the NPC calls its gun ("shoot them with your {gun}"
## reads "...your pistol" or "...your assault rifle"), so one goal serves every weapon.
func fill_goal(goal: String) -> String:
	return goal.replace("{gun}", vocab.gun_noun(_character.inventory.gun_slot()))
