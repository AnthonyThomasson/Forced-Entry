class_name MatchBuilder
extends RefCounted
## Composition-root module (beside `main.gd` and `match_spawner.gd`): builds a match for Main and
## for the Testing domain's world alike, so both compose one the same way. A match spec goes in (a
## plain dict `spec` fills with defaults: the house's `seed` / `plan` / `entrance`, or a `house`
## already built, each side's `count`, `loadout` and optional `at`, the `human`, `wait_nav`,
## `spawn_clearance`, `invader_margin`) and a match handle comes out (a plain dict: `world`,
## `house`, `rooms`, `openings`, `nav_region`, `nav_debug`, then `combatants`, `squads`,
## `player_stack`). `build` is its two stages: `stage`, the world stage (the house, its navigation
## map with the holes overlay and the re-baker, interface 9, the dusk lighting, interface 20, then,
## when asked, a wait until both navigation maps answer with this house), and `populate` (each side
## placed through the match spawner, the human joined, everyone armed, styled and ranked, one squad
## per side). `bind_npc` is the one rule an NPC's controller is handed the house by (before the NPC
## joins the tree), `bind_squad` / `bind_player` / `callout_ttl_of` the squad's and the human's
## (interfaces 17, 21). `spec_from_setup` reads the setup window's choices into a spec,
## `random_spec` draws an endless run's next one.
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
## The keys of a side's loadout the setup window chooses (its per-side config, beside `count`).
const SETUP_LOADOUT_KEYS := ["weapon", "magazine", "spares", "stuns", "frags", "outfit"]
## Most wall-clock ms `stage` waits for the navigation maps to answer with the house's navmesh (a
## map synchronizes on a worker thread, so a loaded machine is slow in real time, not in frames).
const NAV_SYNC_MS := 5000


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
## 20) and `invader_margin` (px out of the house the invaders' group point is drawn; 80).
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


## Populate the staged match `match` (the handle `stage` returned) by `match_spec`: the defenders,
## each at a clear spot in a random room (or at the side's `at` points), then the invader team in
## one group outside the house (round the human's start when the human invades), each NPC bound to
## the house (an invader heading for the front entrance first); the human joined to its side (its
## faction, and its start: the spec's `human.at`, else for a defender a clear spot in a random
## room) under the world, just above the house, and given its stack radio; everyone armed, styled
## and ranked (`arm`); one squad per side (`build_squads`). Placement draws from one RNG seeded with
## the spec's `seed`, so a pinned seed pins the match. Returns the handle with `combatants` (every
## character in the match in spawn order, the human last), `squads` (by faction) and `player_stack`
## (the human's, or null).
static func populate(match: Dictionary, match_spec: Dictionary) -> Dictionary:
	match_spec = spec(match_spec)
	var world: Node2D = match["world"]
	var rooms: Array = match["rooms"]
	var openings: Array = match["openings"]
	var spawner = MATCH_SPAWNER.new()
	spawner.world = world
	spawner.spawn_clearance = float(match_spec["spawn_clearance"])
	spawner.invader_margin = float(match_spec["invader_margin"])
	spawner.openings = openings
	var front := front_entrance(openings)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(match_spec["seed"])
	var human := _human_of(match_spec)
	var human_node: Node2D = human.get("node")
	var human_invader: bool = human_node != null and human["side"] != &"defender"
	var defenders: Dictionary = match_spec["defenders"]
	var at: Array = defenders.get("at", [])
	if at.is_empty():
		for i in int(defenders.get("count", 0)):
			spawner.spawn_defender(rooms, rng, i)
	for i in at.size():
		spawner.add_npc(
			MATCH_SPAWNER.DEFENDER_SCENE,
			spawner.npc_name("Defender", i),
			at[i],
			rooms,
		)
	var invaders: Dictionary = match_spec["invaders"]
	at = invaders.get("at", [])
	if at.is_empty():
		spawner.spawn_invader_team(
			rooms,
			rng,
			int(invaders.get("count", 0)),
			front,
			_start_of(human) if human_invader else Vector2.INF,
		)
	for i in at.size():
		spawner.add_npc(
			MATCH_SPAWNER.INVADER_SCENE,
			spawner.npc_name("Invader", i),
			at[i],
			rooms,
			front,
		)
	var combatants: Array = spawner.combatants.filter(func(c): return is_instance_valid(c))
	var stack: Node = null
	if human_node != null:
		_join(human_node, human_invader, human["at"], match, spawner, rng)
		combatants.append(human_node)
		stack = bind_player(human_node, rooms, openings)
	arm(combatants, match_spec)
	var out := match.duplicate()
	out["combatants"] = combatants
	out["squads"] = build_squads(world, combatants, openings, rooms, human, stack)
	out["player_stack"] = stack
	return out


## The front entrance among `openings` (`WorldGen.get_openings`): its world point, or ZERO when the
## house has none.
static func front_entrance(openings: Array) -> Vector2:
	for o: Dictionary in openings:
		if o.get("front", false):
			return o["pos"]
	return Vector2.ZERO


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
			GameLog.say("%s is armed with the %s" % [character.name, character.item_name()])


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
			else CharacterConfig.default_style)
	var human := _human_of(match_spec)
	var human_node: Node = human.get("node")
	var human_lead: bool = (human["lead"]
			and human_node != null
			and characters.has(human_node)
			and human_node.get("faction") == INVADER_FACTION)
	# The unit's first is its lead, the next its sergeant, the rest troopers.
	var rank := 1 if human_lead else 2
	var out: Array = []
	for character in characters:
		var defending: bool = character.get("faction") == DEFENDER_FACTION
		var look: StringName = unit
		if defending and not crews.is_empty():
			look = crews[looks.randi() % crews.size()]
		var weapons: Array = CharacterConfig.styles[look].get("weapons", [&"police"])
		var drawn := {
			"look": look,
			"seed": looks.randi(),
			"weapon": weapons[looks.randi() % weapons.size()],
		}
		if not defending and human_lead and character == human_node:
			drawn["rank"] = 2
		elif not defending:
			drawn["rank"] = rank
			rank = maxi(rank - 1, 0)
		out.append(drawn)
	return out


## The styles (`CharacterConfig.styles` keys) of the side `faction` fights on, in table order.
static func styles_of(faction: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for key: StringName in CharacterConfig.styles:
		if CharacterConfig.styles[key].get("side", &"") == faction:
			out.append(key)
	return out


## One squad per side over `combatants` (in spawn order), the house's `openings` and `rooms`, under
## `world`, each member handed its own (`bind_squad`; `docs/leadership.md` LD3): the leader by the
## squad's rule (rank, then spawn order), so after `arm` has ranked the unit; the human's side is
## led by the human when `human` (the spec's `{ node, side, lead }`) says it leads. The human is
## handed its squad through `stack`, its stack radio, with `own_claims` on the invaders' side only
## (D29). Returns the squads by faction.
static func build_squads(
	world: Node,
	combatants: Array,
	openings: Array,
	rooms: Array,
	human: Dictionary = {},
	stack: Node = null,
) -> Dictionary:
	var squads := {}
	var human_node: Node = human.get("node")
	if human_node != null and not is_instance_valid(human_node):
		human_node = null
	for faction in [DEFENDER_FACTION, INVADER_FACTION]:
		var members: Array = combatants.filter(
			func(c): return is_instance_valid(c) and c.get("faction") == faction,
		)
		if members.is_empty():
			continue
		var squad: Node = SQUAD.new()
		squad.name = "Squad_%s" % faction
		world.add_child(squad)
		var leader: Node = (human_node
				if human.get("lead", false) and human_node != null and members.has(human_node)
				else null)
		squad.setup(faction, members, openings, rooms, leader, callout_ttl_of(members))
		for member in members:
			bind_squad(
				member,
				squad,
				stack if stack != null and member == human_node else null,
				faction == INVADER_FACTION,
			)
		squads[faction] = squad
	return squads


## Build the world stage of a match under `world`, the node everything the match builds lives under,
## from `match_spec` (`seed`, `plan`, `entrance`, `house`, `wait_nav`). With no `house` it generates
## one (`WorldGen.generate` from the spec's `seed`, `plan` and front `entrance`); a caller that
## built its own (a hand-laid layout or an arena, its objects already placed so the bake carves
## them) names it, and it is moved under `world` when it stands elsewhere. Then the nav map
## (`NavBuilder.build`), its holes overlay and its re-baker, and the dusk lighting seeded by `seed`.
## With `wait_nav` the world is stepped two physics frames (the walls' colliders go live on a step),
## then until `NavBuilder.ready` holds on the planning map and on the steering map, so an NPC placed
## afterwards never plans or walks on a map still showing another navmesh (at most `NAV_SYNC_MS` of
## real time; an error past it). A coroutine: await it. Returns the handle
## `{ world, house, rooms, openings, nav_region, nav_debug }`, or `{}` when `world` was freed during
## the wait (the match torn down).
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


## Put the human `human` in the staged match `match` on its side: that side's faction (so its NPCs
## treat it as an ally) and its start: `at` when given (not INF), else for a defender a clear spot
## in a random room drawn from `rng` (an invader starts where it stands). It is moved under the
## match's world, keeping where it stands, just above the house so the draw order stays house <
## human < NPCs.
static func _join(
	human: Node2D,
	invading: bool,
	at: Vector2,
	match: Dictionary,
	spawner: RefCounted,
	rng: RandomNumberGenerator,
) -> void:
	var rooms: Array = match["rooms"]
	human.set("faction", INVADER_FACTION if invading else DEFENDER_FACTION)
	if at != Vector2.INF:
		human.global_position = at
	elif not invading and not rooms.is_empty():
		human.global_position = spawner.clear_spot(rooms[rng.randi() % rooms.size()]["rect"], rng)
	var world: Node2D = match["world"]
	if human.get_parent() != world:
		human.reparent(world, true)
	var house: Node = match["house"]
	world.move_child(human, house.get_index() + 1)


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
