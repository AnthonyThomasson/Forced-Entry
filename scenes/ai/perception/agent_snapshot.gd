extends RefCounted
## AI PERCEPTION sub-domain — the SNAPSHOT AUTHOR. The BUILD half of perception: given what the NPC
## currently knows (contacts, memory, learned house knowledge) and the combat geometry, it writes
## the decision SNAPSHOT the planner walks — named boolean `facts` the tree gates on, named state
## `sections` Von reads, and named option `groups` (places and things with the attributes a choice
## turns on). It is a pure transform: it reads the event memory and the tactics module, holds no
## state between decisions (a build held between pieces carries its own, `snapshot_build.gd`), and
## never writes memory, decides or picks. The work is split three ways under `snapshot/`: the
## shared vocabulary and tuning (`vocab`), the state text (`_sections`) and the option groups
## (`_options`, with the grenade throws in `_throws` and the leader's order in `_orders`); this
## file assembles them. `agent_perception.gd` (the SEE half) owns it, like it owns vision /
## hostility / memory / tactics, and calls `build()` once per decision.
##
## Everything Von reads is worded for a CLASSIFIER that picks the option whose text best matches the
## state and cannot do arithmetic: distances, routes and ages are BANDS ("in pistol range", "short
## route", "recently"); each option carries the facts that distinguish it from its siblings, in a
## fixed order; there are NO negations (an encoder reads "no cover" as "cover" — say "in the open",
## "line blocked", "free", "unsearched"); and the state uses the same canonical phrases the decision
## tree's situation descriptions are written in, so a fact in the state lights up the option it
## argues for. Options are places and things, never verbs — the decision tree decides what to do at
## them.

const SnapshotBuild = preload("res://scenes/ai/perception/snapshot/snapshot_build.gd")
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
## it first reads them, so the snapshot holds those only once something has. This runs every piece
## of a staged build (`begin_build`) in one go.
func build(rooms: Array, goal: String, activity: String, knowledge: Dictionary) -> Dictionary:
	var staged := begin_build(rooms, goal, activity, func() -> Dictionary: return knowledge)
	var _walks: RefCounted = hold_walks()
	while not staged.done():
		staged.step()
	return staged.result()


## BUILD pass in pieces: the same snapshot as `build()`, made by `step()`ping the returned build
## (`snapshot/snapshot_build.gd`) until `done()`, then `result()`. Nothing runs here; the first
## piece calls `gather` for the knowledge `build()` takes (a `Dictionary`) and `freeze`, if given,
## for entries that go into the snapshot as they stand at that moment (the perception's
## confinement copy). The pieces do the work in the order `build()` always did, so a staged build
## moves no ray, route or random draw. One build is in flight per author: the author's
## per-decision scratch (`vocab.rooms`, the options' and throws' `know`) is the build's, set by its
## first piece, so a build that is dropped for a new one is never resumed.
func begin_build(
		rooms: Array, goal: String, activity: String, gather: Callable, freeze := Callable(),
) -> SnapshotBuild:
	var staged := SnapshotBuild.new()
	staged.author = self
	staged.rooms = rooms
	staged.goal = goal
	staged.activity = activity
	staged.gather = gather
	staged.freeze = freeze
	return staged


## Run the next piece of `staged` (`SnapshotBuild.step` calls this).
func advance_build(staged: SnapshotBuild) -> void:
	match staged.piece:
		SnapshotBuild.Piece.START:
			_start_build(staged)
		SnapshotBuild.Piece.HOSTILE:
			_hostile_piece(staged)
		SnapshotBuild.Piece.FINISH:
			_finish_build(staged)


## Open the walked-route memo of the doorway views (`begin_decision`), for as long as the returned
## token is held: the pieces of a build that run together (one `build()`, or what one frame's pool
## lets the decision job run) reuse each other's walks. A build must not hold it across frames, when
## a door or the map may have changed (`snapshot-staged.md`).
func hold_walks() -> RefCounted:
	return _options.begin_decision()


## Hand the author's modules the build's own decision again (`vocab.rooms`, the options' and
## throws' `know`): what `SnapshotDemand` does as it builds an older snapshot's rest (`_open`), so
## a pause between pieces in which an older snapshot was completed leaves the build's reads as
## they were. Every piece that reads them calls it first.
func _own_scratch(staged: SnapshotBuild) -> void:
	vocab.rooms = staged.rooms
	_options.know = staged.knowledge
	_throws.know = staged.knowledge


## The START piece: the knowledge, the decision's per-build scratch and its context, and which
## hostiles get full analysis.
func _start_build(staged: SnapshotBuild) -> void:
	var knowledge: Dictionary = staged.gather.call()
	staged.knowledge = knowledge
	if staged.freeze.is_valid():
		staged.frozen = staged.freeze.call()
	_own_scratch(staged)
	var ctx := _context(knowledge["contacts"], knowledge["callouts"])
	ctx["engaged_id"] = int(knowledge.get("engaged_id", 0))
	staged.ctx = ctx
	staged.parts = { "per_target": {}, "per_sections": {}, "analyses": {}, "targets": {} }
	staged.analysed = _analysed_ids(ctx)
	staged.piece = SnapshotBuild.Piece.FINISH
	if not ctx["hostiles"].is_empty():
		staged.piece = SnapshotBuild.Piece.HOSTILE


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
		# What this decision's throws worked out (`SnapshotThrows.memo_of`): its own, never an
		# older build's.
		"throw_memo": { "spots": {}, "points": {}, "exists": {} },
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


## One HOSTILE piece: the next hostile given full analysis, with the cheap `line` entries of the
## listed hostiles ahead of it in the contacts' nearest-first order (and, after the last analysed
## one, of those that follow it). Per hostile the build gathers the combat geometry (`analyses`),
## the option groups (`per_target`) and the sections that follow from it (`per_sections`), each by
## hostile id; `targets` holds each hostile given full analysis with its geometry, for what `demand`
## builds of it later (its grenade throws and its exposure).
func _hostile_piece(staged: SnapshotBuild) -> void:
	_own_scratch(staged)
	var ctx := staged.ctx
	var hostiles: Array = ctx["hostiles"]
	var analyses: Dictionary = staged.parts["analyses"]
	# Selection reserves the engaged slot; iteration keeps the contacts' nearest-first order.
	var listed: int = vocab.tuning.decision.max_options_per_level
	while staged.cursor < hostiles.size():
		var i := staged.cursor
		staged.cursor += 1
		var t: Dictionary = hostiles[i]
		if not staged.analysed.has(t["id"]):
			# The hostile bind lists the nearest `max_options_per_level` hostiles and needs only
			# this cheap line fact of one beyond the cap; hostiles further out need nothing.
			if i < listed:
				analyses[t["id"]] = { "line": _line(ctx, t) }
			continue
		_analyse_target(staged, t)
		if _analysed_ahead(staged):
			return
	staged.piece = SnapshotBuild.Piece.FINISH


## Whether a hostile given full analysis is yet to come in the contacts' order.
func _analysed_ahead(staged: SnapshotBuild) -> bool:
	var hostiles: Array = staged.ctx["hostiles"]
	for i in range(staged.cursor, hostiles.size()):
		if staged.analysed.has(hostiles[i]["id"]):
			return true
	return false


## The full analysis of hostile `t`: its geometry, option groups and sections, into `staged.parts`.
func _analyse_target(staged: SnapshotBuild, t: Dictionary) -> void:
	var ctx := staged.ctx
	var parts := staged.parts
	var a := _analyze(ctx, t)
	parts["analyses"][t["id"]] = a
	parts["targets"][t["id"]] = { "t": t, "a": a }
	parts["per_target"][t["id"]] = {
		"fire_positions": _options.fire_group(ctx, t, a),
		"flank_sides": _options.flank_group(t, a, staged.rooms),
		"advance_positions": _options.advance_group(ctx, t, a),
		"melee": _options.melee_group(ctx["self_pos"], t),
	}
	parts["per_sections"][t["id"]] = _target_sections(ctx, t, a)


## The FINISH piece: what the whole decision shares, the facts, the option groups, the demand that
## builds the rest when the walk reads it, and the sections; the snapshot is done.
func _finish_build(staged: SnapshotBuild) -> void:
	_own_scratch(staged)
	var knowledge := staged.knowledge
	var ctx := staged.ctx
	var parts := staged.parts
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
	demand.rooms = staged.rooms
	demand.stun_stack = parts["stun_stack"]
	demand.groups = options
	demand.facts = facts
	var sections := _state_sections(ctx, parts, staged.goal, staged.activity, knowledge)
	demand.sections = sections
	ctx["analyses"] = parts["analyses"]
	var snapshot := {
		"facts": facts, "sections": sections, "sections_per_target": parts["per_sections"],
		"options": options, "gun": vocab.gun_noun(parts["gun"]), "demand": demand,
	}
	snapshot.merge(staged.frozen)
	staged.finish(snapshot)


## The radio callouts read again for a snapshot built some frames ago (`callouts`: what the NPC
## hears now), and what the snapshot made of the ones it was built with made again: who holds each
## flank side of a hostile (`held_by`, so the flank options, their summary and the allies and
## flanks sections), the allies on a hostile (the hostile group's wording), whether the stack holds
## a stun. A teammate's claim that came in while the build was spread over frames is seen, so two
## NPCs on one target take different sides. The groups, facts and sections built when the walk
## first reads them read the callouts then, as they always have. Called by the decision job as
## its throw piece ends, the last thing before the walk; nothing is made again when the callouts
## are as the build read them. Like every piece it first hands the authors the snapshot's own
## decision (`SnapshotDemand.open`), whatever a decision begun since has left in them.
func reread_claims(snapshot: Dictionary, callouts: Array) -> void:
	var demand: SnapshotDemand = snapshot["demand"]
	var ctx: Dictionary = demand.ctx
	var _scope: RefCounted = demand.open()
	if callouts == ctx["callouts"]:
		return
	ctx["callouts"] = callouts
	demand.know["callouts"] = callouts
	for id in demand.targets:
		var target: Dictionary = demand.targets[id]
		for side: Dictionary in target["a"]["flanks"]:
			side["held_by"] = _tactics.side_holder(
				target["t"], target["a"]["front"], side["side"], ctx["allies"], callouts
			)
		snapshot["options"]["per_target"][id]["flank_sides"] = _options.flank_group(
			target["t"], target["a"], demand.rooms
		)
		var texts := _target_sections(ctx, target["t"], target["a"])
		for name in texts:
			demand.per_sections[id][name] = texts[name]
	snapshot["options"]["hostiles"] = _options.hostile_group(
		ctx, ctx["hostiles"], ctx["analyses"]
	)
	var carried: Array = demand.know["carried_grenades"]
	demand.stun_stack = (carried.has(&"stun")
			or callouts.any(func(c): return int(StackClaim.decode(c).get("stuns", 0)) > 0))
	snapshot["facts"]["stack_has_stun"] = demand.stun_stack
	for name in ["allies", "flanks"]:
		snapshot["sections"][name] = _primary_section(snapshot, ctx, name)


## The state section `name` (`allies` or `flanks`) of the snapshot, taken from the nearest hostile
## with full analysis as `_state_sections` does.
func _primary_section(snapshot: Dictionary, ctx: Dictionary, name: String) -> String:
	var per_sections: Dictionary = snapshot["sections_per_target"]
	for h: Dictionary in ctx["hostiles"]:
		if per_sections.has(h["id"]):
			return per_sections[h["id"]][name]
	return _sections.allies_text(ctx, {}, {}) if name == "allies" else ""


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
