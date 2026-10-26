extends RefCounted
## Shared helper for the tests that drive Main (`scenes/main.gd`, the composition root) through its
## public members only (not a test itself): Main run whole, as `main.tscn` gives it the children its
## `_ready` reads (`Player`, the player's character and controller, and the setup window,
## `SetupMenu`), without the Von launcher and the command server `main.tscn` would start. Added
## without the Engine `skip_setup` meta, it opens the setup window and builds nothing, as a fresh
## launch does; a test then reads the window (`SetupMenu.current_config()`) or starts a match of its
## own with `Main.start_match(spec)`.
##
## A match gets a world of its own (`viewport`: a `SubViewport` with its own `World2D`, so its own
## physics space and navigation maps, fresh as each match's are), under the test world, which frees
## it with everything else; `close` puts back what Main changed outside it.

const MainScript := preload("res://scenes/main.gd")
const PlayerController := preload("res://scenes/character/player_controller.gd")
const LayoutBuilder := preload("res://scenes/testing/layout_builder.gd")
const SetupMenu := preload("res://scenes/ui/menus/setup_menu.gd")
const PLAYER_SCENE := "res://scenes/character/character_base.tscn"


## A world of its own under the test world: a `SubViewport` with a fresh `World2D`.
static func viewport(t: TestContext) -> SubViewport:
	var out := SubViewport.new()
	out.name = "MainViewport"
	out.world_2d = World2D.new()
	out.disable_3d = true
	out.size = Vector2i(64, 64)
	out.render_target_update_mode = SubViewport.UPDATE_DISABLED
	t.world.add_child(out)
	return out


## Main whole under `parent`, its run's exports (`main.run`) set from `exports` first (Debug off
## unless they name `debug_overlays`), its `Player` standing at `player_at` (Main's anchor: the
## front entrance is built `run.entrance_distance` above it): it loads the settings
## (`Settings.path`, which the test points at a scratch file) and opens the setup window, or, with
## the Engine `skip_setup` meta set while it enters the tree (a scripted restart), builds its match
## at once. Returned once its `_ready` has run.
static func open(parent: Node, exports: Dictionary = {}, player_at := Vector2.ZERO) -> Node2D:
	var main: Node2D = MainScript.new()
	main.name = "Main"
	main.run.set("debug_overlays", false)
	for key in exports:
		main.run.set(key, exports[key])
	var player: Node2D = (load(PLAYER_SCENE) as PackedScene).instantiate()
	player.name = "Player"
	player.position = player_at
	var brain: Node = PlayerController.new()
	brain.name = "PlayerController"
	player.add_child(brain)
	main.add_child(player)
	var menu: CanvasLayer = SetupMenu.new()
	menu.name = "SetupMenu"
	main.add_child(menu)
	parent.add_child(main)
	return main


## The setup window Main opened (its `SetupMenu` child), or null.
static func setup_menu(main: Node) -> Node:
	return main.get_node_or_null("SetupMenu") if is_instance_valid(main) else null


## A hand-laid house for a match spec's `house`, built under `parent` from the layout a `TestSetup`
## describes (`layout.world`, e.g. after `Maps.house(TestSetup.new(), false)`).
static func house(layout: TestSetup, parent: Node) -> Node2D:
	return LayoutBuilder.build(layout.world, parent)


## Put back what Main changed outside its own nodes: the listener it named (`Sound.focus`) and the
## key bindings its settings load applied; then free `node` (the viewport, or Main).
static func close(t: TestContext, node: Node) -> void:
	Sound.focus = null
	if is_instance_valid(node):
		node.queue_free()
	await t.frames(2)
	Keybinds.bindings.reset_all()
