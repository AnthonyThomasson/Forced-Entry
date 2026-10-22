extends GameTest
## Interface 9 and the match's world stage (`MatchBuilder.stage`): with `wait_nav` the stage waits
## until both navigation maps (the planning map and the steering map, `NavBuilder.steering_map`)
## answer with the new house, so on the frame the first NPC enters the tree both are
## `NavBuilder.ready` and each map's closest point to a room's centre belongs to the house's own
## region; and no NPC's first walk target lies off the house's navmesh (an NPC that plans on a map
## still showing no navmesh snaps nothing and walks to points off it). Main's match waits the same
## way, and a match torn down while it waits (Escape back to the setup window) places nobody and
## logs nothing.
##
## Two matches, each in a world of its own (a `SubViewport` with its own `World2D`, so fresh
## navigation maps, as each match's are): first a match the module builds
## (`MatchBuilder.build`: its stage, then its population); then Main run whole, `_ready` to its
## match, as a scripted restart starts it (the Engine `skip_setup` meta, set while it enters the
## tree and dropped after), with the two children its scene gives it that `_ready` reads (`Player`
## and `SetupMenu`, never opened), as a Watch match of two a side on a pinned house. The NPCs are
## found as they enter the tree (the SceneTree's `node_added`: a character with a controller,
## interface 7), never through Main's members. Scripted Von, the first option offered, so the NPCs
## walk; the settings file is a scratch one, and the listener Main names (`Sound.focus`) is put back
## after.

const MainScript := preload("res://scenes/main.gd")
const PlayerController := preload("res://scenes/character/player_controller.gd")
const PLAYER_SCENE := "res://scenes/character/character_base.tscn"
const SEED := 18
## Where the module's house puts its front entrance.
const ENTRANCE := Vector2(440, 350)
## Where Main's human stands in its scene (Main's anchor: the front entrance is built above it).
const HUMAN_AT := Vector2(440, 420)
const DEFENDERS := 2
const INVADERS := 2
## How far (px) a walk target may lie from the navmesh's closest point and still be on it.
const ON_MESH := 2.0
## How long (s) the NPCs' walks are watched for each one's first target.
const WATCH_S := 5.0


func describe() -> Dictionary:
	return {
		"name": "A match's NPCs enter only once both navigation maps are ready",
		"description": "The world stage waits for the planning and the steering map to answer "
			+ "with the new house before any NPC is placed, and every NPC's first walk target "
			+ "lies on the house's navmesh; Main's match waits the same way, and one torn down "
			+ "during the wait places nobody and logs nothing.",
		"tags": ["setup", "match", "spawn", "navigation"],
		"timeout": 40.0,
		"allowed_logs": [
			"Navigation map synchronization error",
			"NavigationPolygon polygon convex partition failed",
		],
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 300, 300))
	s.von_script([])
	s.switch(&"ai.hostile_on_trespass", false)
	s.set_static(Settings, "path", "user://test_match_nav_ready_settings.json")
	s.set_static(Settings, "setup", {})
	s.set_static(Settings, "overlays", {})
	s.set_static(Settings, "debug", Settings.debug)


func run(t: TestContext) -> void:
	var viewport := _viewport(t)
	var watch := _watch(t, viewport)
	var world := Node2D.new()
	world.name = "World"
	viewport.add_child(world)
	var spec := MatchBuilder.spec({
		"seed": SEED,
		"entrance": ENTRANCE,
		"wait_nav": true,
		"defenders": { "count": DEFENDERS },
		"invaders": { "count": INVADERS },
	})
	await MatchBuilder.build(spec, world)
	await _judge(t, watch, viewport, "the module's match")
	await _free(t, viewport, watch)

	viewport = _viewport(t)
	watch = _watch(t, viewport)
	_start_main(viewport)
	await _judge(t, watch, viewport, "Main's match")
	await _free(t, viewport, watch)

	# Torn down while its maps synchronize (Escape back to the setup window): the wait ends with
	# the match, placing nobody and logging nothing (any error logged fails the test).
	viewport = _viewport(t)
	watch = _watch(t, viewport)
	_start_main(viewport)
	await _free(t, viewport, watch)
	await t.frames(10)
	t.check(
		(watch["entries"] as Array).is_empty(),
		"a match torn down during the wait places nobody (%d entered)"
			% (watch["entries"] as Array).size(),
	)


## A world of its own under the test world: a `SubViewport` with a fresh `World2D`.
func _viewport(t: TestContext) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.world_2d = World2D.new()
	viewport.disable_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	t.world.add_child(viewport)
	return viewport


## Watch every NPC that enters the tree under `viewport`: on its frame, whether each map was ready
## and answered with the house (`entries`), and its first walk target (the agent's target on its
## first path, `targets`). Returns `{ entries, targets, added }` (`added` the connected callable).
func _watch(t: TestContext, viewport: SubViewport) -> Dictionary:
	var watch := { "entries": [], "targets": {} }
	var added := func(node: Node) -> void:
		if not (node is CharacterBody2D and viewport.is_ancestor_of(node)):
			return
		if TestContext.controller_of(node, &"control") == null:
			return
		if node.get_children().all(func(c): return not ("rooms" in c)):
			return
		(watch["entries"] as Array).append(_maps_now(viewport, node))
		for child in node.get_children():
			if child is NavigationAgent2D:
				var agent: NavigationAgent2D = child
				agent.path_changed.connect(func() -> void:
					if not (watch["targets"] as Dictionary).has(node.name):
						watch["targets"][node.name] = {
							"point": agent.target_position, "map": agent.get_navigation_map(),
						})
	watch["added"] = added
	t.world.get_tree().node_added.connect(added)
	return watch


## How the maps of `viewport`'s world stand on the frame `npc` enters: `{ npc, planning, steering,
## planning_house, steering_house }` (`*_house`: the map's closest point to a room's centre belongs
## to the house's own region).
func _maps_now(viewport: SubViewport, npc: Node) -> Dictionary:
	var map: RID = viewport.world_2d.navigation_map
	var steering := NavBuilder.steering_map(map)
	var region := _find_region(viewport)
	var steering_region: NavigationRegion2D = null
	if region != null:
		for child in region.get_children():
			if child is NavigationRegion2D:
				steering_region = child
	var centre := Vector2.INF
	var world := region.get_parent() if region != null else null
	if world != null:
		for child in world.get_children():
			var rooms := WorldGen.get_rooms(child as Node2D) if child is Node2D else []
			if not rooms.is_empty():
				centre = (rooms[0]["rect"] as Rect2).get_center()
	return {
		"npc": String(npc.name),
		"planning": NavBuilder.ready(map),
		"steering": steering.is_valid() and NavBuilder.ready(steering),
		"planning_house": _answers_with(map, region, centre),
		"steering_house": _answers_with(steering, steering_region, centre),
	}


## Whether `map` has synchronized and its closest point to `centre` belongs to `region`.
func _answers_with(map: RID, region: NavigationRegion2D, centre: Vector2) -> bool:
	if region == null or centre == Vector2.INF or not map.is_valid():
		return false
	if NavigationServer2D.map_get_iteration_id(map) == 0:
		return false  # asking a map that never synchronized is an engine error
	return NavigationServer2D.map_get_closest_point_owner(map, centre) == region.get_rid()


## The first NavigationRegion2D under `node` (the planning region the bake added), else null.
func _find_region(node: Node) -> NavigationRegion2D:
	for child in node.get_children():
		if child is NavigationRegion2D:
			return child
		var found := _find_region(child)
		if found != null:
			return found
	return null


## Main as a scripted restart starts it, in `viewport`: a Watch match of `DEFENDERS` and `INVADERS`
## on house `SEED`, Debug off.
func _start_main(viewport: SubViewport) -> void:
	var main: Node2D = MainScript.new()
	main.name = "Main"
	main.set("house_seed", SEED)
	main.set("defender_count", DEFENDERS)
	main.set("invader_count", INVADERS)
	main.set("spectator_mode", true)
	main.set("debug_overlays", false)
	var player: Node2D = (load(PLAYER_SCENE) as PackedScene).instantiate()
	player.name = "Player"
	var brain: Node = PlayerController.new()
	brain.name = "PlayerController"
	player.add_child(brain)
	player.position = HUMAN_AT
	main.add_child(player)
	var menu := CanvasLayer.new()
	menu.name = "SetupMenu"
	main.add_child(menu)
	Engine.set_meta("skip_setup", true)
	viewport.add_child(main)
	Engine.remove_meta("skip_setup")


## Wait for the match's NPCs to enter, watch their walks for `WATCH_S`, then check what `watch` saw:
## both maps ready (and answering with the house) on the first NPC's frame, and every first walk
## target on the navmesh.
func _judge(t: TestContext, watch: Dictionary, viewport: SubViewport, what: String) -> void:
	var entries: Array = watch["entries"]
	if not t.require(
			await t.until(func(): return entries.size() >= DEFENDERS + INVADERS, 10.0),
			"premise: %s placed %d NPCs (%d entered)" % [
				what,
				DEFENDERS + INVADERS,
				entries.size(),
			],
	):
		return
	var first: Dictionary = entries[0]
	t.check(
		first["planning"] and first["steering"],
		"%s: both maps are NavBuilder.ready as the first NPC (%s) enters (planning %s, steering %s)"
			% [what, first["npc"], first["planning"], first["steering"]],
	)
	t.check(
		first["planning_house"] and first["steering_house"],
		"%s: both maps answer with the house's own regions as %s enters (planning %s, steering %s)"
			% [what, first["npc"], first["planning_house"], first["steering_house"]],
	)
	await t.seconds(WATCH_S)
	var targets: Dictionary = watch["targets"]
	t.require(
		not targets.is_empty(),
		"premise: in %s some NPC walked within %.0f s" % [what, WATCH_S],
	)
	var map: RID = viewport.world_2d.navigation_map
	for npc in targets:
		var point: Vector2 = targets[npc]["point"]
		var walked: RID = targets[npc]["map"]
		var on := NavigationServer2D.map_get_closest_point(
			walked if walked.is_valid() else map,
			point,
		)
		t.check(
			on.distance_to(point) <= ON_MESH,
			"%s: %s's first walk target %s lies on the house's navmesh (%.0f px off it)"
				% [what, npc, str(point.round()), on.distance_to(point)],
		)


## Stop watching and free `viewport` with its match.
func _free(t: TestContext, viewport: SubViewport, watch: Dictionary) -> void:
	t.world.get_tree().node_added.disconnect(watch["added"])
	Sound.focus = null
	viewport.queue_free()
	await t.frames(2)
	Keybinds.reset_all()
