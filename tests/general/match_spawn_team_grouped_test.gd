extends GameTest
## LD27: a Main-built invader team spawns in a group round one point outside the house, beside its
## front door on a side drawn from the house seed (its members packed round it at
## `spawn_clearance`), not spread round the house; with a human invader in the match, round the
## human's spot. Defenders keep spawning in random rooms.
##
## Main runs whole, `_ready` to its match, as a scripted restart starts it (the Engine `skip_setup`
## meta, set while it enters the tree and dropped after), in a world of its own (a `SubViewport`
## with its own `World2D`, so fresh navigation maps, as each match's are): a Main
## node with the two children its scene gives it that `_ready` reads (`Player`, the human's body
## and controller, and `SetupMenu`, never opened). Its run's exports (`main.run`) name the match: a
## pinned house seed, four invaders and two defenders; Watch (spectator) for the team alone, Start
## as an invader for the human's case. Von is down (the NPCs hold steady: where they stand is the
## spawn's alone), the settings file is a scratch one, and the listener Main names (`Sound.focus`)
## is put back after. Its NPCs are read off the node Main builds the match under (the `match_world`
## group).

const MainScript := preload("res://scenes/main.gd")
const PlayerController := preload("res://scenes/character/player_controller.gd")
const PLAYER_SCENE := "res://scenes/character/character_base.tscn"
const SEED := 101
const INVADERS := 4
const DEFENDERS := 2
## Where the human stands in the scene (Main's anchor: the house's front entrance is built above
## it).
const HUMAN_AT := Vector2(0, 0)
## The most (px) a member may stand from the group's centre: four bodies packed at the clearance.
const GROUP_RADIUS := 110.0
## The point stands outside the house, against its outside wall beside the front door; the group's
## centre stands outside the house within this band of the rooms' bounds (px).
const OUT_MIN := 20.0
const OUT_MAX := 220.0


func describe() -> Dictionary:
	return {
		"name": "A Main-built invader team spawns in one group",
		"description": "Main places every invader round one seeded point outside the house (the "
			+ "same point for the same seed), or round the human invader's spot; defenders still "
			+ "start in rooms.",
		"tags": ["setup", "match", "spawn", "squad", "leadership"],
		"timeout": 30.0,
		"allowed_logs": [
			"Navigation map synchronization error",
			"NavigationPolygon polygon convex partition failed",
		],
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 300, 300))
	s.von_down()
	s.set_static(Settings, "path", "user://test_match_spawn_team_settings.json")
	s.set_static(Settings, "setup", {})
	s.set_static(Settings, "overlays", {})
	s.set_static(Settings, "debug", Settings.debug)


func run(t: TestContext) -> void:
	var watch := await _match(t, true)
	if not t.require(not watch.is_empty(), "Main built the match (spawner, rooms)"):
		return
	var invaders: Array = watch["invaders"]
	if not t.require(
			invaders.size() == INVADERS and (watch["defenders"] as Array).size() == DEFENDERS,
			"premise: Main placed %d invaders and %d defenders (%d, %d)"
				% [INVADERS, DEFENDERS, invaders.size(), (watch["defenders"] as Array).size()],
	):
		return
	var centre := _centre(invaders)
	t.check(
		_spread(invaders, centre) <= GROUP_RADIUS,
		"every invader stands within %.0f px of the group's centre (farthest %.0f px; at %s)"
			% [GROUP_RADIUS, _spread(invaders, centre), str(_points(invaders))],
	)
	var bounds: Rect2 = watch["bounds"]
	var out := _outside_by(bounds, centre)
	t.check(
		out >= OUT_MIN and out <= OUT_MAX,
		"the group stands round a point outside the house (%.0f px out of its bounds "
			% out + "%s; centre %s)" % [str(bounds), str(centre.round())],
	)
	for d: Dictionary in watch["defenders"]:
		t.check(
			(watch["rooms"] as Array).any(func(r): return (r["rect"] as Rect2).has_point(d["pos"])),
			"defender %s starts in a room (%s)" % [d["name"], str((d["pos"] as Vector2).round())],
		)
	var again := await _match(t, true)
	if not again.is_empty():
		var other := _centre(again["invaders"])
		t.check(
			other.distance_to(centre) < 1.0,
			"the same seed gives the same point (%s and %s)"
				% [str(centre.round()), str(other.round())],
		)
	await _check_played(t)


## Played as an invader, the team stands round the human's spot.
func _check_played(t: TestContext) -> void:
	var played := await _match(t, false)
	if not t.require(not played.is_empty(), "Main built the match with a human invader"):
		return
	var human: Vector2 = played["human"]
	var far: float = (played["invaders"] as Array).map(
		func(n): return (n["pos"] as Vector2).distance_to(human),
	).max()
	t.check(
		far <= GROUP_RADIUS,
		"with a human invader, the team stands round the human's spot (farthest %.0f px of %s; "
			% [far, str(human.round())] + "at %s)" % str(_points(played["invaders"])),
	)


## Build one match the way Main does with `SEED`, watched (`spectator`) or played as an invader,
## read where it placed everyone, and free it: `{ invaders, defenders, rooms, bounds, human }`
## (each `{ name, pos }`, read before the match is freed), {} when Main built nothing.
func _match(t: TestContext, spectator: bool) -> Dictionary:
	var viewport := _viewport(t)
	var main: Node2D = MainScript.new()
	main.name = "Main"
	main.run.set("house_seed", SEED)
	main.run.set("invader_count", INVADERS)
	main.run.set("defender_count", DEFENDERS)
	main.run.set("spectator_mode", spectator)
	main.run.set("player_side", &"invader")
	main.run.set("debug_overlays", false)
	var player := _player()
	main.add_child(player)
	var menu := CanvasLayer.new()
	menu.name = "SetupMenu"
	main.add_child(menu)
	Engine.set_meta("skip_setup", true)
	viewport.add_child(main)
	Engine.remove_meta("skip_setup")
	# Main places nobody until both navigation maps answer with its house (`MatchBuilder.stage`).
	await t.until(func(): return _npcs(viewport).size() >= INVADERS + DEFENDERS, 5.0)
	var out := {}
	var world := _match_world(viewport)
	var all := _npcs(viewport)
	if world != null and not all.is_empty():
		var rooms: Array = []
		for child in world.get_children():
			if rooms.is_empty() and child is Node2D:
				rooms = WorldGen.get_rooms(child)
		var bounds: Rect2 = rooms[0]["rect"] if not rooms.is_empty() else Rect2()
		for r in rooms:
			bounds = bounds.merge(r["rect"])
		out = {
			"invaders": _frozen(all.filter(func(c): return c.get("faction") == &"invader")),
			"defenders": _frozen(all.filter(func(c): return c.get("faction") != &"invader")),
			"rooms": rooms,
			"bounds": bounds,
			"human": player.global_position if is_instance_valid(player) else Vector2.INF,
		}
	Sound.focus = null
	viewport.queue_free()
	await t.frames(2)
	Keybinds.bindings.reset_all()
	return out


## A world of its own under the test's world, for one match: a small viewport that never renders.
func _viewport(t: TestContext) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.world_2d = World2D.new()
	viewport.disable_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	t.world.add_child(viewport)
	return viewport


## The scene's `Player` as Main finds it: a player character with its controller, at `HUMAN_AT`,
## that does not die.
func _player() -> Node2D:
	var player: Node2D = (load(PLAYER_SCENE) as PackedScene).instantiate()
	player.name = "Player"
	var brain: Node = PlayerController.new()
	brain.name = "PlayerController"
	player.add_child(brain)
	player.position = HUMAN_AT
	player.set("max_health", 1_000_000.0)
	return player


## The node Main builds its match under in `viewport` (the `match_world` group, interface 14), else
## null.
func _match_world(viewport: SubViewport) -> Node:
	for node in viewport.get_tree().get_nodes_in_group(&"match_world"):
		if viewport.is_ancestor_of(node):
			return node
	return null


## The NPCs of Main's match in `viewport`, in spawn order: the characters under its `match_world`
## node with an AI controller (interface 7: the child with `control` and the house's `rooms`).
func _npcs(viewport: SubViewport) -> Array:
	var world := _match_world(viewport)
	if world == null:
		return []
	return world.get_children().filter(func(c):
		var brain := TestContext.controller_of(c)
		return c is CharacterBody2D and brain != null and "rooms" in brain)


## Each node's `{ name, pos }`, so it outlives the match.
func _frozen(nodes: Array) -> Array:
	return nodes.map(func(n): return { "name": String(n.name), "pos": n.global_position })


## The centre (mean position) of `placed` (`{ name, pos }` each).
func _centre(placed: Array) -> Vector2:
	var sum := Vector2.ZERO
	for n: Dictionary in placed:
		sum += n["pos"] as Vector2
	return sum / maxf(placed.size(), 1.0)


## The farthest any of `placed` stands from `centre`.
func _spread(placed: Array, centre: Vector2) -> float:
	return placed.map(func(n): return (n["pos"] as Vector2).distance_to(centre)).max()


## How far `p` lies outside `rect` (0 inside it).
func _outside_by(rect: Rect2, p: Vector2) -> float:
	var nearest := p.clamp(rect.position, rect.end)
	return 0.0 if rect.has_point(p) else p.distance_to(nearest)


## The rounded positions of `placed`, for a message.
func _points(placed: Array) -> Array:
	return placed.map(func(n): return (n["pos"] as Vector2).round())
