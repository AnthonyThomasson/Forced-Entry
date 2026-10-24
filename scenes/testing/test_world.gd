extends Node2D
## Testing domain: one test's live world, built from a TestSetup through the published interfaces
## only (WorldGen, the Objects factories, NavBuilder, the character scenes + controller contract) —
## the same way main.gd composes a match. Freed between tests; `restore()` undoes the static-var
## overrides, which outlive the scene.

const ArenaBuilder = preload("res://scenes/testing/arena_builder.gd")
const LayoutBuilder = preload("res://scenes/testing/layout_builder.gd")
const TestSwitches = preload("res://scenes/testing/test_switches.gd")
const ScriptedController = preload("res://scenes/testing/scripted_controller.gd")
const PlayerController = preload("res://scenes/character/player_controller.gd")
const OVERLAY_REGISTRY := preload("res://scenes/ui/overlays/overlay_registry.gd")
const ACTOR_SCENES := {
	&"puppet": "res://scenes/character/character_base.tscn",
	&"player": "res://scenes/character/character_base.tscn",
	&"defender": "res://scenes/ai/npc_defender.tscn",
	&"invader": "res://scenes/ai/npc_invader.tscn",
}

## The house or arena root and its rooms.
var house: Node2D
var rooms: Array = []
## Its doorways (`WorldGen.get_openings`), injected into every NPC beside `rooms`.
var openings: Array = []
## The match `TestSetup.match` declared, populated over this world (`MatchBuilder.populate`'s
## handle); {} when none.
var match_handle: Dictionary = {}
## The squads `TestSetup.squads` declared, by faction (`MatchBuilder.build_squads`), and the human
## leader's stack radio (`MatchBuilder.bind_player`), or null; or the declared match's own.
var squads: Dictionary = {}
var player_stack: Node = null
## The placed actors, objects and vehicles by id.
var actors: Dictionary = {}
var objects: Dictionary = {}
var vehicles: Dictionary = {}
## Original values of overridden statics: `[script, prop, value]`.
var _saved_statics: Array = []
## The overlay toggles (`show_<x>` -> on), given to every actor as it spawns and changed by
## `set_overlay`.
var _overlay_flags: Dictionary = {}
## The navmesh-holes overlay (the "Navigation holes" toggle), kept in step with re-bakes by the
## updater.
var _nav_debug: Node2D = null
## The squad-leaders overlay (the "Squad leaders" toggle), built with the squads a setup declares
## (`TestSetup.squads` or `TestSetup.match`); null in a world that declares none.
var _leader_overlay: Node2D = null


## Build everything `setup` declares. Statics and switches are applied before anything spawns, so
## spawning already sees them. The world stage (nav map, its overlay and re-baker, the dusk
## lighting, then the wait for the navigation maps) is Main's own, `MatchBuilder.stage`, over the
## house, layout or arena built here with its objects in place, so the bake carves them; it steps
## two physics frames (the walls' colliders go live on a step) and waits until both maps answer with
## this world's navmesh before any actor enters: an NPC thinking on its first tick would otherwise
## see through the walls and plan on an empty map.
func build(setup: TestSetup) -> void:
	for switch_name in setup.switches:
		if not TestSwitches.has(switch_name):
			push_error("TestWorld: unknown switch '%s'" % switch_name)
	_apply_statics(setup)
	_build_world(setup.resolved_world())
	# Objects go under the house/arena root (like furnished pieces) so the nav bake carves them.
	for o in setup.objects:
		var opts: Dictionary = o["opts"].duplicate()
		opts["name"] = String(o["id"])
		objects[o["id"]] = ObjectFactory.spawn(
			o["definition"],
			house.to_local(o["position"]),
			house,
			opts,
		)
	_overlay_flags = {}
	for flag in OVERLAY_REGISTRY.defaults():
		_overlay_flags[flag] = setup.overlays.has(flag)
	var spec := {
		"seed": int(setup.resolved_world().get("seed", 0)),
		"house": house,
		"wait_nav": true,
		"overlays": _overlay_flags.duplicate(),
	}
	var staged: Dictionary = await MatchBuilder.stage(spec, self)
	_nav_debug = staged["nav_debug"]
	for v in setup.vehicles:
		var vehicle := _spawn_vehicle(v)
		if vehicle != null:
			vehicles[v["id"]] = vehicle
	if not vehicles.is_empty():
		# A new body joins the physics server's broadphase only at its next step: wait for it, so
		# the vehicles are solid (and found by space queries) before an actor is placed or the
		# test's first query runs.
		await get_tree().physics_frame
	for a in setup.actors:
		actors[a["id"]] = _spawn_actor(a, setup.switches)
	if setup.match_spec is Dictionary:
		var overrides: Dictionary = (setup.match_spec as Dictionary).merged(spec)
		var human: Variant = overrides.get("human")
		if human is Dictionary and (human as Dictionary).has("actor"):
			# The human a test actor: the match joins that node to its side.
			human = (human as Dictionary).duplicate()
			human["node"] = actors.get(human["actor"])
			human.erase("actor")
			overrides["human"] = human
		match_handle = MatchBuilder.populate(staged, MatchBuilder.spec(overrides))
		squads = match_handle["squads"]
		player_stack = match_handle["player_stack"]
		_leader_overlay = match_handle["leader_overlay"]
		if setup.squads_spec is Dictionary:
			push_error("TestWorld: a setup declares its squads or a match, not both")
	elif setup.squads_spec is Dictionary:
		_build_squads(setup)
	_apply_world_switches(setup.switches)


## The squads `setup` declares (`TestSetup.squads`): one per faction over its actors, in
## declaration order, built and bound as a match's are (`MatchBuilder.squads_over`: the human
## leader first handed its stack radio, the squads keeping claims the setup's `claim_ttl` when it
## names one, and the squad-leaders overlay over them, shown as the setup's overlays say).
func _build_squads(setup: TestSetup) -> void:
	var members: Array = []
	for a in setup.actors:
		if is_instance_valid(actors.get(a["id"])):
			members.append(actors[a["id"]])
	var human := {}
	var human_id: Variant = (setup.squads_spec as Dictionary).get("human")
	if human_id != null:
		var node: Node = actors.get(StringName(human_id))
		if node == null:
			push_error("TestWorld: squads' human '%s' is no actor" % human_id)
		else:
			human = { "node": node, "lead": true }
	var built := MatchBuilder.squads_over(
		self,
		members,
		rooms,
		openings,
		human,
		bool(_overlay_flags.get(OVERLAY_REGISTRY.LEADERS, false)),
		float((setup.squads_spec as Dictionary).get("claim_ttl", -1.0)),
	)
	squads = built["squads"]
	player_stack = built["player_stack"]
	_leader_overlay = built["leader_overlay"]


## Undo every static override (call after freeing the world, or before rebuilding).
func restore() -> void:
	for i in range(_saved_statics.size() - 1, -1, -1):
		var s: Array = _saved_statics[i]
		(s[0] as Script).set(s[1], s[2])
	_saved_statics.clear()


## The current per-NPC overlay flags (for the in-game toggle bar).
func overlay_flags() -> Dictionary:
	return _overlay_flags.duplicate()


## Turn one debug overlay on/off, as the in-game toggle bar does, by the match's one rule
## (`MatchBuilder.set_overlay`) on this world: the navmesh holes on its holes overlay, the squad
## leaders on its leaders overlay (a world that declares no squads has none, so the toggle does
## nothing there) and any other on every NPC, its actors' and a declared match's. The performance
## panel belongs to the runner.
func set_overlay(flag: String, on: bool) -> void:
	_overlay_flags[flag] = on
	MatchBuilder.set_overlay(
		{
			"nav_debug": _nav_debug,
			"leader_overlay": _leader_overlay,
			"combatants": actors.values() + (match_handle.get("combatants", []) as Array),
		},
		flag,
		on,
	)


## Apply the switch rows' static knobs, then the explicit `set_static` overrides.
func _apply_statics(setup: TestSetup) -> void:
	for switch_name in setup.switches:
		var on: bool = setup.switches[switch_name]
		for knob in TestSwitches.row(switch_name).get("static", []):
			if knob.size() < 3:
				_set_static(knob[0], knob[1], on)
			elif not on:
				_set_static(knob[0], knob[1], knob[2])
	for s in setup.statics:
		_set_static(s[0], s[1], s[2])


## Set a static var, remembering its value for `restore()`.
func _set_static(script: Script, prop: StringName, value: Variant) -> void:
	_saved_statics.append([script, prop, script.get(prop)])
	script.set(prop, value)


## Build the generated house or the arena, and read its rooms.
func _build_world(world: Dictionary) -> void:
	if world["kind"] == "house":
		house = WorldGen.generate(
			int(world["seed"]),
			String(world.get("plan", "")),
			world.get("entrance", Vector2.ZERO),
			self,
		)
	elif world["kind"] == "layout":
		house = LayoutBuilder.build(world, self)
	else:
		house = ArenaBuilder.build(world, self)
	rooms = WorldGen.get_rooms(house)
	openings = WorldGen.get_openings(house)


## Instance vehicle `v` (`TestSetup.vehicle`) from `res://scenes/vehicle/<kind>.tscn`, set its
## props, then add it to the world, already in place. A kind with no scene is left out (null)
## without an error, so a test written before the vehicle exists fails on its own `require`.
func _spawn_vehicle(v: Dictionary) -> Node:
	var path := "res://scenes/vehicle/%s.tscn" % v["kind"]
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var vehicle := scene.instantiate()
	vehicle.name = String(v["id"])
	var props: Dictionary = v["props"]
	for prop in props:
		vehicle.set(prop, props[prop])
	# Placed before it joins the tree, like an actor: a body added at the origin and moved
	# afterwards shoves what is there.
	if vehicle is Node2D:
		vehicle.position = to_local(v["position"])
		vehicle.rotation = v["rotation"]
	add_child(vehicle)
	return vehicle


## Instance actor `a`, inject its controller and props/switches/overlays, then add it to the world.
func _spawn_actor(a: Dictionary, switches: Dictionary) -> Node:
	var kind: StringName = a["kind"]
	var path: String = ACTOR_SCENES.get(kind, String(kind))
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("TestWorld: actor '%s' has unknown kind/scene '%s'" % [a["id"], kind])
		return null
	var character := scene.instantiate()
	character.name = String(a["id"])
	if kind == &"puppet":
		var puppet: Node = ScriptedController.new()
		puppet.name = "ScriptedController"
		character.add_child(puppet)
	elif kind == &"player":
		var human: Node = PlayerController.new()
		human.name = "PlayerController"
		character.add_child(human)
	var props: Dictionary = a["props"]
	for prop in props:
		character.set(prop, props[prop])
	for switch_name in switches:
		var row: Dictionary = TestSwitches.row(switch_name).get("actor", {})
		if row.is_empty():
			continue
		var target: Node
		if row.get("controller", false):
			target = TestContext.controller_of(character)
		else:
			target = character if row["child"] == "" else character.get_node_or_null(row["child"])
		if target != null:
			for prop in row["props"]:
				target.set(prop, switches[switch_name])
	var children: Dictionary = a["children"]
	for child_path in children:
		var child := character.get_node_or_null(child_path)
		if child == null:
			push_error("TestWorld: actor '%s' has no child '%s'" % [a["id"], child_path])
			continue
		for prop in children[child_path]:
			child.set(prop, children[child_path][prop])
	OVERLAY_REGISTRY.apply(character, _overlay_flags)
	# The AI learns the house's rooms, its doorways and, for an invader, the front entrance by
	# Main's own rule, before it joins the tree.
	MatchBuilder.bind_npc(
		character,
		rooms,
		openings,
		MatchBuilder.entry_point_for(character.get("faction"), openings),
	)
	# Positioned before it joins the tree: a body added at the origin and moved afterwards launches
	# whatever stands there (the same trap `match_spawner.gd` avoids).
	character.position = to_local(a["position"])
	add_child(character)
	return character


## Apply the switch rows that target a node of the built world.
func _apply_world_switches(switches: Dictionary) -> void:
	for switch_name in switches:
		var row: Dictionary = TestSwitches.row(switch_name).get("world", {})
		if row.is_empty():
			continue
		var node := get_node_or_null(row["node"])
		if node != null:
			for prop in row["props"]:
				node.set(prop, switches[switch_name])
