class_name MatchBuilder
extends RefCounted
## Composition-root module (beside `main.gd` and `match_spawner.gd`): builds a match for Main and
## for the Testing domain's world alike, so both compose one the same way. A match spec goes in (a
## plain dict `spec` fills with defaults: the house's `seed` / `plan` / `entrance`, or a `house`
## already built, each side's `count`, `loadout` and optional `at`, the `human`, `wait_nav`,
## `spawn_clearance`, `invader_margin`, `overlays`) and a match handle comes out (a plain dict:
## `world`, `house`, `rooms`, `openings`, `nav_region`, `nav_debug`, then `combatants`, `squads`,
## `player_stack`, `leader_overlay`). `build` is its two stages: `stage`, the world stage (the
## house, its navigation map with the holes overlay and the re-baker, interface 9, the dusk
## lighting, interface 20, then, when asked, a wait until both navigation maps answer with this
## house), and `populate` (each side placed through the match spawner, the human joined, everyone
## armed, styled and ranked, one squad per side and the squad-leaders overlay over them). `bind_npc`
## is the one rule an NPC's controller is handed the house by (before the NPC joins the tree),
## `bind_squad` / `bind_player` / `callout_ttl_of` the squad's and the human's (interfaces 17, 21).
## `set_overlay` is the one rule a debug overlay's toggle reaches a match by (interface 22).
## `spec_from_setup` reads the setup window's choices into a spec, `random_spec` draws an endless
## run's next one.
## Like `main.gd` it knows the domains it wires; nothing in them knows it.

## NPC placement for one match (where defenders and invaders start; see match_spawner.gd).
const MATCH_SPAWNER := preload("res://scenes/match_spawner.gd")
## One side's squad: its leader, succession and the orders its leader gives (`docs/leadership.md`,
## interface 21).
const SQUAD := preload("res://scenes/ai/team/squad.gd")
## Faction tags the two NPC scenes carry (authored on the scenes); a human joining a side takes its
## tag so that side's NPCs treat them as an ally.
const DEFENDER_FACTION := &"household"
const INVADER_FACTION := &"invader"
## Salt mixed into the house seed for the loadout draws, so picking guns never shifts the NPC
## placement that the house seed already pins ("LOAD").
const LOADOUT_SEED_SALT := 0x4c4f4144
## Salt mixed into the house seed for the style draws, so styling the crews never shifts the guns or
## the placement ("LOOK").
const STYLE_SEED_SALT := 0x4c4f4f4b
## What the invaders (and a human invading) carry and wear by default: a stun grenade and a frag
## grenade each, in a helmet, a shirt, a plate carrier with a steel III plate front and back,
## tactical pants and boots (`docs/outfits.md` O11). The rest (the gun, its magazine and spares) is
## the `LoadoutConfig` default: one random gun with its own magazine and spares.
const INVADER_LOADOUT := {
	"stuns": 1, "frags": 1,
	"outfit": {
		"head": &"helmet", "body": &"shirt", "vest": &"plate_carrier", "pants": &"tactical_pants",
		"feet": &"boots", "front_plate": &"steel_iii", "back_plate": &"steel_iii",
	},
}
## What the defenders (and a human defending) carry and wear by default: the `LoadoutConfig`
## default, a random gun with its own magazine and spares, no grenades, and
## `LoadoutConfig.default_outfit`'s plain clothes (a t-shirt, jeans and shoes).
const DEFENDER_LOADOUT := {}
## Draw-only overlay for the baked navmesh's holes, furniture and characters at rest (Navigation
## domain).
const NAV_DEBUG := preload("res://scenes/navigation/nav_debug.gd")
## Periodic navmesh re-baker: re-carves furniture holes as pieces are shoved around (Navigation
## domain).
const NAV_UPDATER := preload("res://scenes/navigation/nav_updater.gd")
## The human's side of the entry radio: it reserves the human a slot in an AI stack near it
## (`docs/tactical-entry.md` E16).
const PLAYER_STACK := preload("res://scenes/ai/team/player_stack.gd")
## The debug overlay table (UI): the flags `overlays` and `set_overlay` name.
const OVERLAY_REGISTRY := preload("res://scenes/ui/overlays/overlay_registry.gd")
## The squad-leaders debug overlay (UI, `docs/leadership.md` LD12): a crown over each side's leader.
const LEADER_OVERLAY := preload("res://scenes/ui/overlays/leader_overlay.gd")
## The keys of a side's loadout the setup window chooses (its per-side config, beside `count`).
const SETUP_LOADOUT_KEYS := ["weapon", "magazine", "spares", "stuns", "frags", "outfit"]
## Most wall-clock ms `stage` waits for the navigation maps to answer with the house's navmesh (a
## map synchronizes on a worker thread, so a loaded machine is slow in real time, not in frames).
const NAV_SYNC_MS := 5000
## The `claim_ttl` (`SquadsSpec`) that `build_squads` and `squads_over` read as "as long as the
## side's NPCs keep a callout" (`callout_ttl_of`): any negative value.
const CLAIM_TTL_OF_NPCS := -1.0


## A match spec: `overrides` over the defaults. `seed` (the house's, which also pins the placement,
## the guns and the styles; 0 by default), `plan` (a floorplan key, "" = picked by the seed),
## `entrance` (where the front entrance lands), `house` (a house already built, a hand-laid layout
## or an arena with its objects placed, staged in place of a generated one; null = generate one),
## `defenders` / `invaders` (each `{ count, loadout, at }`: how many NPCs, what they carry
## (`INVADER_LOADOUT` / `DEFENDER_LOADOUT`), and optional explicit start points, one NPC each, in
## place of placement; a side given in `overrides` keeps the defaults of what it does not name),
## `human` (`{ node, side, lead, at }`: the human's character, the side it joins, `&"defender"` or
## `&"invader"`, whether it leads that side's squad, and optionally where it starts in place of its
## side's placement; `{}` = no human), `wait_nav` (`stage` waits for the navigation maps; on),
## `spawn_clearance` (px a character is dropped clear of furniture, twice that of another combatant;
## 20), `invader_margin` (px out of the house the invaders' group point is drawn; 80) and `overlays`
## (the debug overlays the match starts with, `{ show_<x>: bool }` by `OverlayRegistry` flag: the
## navigation holes, the squad leaders and each NPC's own; a flag it does not name starts off;
## `{}`).
static func spec(overrides: Dictionary = {}) -> Dictionary:
	var out := {
		"seed": 0,
		"plan": "",
		"entrance": Vector2.ZERO,
		"house": null,
		"defenders": { "count": 1, "loadout": DEFENDER_LOADOUT.duplicate(true), "at": [] },
		"invaders": { "count": 1, "loadout": INVADER_LOADOUT.duplicate(true), "at": [] },
		"human": {},
		"wait_nav": true,
		"spawn_clearance": 20.0,
		"invader_margin": 80.0,
		"overlays": {},
	}
	for key in overrides:
		if (key == "defenders" or key == "invaders") and overrides[key] is Dictionary:
			out[key] = (out[key] as Dictionary).merged(overrides[key], true)
		else:
			out[key] = overrides[key]
	return out


## The match spec of the setup window's `config` (`SetupMenu`'s `{ mode, side, seed, lead,
## defenders, invaders }`, each side `{ count, weapon, magazine, spares, stuns, frags, outfit }`)
## laid over `base` (a spec, e.g. Main's exports'): the config's `seed`; each side's `count` and
## the loadout keys it names (`SETUP_LOADOUT_KEYS`) over the base side's loadout, a side the config
## leaves out keeping the base's; and the human: in a played match (`mode` "play") the base's human
## on the config's `side`, leading it with `lead`; in any other mode none; a config with no `mode`
## keeps the base's human. An endless run (`mode` "endless") of no NPC at all is one a side, since
## there would be nothing to watch.
static func spec_from_setup(config: Dictionary, base: Dictionary = {}) -> Dictionary:
	var out := spec(base)
	out["seed"] = int(config.get("seed", out["seed"]))
	for side in ["defenders", "invaders"]:
		var chosen: Variant = config.get(side)
		if not chosen is Dictionary:
			continue
		var into: Dictionary = (out[side] as Dictionary).duplicate()
		into["count"] = int(chosen.get("count", into.get("count", 0)))
		var loadout: Dictionary = (into.get("loadout", {}) as Dictionary).duplicate()
		for key in SETUP_LOADOUT_KEYS:
			if chosen.has(key):
				loadout[key] = chosen[key]
		into["loadout"] = loadout
		out[side] = into
	var mode := str(config.get("mode", ""))
	if mode != "" and mode != "play":
		out["human"] = {}
	elif out["human"] is Dictionary and not (out["human"] as Dictionary).is_empty():
		var human: Dictionary = (out["human"] as Dictionary).duplicate()
		human["side"] = StringName(config.get("side", human.get("side", &"defender")))
		human["lead"] = bool(config.get("lead", false))
		out["human"] = human
	if (mode == "endless"
			and int(out["defenders"]["count"]) + int(out["invaders"]["count"]) == 0):
		out["defenders"]["count"] = 1
		out["invaders"]["count"] = 1
	return out


## An endless run's next match spec, drawn from `rng` over `base` (the match before it): a fresh
## seed (0, which the caller resolves), each side's count drawn from 1..its most in `most` (`{
## defenders, invaders }`: the counts chosen in setup; a side whose most is 0 stays empty), in that
## order, then a random gun and outfit for each side (`LoadoutConfig.random`), defenders first, with
## the grenade counts its base loadout carries.
static func random_spec(
	rng: RandomNumberGenerator,
	base: Dictionary,
	most: Dictionary,
) -> Dictionary:
	var out := spec(base)
	out["seed"] = 0
	for side in ["defenders", "invaders"]:
		var top := int(most.get(side, 0))
		out[side] = (out[side] as Dictionary).duplicate()
		out[side]["count"] = 0 if top <= 0 else rng.randi_range(1, top)
	for side in ["defenders", "invaders"]:
		var kept := LoadoutConfig.grenade_counts(out[side].get("loadout", {}))
		# Laid over the draw, which names no grenades of its own (0 + 0).
		out[side]["loadout"] = LoadoutConfig.random(rng).merged(kept, true)
	return out


## Build the whole match of `match_spec` under `world`: `stage`, then `populate`. A coroutine (the
## stage may wait for the navigation maps): await it. Returns the match handle.
static func build(match_spec: Dictionary, world: Node2D) -> Dictionary:
	var staged: Dictionary = await stage(match_spec, world)
	if staged.is_empty():
		return {}
	return populate(staged, match_spec)


## Populate the staged match `handle` (the handle `stage` returned) by `match_spec`: the defenders,
## each at a clear spot in a random room (or at the side's `at` points), then the invader team in
## one group outside the house (round the human's start when the human invades), each NPC bound to
## the house before it joins the tree (`bind_npc`, an invader heading for the front entrance first);
## the human joined to its side (its faction, and its start: the spec's `human.at`, else for a
## defender a clear spot in a random room) under the world, just above the house; everyone armed,
## styled and ranked (`arm`); the squads over them (`squads_over`: the human's stack radio, one
## squad per side and the squad-leaders overlay, shown as the spec's `overlays` says); every other
## debug overlay but the navigation holes (the stage's) started as the spec's `overlays` says
## (`set_overlay`: a flag it does not name off). Placement draws from one RNG seeded with the spec's
## `seed`, so a pinned seed pins the match. Returns the handle with `combatants` (every character in
## the match in spawn order, the human last), `squads` (by faction), `player_stack` (the human's, or
## null) and `leader_overlay`.
static func populate(handle: Dictionary, match_spec: Dictionary) -> Dictionary:
	match_spec = spec(match_spec)
	var spawner := _spawner_for(handle, match_spec)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(match_spec["seed"])
	var human := _human_of(match_spec)
	_place_sides(spawner, match_spec, handle, rng, human)
	var combatants: Array = spawner.combatants.filter(func(c): return is_instance_valid(c))
	if human["node"] != null:
		_join(human, handle, spawner, rng)
		combatants.append(human["node"])
	arm(combatants, match_spec)
	var out := handle.duplicate()
	out["combatants"] = combatants
	_finish(out, match_spec, human)
	return out


## The placement helper (`match_spawner.gd`) for the staged match `handle`, with `match_spec`'s
## clearances, binding each NPC it places by the match's one rule (`bind_npc`, with
## `entry_point_for` its faction).
static func _spawner_for(handle: Dictionary, match_spec: Dictionary) -> RefCounted:
	var rooms: Array = handle["rooms"]
	var openings: Array = handle["openings"]
	var spawner = MATCH_SPAWNER.new()
	spawner.world = handle["world"]
	spawner.spawn_clearance = float(match_spec["spawn_clearance"])
	spawner.invader_margin = float(match_spec["invader_margin"])
	spawner.bind = func(npc: Node) -> void:
		bind_npc(npc, rooms, openings, entry_point_for(npc.get("faction"), openings))
	return spawner


## Place both sides of `match_spec` through `spawner` from `rng` (`_place_side`: a side with `at`
## points at those): the defenders each in a random room, then the invader team beside the front
## entrance of `handle`'s house, round the spec's `human` (`_human_of`) when it invades.
static func _place_sides(
	spawner: RefCounted,
	match_spec: Dictionary,
	handle: Dictionary,
	rng: RandomNumberGenerator,
	human: Dictionary,
) -> void:
	var rooms: Array = handle["rooms"]
	var openings: Array = handle["openings"]
	_place_side(
		spawner,
		match_spec["defenders"],
		MATCH_SPAWNER.DEFENDER_SCENE,
		"Defender",
		func(count: int) -> void:
			for i in count:
				spawner.spawn_defender(rooms, rng, i),
	)
	_place_side(
		spawner,
		match_spec["invaders"],
		MATCH_SPAWNER.INVADER_SCENE,
		"Invader",
		func(count: int) -> void:
			spawner.spawn_invader_team(
				rooms,
				rng,
				count,
				_front_opening(openings),
				_start_of(human) if _invading(human) else Vector2.INF,
			),
	)


## The squads over the match handle `out`'s `combatants` (`squads_over`: the spec's `human`'s stack
## radio, one squad per side and the squad-leaders overlay, shown as `match_spec`'s `overlays`
## says), merged into `out`; then every other debug overlay but the navigation holes (the stage's)
## started as the `overlays` say (`set_overlay`: a flag it does not name off).
static func _finish(out: Dictionary, match_spec: Dictionary, human: Dictionary) -> void:
	var overlays: Dictionary = match_spec["overlays"]
	var squads_spec := SquadsSpec.new()
	squads_spec.members = out["combatants"]
	squads_spec.openings = out["openings"]
	squads_spec.rooms = out["rooms"]
	squads_spec.human = human
	out.merge(
		squads_over(
			out["world"],
			squads_spec,
			bool(overlays.get(OVERLAY_REGISTRY.LEADERS, false)),
		),
	)
	for flag in OVERLAY_REGISTRY.defaults():
		if flag != OVERLAY_REGISTRY.NAV_HOLES and flag != OVERLAY_REGISTRY.LEADERS:
			set_overlay(out, flag, bool(overlays.get(flag, false)))


## Place the side `side` (the spec's `defenders` / `invaders`) through `spawner`: at its `at`
## points, each a `scene` named from `base` (`npc_name`), or, when it names none, its `count` by the
## side's own rule, `place` (called with the count).
static func _place_side(
	spawner: RefCounted,
	side: Dictionary,
	scene: PackedScene,
	base: String,
	place: Callable,
) -> void:
	var at: Array = side.get("at", [])
	if at.is_empty():
		place.call(int(side.get("count", 0)))
	for i in at.size():
		spawner.add_npc(scene, spawner.npc_name(base, i), at[i])


## The world point of the front entrance among `openings` (`WorldGen.get_openings`), or ZERO when
## the house has none.
static func front_entrance(openings: Array) -> Vector2:
	return _front_opening(openings).get("pos", Vector2.ZERO)


## The opening of the front entrance among `openings` (`WorldGen.get_openings`: `{ pos, width,
## front, exit, rooms }`), or `{}` when the house has none.
static func _front_opening(openings: Array) -> Dictionary:
	for o: Dictionary in openings:
		if o.get("front", false):
			return o
	return {}


## Where an NPC of `faction` heads first while outside every room (`bind_npc`'s `entry_point`): an
## invader the front entrance among `openings` (`front_entrance`), a defender nowhere (ZERO).
static func entry_point_for(faction: Variant, openings: Array) -> Vector2:
	return Vector2.ZERO if faction == DEFENDER_FACTION else front_entrance(openings)


## Arm `characters` (the match's combatants, the human included) with their side's loadout from
## `match_spec` (`defenders` / `invaders` `loadout`, by each one's faction) through
## `LoadoutConfig.apply`: the chosen gun with its magazine and spares, or for "random" one gun drawn
## per character, its grenades and its outfit; and style each as it is armed (`style`). The guns are
## drawn from an RNG seeded with the spec's `seed` XOR `LOADOUT_SEED_SALT`, so a pinned seed pins
## them without shifting the placement.
static func arm(characters: Array, match_spec: Dictionary) -> void:
	match_spec = spec(match_spec)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(match_spec["seed"]) ^ LOADOUT_SEED_SALT
	var styles := style(characters, match_spec)
	for i in characters.size():
		var character: Node = characters[i]
		var defending: bool = character.get("faction") == DEFENDER_FACTION
		var side: Dictionary = match_spec["defenders" if defending else "invaders"]
		var gun := LoadoutConfig.apply(character, side["loadout"], rng, styles[i])
		if gun != &"":
			GameLog.say(
				"%s is armed with the %s" % [character.name, character.inventory.item_name()],
			)


## How each of `characters` is drawn (`docs/outfits.md`, styles), one `LoadoutConfig.apply` style
## each (`{ look, seed, weapon, rank? }`), from an RNG seeded with the spec's `seed` XOR
## `STYLE_SEED_SALT` (so the styles never shift the guns): its first draw is the match's police
## unit, one of the invaders' styles, worn by every invader, the human invader too, the first of
## them its lead (rank 2) and the second its sergeant (1), the rest troopers (0); each defender, the
## human defender too, draws one of the defenders' styles; then each draws a look seed and one of
## its style's weapon styles. A human invader who leads (the spec's `human.lead`) is the unit's lead
## instead, and the NPC invaders are ranked from the sergeant down; the draws are the same.
static func style(characters: Array, match_spec: Dictionary) -> Array:
	match_spec = spec(match_spec)
	var looks := RandomNumberGenerator.new()
	looks.seed = int(match_spec["seed"]) ^ STYLE_SEED_SALT
	var units := styles_of(INVADER_FACTION)
	var crews := styles_of(DEFENDER_FACTION)
	var unit: StringName = (units[looks.randi() % units.size()]
			if not units.is_empty()
			else CharacterStyleConfig.default_style)
	var lead := _leading_invader(characters, match_spec)
	# The unit's first is its lead, the next its sergeant, the rest troopers.
	var rank := 1 if lead != null else 2
	var out: Array = []
	for character in characters:
		var defending: bool = character.get("faction") == DEFENDER_FACTION
		var drawn := _drawn_style(looks, unit, crews, defending)
		if not defending and lead != null and character == lead:
			drawn["rank"] = 2
		elif not defending:
			drawn["rank"] = rank
			rank = maxi(rank - 1, 0)
		out.append(drawn)
	return out


## The spec's human when it leads the unit (`human.lead`, an invader among `characters`), else null.
static func _leading_invader(characters: Array, match_spec: Dictionary) -> Node:
	var human := _human_of(match_spec)
	var node: Node = human.get("node")
	if (human["lead"]
			and node != null
			and characters.has(node)
			and node.get("faction") == INVADER_FACTION):
		return node
	return null


## One character's style drawn from `looks`: the unit's `unit` look, or for a `defending` one one of
## the `crews` looks (when there are any); then its look seed and one of that look's weapon styles.
## `{ look, seed, weapon }`.
static func _drawn_style(
	looks: RandomNumberGenerator,
	unit: StringName,
	crews: Array[StringName],
	defending: bool,
) -> Dictionary:
	var look: StringName = unit
	if defending and not crews.is_empty():
		look = crews[looks.randi() % crews.size()]
	var weapons: Array = CharacterStyleConfig.styles[look].get("weapons", [&"police"])
	return {
		"look": look,
		"seed": looks.randi(),
		"weapon": weapons[looks.randi() % weapons.size()],
	}


## The styles (`CharacterStyleConfig.styles` keys) of the side `faction` fights on, in table order.
static func styles_of(faction: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for key: StringName in CharacterStyleConfig.styles:
		if CharacterStyleConfig.styles[key].get("side", &"") == faction:
			out.append(key)
	return out


## One squad per side over `squads_spec`'s `members` (in spawn order), the house's `openings` and
## `rooms`, under `world`, each member handed its own (`bind_squad`; `docs/leadership.md` LD3): the
## leader by the squad's rule (rank, then spawn order), so after `arm` has ranked the unit; the
## human's side is led by the human when its `human` (the spec's `{ node, side, lead }`) says it
## leads. The human is handed its squad through `stack`, its stack radio, with `own_claims` on the
## invaders' side only (D29). Each squad keeps its members' claims `claim_ttl` s, or, at
## `CLAIM_TTL_OF_NPCS`, as long as the side's NPCs keep a callout (`callout_ttl_of`). Returns the
## squads by faction.
static func build_squads(world: Node, squads_spec: SquadsSpec, stack: Node = null) -> Dictionary:
	var squads := {}
	var human := squads_spec.human
	var human_node: Node = human.get("node")
	if human_node != null and not is_instance_valid(human_node):
		human_node = null
	for faction in [DEFENDER_FACTION, INVADER_FACTION]:
		var members: Array = squads_spec.members.filter(
			func(c): return is_instance_valid(c) and c.get("faction") == faction,
		)
		if members.is_empty():
			continue
		var squad: Node = SQUAD.new()
		squad.name = "Squad_%s" % faction
		world.add_child(squad)
		var roster := SquadRoster.new()
		roster.faction = faction
		roster.members = members
		roster.human = (human_node
				if human.get("lead", false) and human_node != null and members.has(human_node)
				else null)
		var ttl := squads_spec.claim_ttl
		roster.claim_ttl = ttl if ttl >= 0.0 else callout_ttl_of(members)
		squad.setup(roster, squads_spec.openings, squads_spec.rooms)
		for member in members:
			bind_squad(
				member,
				squad,
				stack if stack != null and member == human_node else null,
				faction == INVADER_FACTION,
			)
		squads[faction] = squad
	return squads


## The squad-leaders debug overlay (`docs/leadership.md` LD12) of the squads `squads` (by faction,
## as `build_squads` returns them) under `world`: a `LeaderOverlay` watching every squad's `view()`,
## hidden until `set_overlay` shows it. Returned, for the match handle's `leader_overlay`.
static func build_leader_overlay(world: Node, squads: Dictionary) -> Node2D:
	var overlay: Node2D = LEADER_OVERLAY.new()
	overlay.name = "LeaderOverlay"
	world.add_child(overlay)
	overlay.watch(squads.values().map(func(squad): return squad.view))
	return overlay


## Turn the debug overlay `flag` (an `OverlayRegistry` row) on or off on the match `handle` (a
## handle, or any dict with its `nav_debug`, `leader_overlay` and `combatants`): the navigation
## holes on its `nav_debug` (redrawn, since a paused overlay's own `_process` may not run), the
## squad leaders on its `leader_overlay` (a world with no squads has none: nothing happens), and
## any NPC's own overlay on each NPC among its `combatants` (a character with an AI controller,
## interface 7: the human has none of those overlays) through `OverlayRegistry.apply`. The
## performance flag is the caller's own overlay: nothing here.
static func set_overlay(handle: Dictionary, flag: String, on: bool) -> void:
	if flag == OVERLAY_REGISTRY.NAV_HOLES:
		var nav_debug: Variant = handle.get("nav_debug")
		if is_instance_valid(nav_debug):
			nav_debug.show_holes = on
			nav_debug.queue_redraw()
	elif flag == OVERLAY_REGISTRY.LEADERS:
		var overlay: Variant = handle.get("leader_overlay")
		if is_instance_valid(overlay):
			overlay.show_leaders = on
	elif not OVERLAY_REGISTRY.is_global(flag):
		for npc: Variant in handle.get("combatants", []):
			if is_instance_valid(npc) and _controller_of(npc) != null:
				OVERLAY_REGISTRY.apply(npc, { flag: on })


## Build the world stage of a match under `world`, the node everything the match builds lives under,
## from `match_spec` (`seed`, `plan`, `entrance`, `house`, `wait_nav`, and `overlays` for the holes
## overlay's start). With no `house` it generates one (`WorldGen.generate` from the spec's `seed`,
## `plan` and front `entrance`); a caller that built its own (a hand-laid layout or an arena, its
## objects already placed so the bake carves them) names it, and it is moved under `world` when it
## stands elsewhere. Then the nav map (`NavBuilder.build`), its holes overlay and its re-baker, and
## the dusk lighting seeded by `seed`. With `wait_nav` the world is stepped two physics frames (the
## walls' colliders go live on a step), then until `NavBuilder.ready` holds on the planning map and
## on the steering map, so an NPC placed afterwards never plans or walks on a map still showing
## another navmesh (at most `NAV_SYNC_MS` of real time; an error past it). A coroutine: await it.
## Returns the handle `{ world, house, rooms, openings, nav_region, nav_debug }`, or `{}` when
## `world` was freed during the wait (the match torn down).
static func stage(match_spec: Dictionary, world: Node2D) -> Dictionary:
	match_spec = spec(match_spec)
	var house: Node2D = match_spec["house"]
	if house == null:
		house = WorldGen.generate(
			int(match_spec["seed"]),
			String(match_spec["plan"]),
			match_spec["entrance"],
			world,
		)
	elif house.get_parent() == null:
		world.add_child(house)
	elif house.get_parent() != world:
		house.reparent(world, true)
	var rooms := WorldGen.get_rooms(house)
	var nav_region := NavBuilder.build(house, rooms, world)
	var nav_debug: Node2D = NAV_DEBUG.new()
	nav_debug.name = "NavDebug"
	world.add_child(nav_debug)
	nav_debug.setup(house)
	set_overlay(
		{ "nav_debug": nav_debug },
		OVERLAY_REGISTRY.NAV_HOLES,
		bool((match_spec["overlays"] as Dictionary).get(OVERLAY_REGISTRY.NAV_HOLES, false)),
	)
	# The re-baker keeps the navmesh in step with shoved furniture and refreshes the overlay.
	var nav_updater: Node = NAV_UPDATER.new()
	nav_updater.name = "NavUpdater"
	world.add_child(nav_updater)
	nav_updater.setup(nav_region, house, rooms, nav_debug)
	WorldLighting.light(world, int(match_spec["seed"]), rooms)
	if bool(match_spec["wait_nav"]):
		await _wait_nav(world)
		if not is_instance_valid(world):
			return {}
	return {
		"world": world,
		"house": house,
		"rooms": rooms,
		"openings": WorldGen.get_openings(house),
		"nav_region": nav_region,
		"nav_debug": nav_debug,
	}


## Step `world` two physics frames, then until its navigation map and the steering map that goes
## with it (`NavBuilder.steering_map`, when it has one) are `NavBuilder.ready`, at most
## `NAV_SYNC_MS` of real time. Ends early when `world` leaves the tree or is freed.
static func _wait_nav(world: Node2D) -> void:
	for i in 2:
		if not (is_instance_valid(world) and world.is_inside_tree()):
			return
		await world.get_tree().physics_frame
	var deadline := Time.get_ticks_msec() + NAV_SYNC_MS
	while is_instance_valid(world) and world.is_inside_tree():
		var map: RID = world.get_world_2d().navigation_map
		var steering := NavBuilder.steering_map(map)
		if NavBuilder.ready(map) and (not steering.is_valid() or NavBuilder.ready(steering)):
			return
		if Time.get_ticks_msec() > deadline:
			push_error("MatchBuilder: the navigation maps did not take in the house within %d ms"
					% NAV_SYNC_MS)
			return
		await world.get_tree().physics_frame


## The squads over `squads_spec` (its `members`, a match's characters in spawn order after `arm`
## has ranked them, and the house's `openings` and `rooms`): its `human` (`human.node`, leading its
## side when `human.lead`) first handed its stack radio (`bind_player`), then one squad per side
## (`build_squads`, each keeping its members' claims `claim_ttl` s, or, at `CLAIM_TTL_OF_NPCS`, as
## long as its NPCs keep a callout) and the squad-leaders overlay over them
## (`build_leader_overlay`), shown when `leaders`. `populate` ends with it, and the Testing world
## builds the squads a test declares through it. Returns `{ squads, player_stack, leader_overlay }`
## (`player_stack` null with no human), for the match handle.
static func squads_over(world: Node, squads_spec: SquadsSpec, leaders := false) -> Dictionary:
	var human_node: Variant = squads_spec.human.get("node")
	var stack: Node = (bind_player(human_node, squads_spec.rooms, squads_spec.openings)
			if is_instance_valid(human_node)
			else null)
	var squads := build_squads(world, squads_spec, stack)
	var overlay := build_leader_overlay(world, squads)
	set_overlay({ "leader_overlay": overlay }, OVERLAY_REGISTRY.LEADERS, leaders)
	return { "squads": squads, "player_stack": stack, "leader_overlay": overlay }


## Hand an NPC's controller the house: its `rooms` (world-space rects), its `openings` (the
## doorways, for tactical entry) and, when given, an `entry_point` it heads for first while outside
## every room. Called BEFORE the NPC joins the tree, so its first tick already knows them; the
## controller is found by its contract (interface 7: the child with `control` and `rooms`), since
## the `npc_controllers` group is joined only in its `_ready`. An NPC with no such child is left
## alone.
static func bind_npc(
	npc: Node,
	rooms: Array,
	openings: Array,
	entry_point := Vector2.ZERO,
) -> void:
	var brain := _controller_of(npc)
	if brain == null:
		return
	brain.rooms = rooms
	if "openings" in brain:
		brain.openings = openings
	if entry_point != Vector2.ZERO and "entry_point" in brain:
		brain.entry_point = entry_point


## Hand a member its side's squad (`ai/team/squad.gd`, `docs/leadership.md` LD3), as `bind_npc`
## hands it the house: an NPC's controller's `squad`, found by the same contract, and the human's
## `stack`, the stack radio `bind_player` returned for it (its `squad`, LD17), with `own_claims`
## (LD24, D29: true for the invaders' side only, whose leader's own claim at a doorway rallies the
## team).
static func bind_squad(npc: Node, squad: Node, stack: Node = null, own_claims := false) -> void:
	if stack != null and "squad" in stack:
		stack.squad = squad
		stack.own_claims = own_claims
	var brain := _controller_of(npc)
	if brain != null and "squad" in brain:
		brain.squad = squad


## How long the NPCs among `members` keep a callout they heard: the `callout_ttl` of the first one's
## controller (0 with no NPC among them). Handed to the side's squad (`Squad.setup`), which keeps
## its members' entry claims as long.
static func callout_ttl_of(members: Array) -> float:
	for m in members:
		if not (m is Node and is_instance_valid(m)):
			continue
		var brain := _controller_of(m)
		if brain != null and "callout_ttl" in brain:
			return float(brain.callout_ttl)
	return 0.0


## Give the human the stack radio, as `bind_npc` hands an NPC its doorways: a `PlayerStack` child of
## `player` that knows the house's `rooms` and `openings`. Returned, for the stack markers to watch.
static func bind_player(player: Node, rooms: Array, openings: Array) -> Node:
	return PLAYER_STACK.attach(player, rooms, openings)


## Put the spec's human (`_human_of`) in the staged match `handle` on its side: that side's faction
## (so its NPCs treat it as an ally) and its start: its `at` when given (not INF), else for a
## defender a clear spot in a random room drawn from `rng` through `spawner` (an invader starts
## where it stands). It is moved under the match's world, keeping where it stands, just above the
## house so the draw order stays house < human < NPCs.
static func _join(
	human: Dictionary,
	handle: Dictionary,
	spawner: RefCounted,
	rng: RandomNumberGenerator,
) -> void:
	var node: Node2D = human["node"]
	var invading := _invading(human)
	var at: Vector2 = human["at"]
	var rooms: Array = handle["rooms"]
	node.set("faction", INVADER_FACTION if invading else DEFENDER_FACTION)
	if at != Vector2.INF:
		node.global_position = at
	elif not invading and not rooms.is_empty():
		node.global_position = spawner.clear_spot(rooms[rng.randi() % rooms.size()]["rect"], rng)
	var world: Node2D = handle["world"]
	if node.get_parent() != world:
		node.reparent(world, true)
	var house: Node = handle["house"]
	world.move_child(node, house.get_index() + 1)


## Whether the spec's human (`_human_of`) is there and joins the invaders.
static func _invading(human: Dictionary) -> bool:
	return human["node"] != null and human["side"] != &"defender"


## The spec's human as `{ node, side, lead, at }`: `node` null when there is none (or it was
## freed), `at` INF when it names no start.
static func _human_of(match_spec: Dictionary) -> Dictionary:
	var given: Variant = match_spec.get("human")
	var human: Dictionary = given if given is Dictionary else {}
	var node: Variant = human.get("node")
	var at: Variant = human.get("at")
	return {
		"node": node if is_instance_valid(node) and node is Node2D else null,
		"side": StringName(human.get("side", &"defender")),
		"lead": bool(human.get("lead", false)),
		"at": at if at is Vector2 else Vector2.INF,
	}


## Where the spec's human (`_human_of`) starts: its `at`, else where it stands.
static func _start_of(human: Dictionary) -> Vector2:
	return human["at"] if human["at"] != Vector2.INF else (human["node"] as Node2D).global_position


## The controller of `npc` (interface 7): its child with `control` and `rooms`, else null.
static func _controller_of(npc: Node) -> Node:
	for child in npc.get_children():
		if child.has_method("control") and "rooms" in child:
			return child
	return null
