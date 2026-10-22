class_name MatchBuilder
extends RefCounted
## Composition-root module (beside `main.gd` and `match_spawner.gd`): builds a match for Main and
## for the Testing domain's world alike, so both compose one the same way. `stage` is the world
## stage: the house (generated, or one the caller already built), its navigation map with the
## holes overlay and the re-baker (interface 9), and the dusk lighting (interface 20), then, when
## asked, a wait until both navigation maps answer with this house. `bind_npc` is the one rule an
## NPC's controller is handed the house by (before the NPC joins the tree), `bind_squad` /
## `bind_player` / `callout_ttl_of` the squad's and the human's (interfaces 17, 21). Like
## `main.gd` it knows the domains it wires; nothing in them knows it.

## Draw-only overlay for the baked navmesh's holes, furniture and characters at rest (Navigation
## domain).
const NAV_DEBUG := preload("res://scenes/navigation/nav_debug.gd")
## Periodic navmesh re-baker: re-carves furniture holes as pieces are shoved around (Navigation
## domain).
const NAV_UPDATER := preload("res://scenes/navigation/nav_updater.gd")
## The human's side of the entry radio: it reserves the human a slot in an AI stack near it
## (`docs/tactical-entry.md` E16).
const PLAYER_STACK := preload("res://scenes/ai/team/player_stack.gd")
## Most wall-clock ms `stage` waits for the navigation maps to answer with the house's navmesh (a
## map synchronizes on a worker thread, so a loaded machine is slow in real time, not in frames).
const NAV_SYNC_MS := 5000


## Build the world stage of a match under `world`, the node everything the match builds lives under,
## from `spec` (`seed`, `plan`, `entrance`, `wait_nav`). With no `house` it generates one
## (`WorldGen.generate` from the spec's `seed`, `plan` and front `entrance`); a caller that built
## its own (a test's arena or layout, its objects already placed so the bake carves them) passes it.
## Then the nav map (`NavBuilder.build`), its holes overlay and its re-baker, and the dusk lighting
## seeded by `seed`. With `wait_nav` the world is stepped two physics frames (the walls' colliders
## go live on a step), then until `NavBuilder.ready` holds on the planning map and on the steering
## map, so an NPC placed afterwards never plans or walks on a map still showing another navmesh (at
## most `NAV_SYNC_MS` of real time; an error past it). A coroutine: await it. Returns the handle
## `{ world, house, rooms, openings, nav_region, nav_debug }`.
static func stage(spec: Dictionary, world: Node2D, house: Node2D = null) -> Dictionary:
	if house == null:
		house = WorldGen.generate(
			int(spec.get("seed", 0)),
			String(spec.get("plan", "")),
			spec.get("entrance", Vector2.ZERO),
			world,
		)
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
	WorldLighting.light(world, int(spec.get("seed", 0)), rooms)
	if bool(spec.get("wait_nav", false)):
		await _wait_nav(world)
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
## `NAV_SYNC_MS` of real time. Ends early when `world` leaves the tree.
static func _wait_nav(world: Node2D) -> void:
	for i in 2:
		if not world.is_inside_tree():
			return
		await world.get_tree().physics_frame
	var deadline := Time.get_ticks_msec() + NAV_SYNC_MS
	while world.is_inside_tree():
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


## The controller of `npc` (interface 7): its child with `control` and `rooms`, else null.
static func _controller_of(npc: Node) -> Node:
	for child in npc.get_children():
		if child.has_method("control") and "rooms" in child:
			return child
	return null
