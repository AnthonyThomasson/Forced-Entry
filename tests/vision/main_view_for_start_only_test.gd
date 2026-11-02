extends GameTest
## V8 (`docs/player-vision.md`): in Main the view is built in a played match (the setup window's
## Start) for the human only, and Watch, with no human, draws everything as today. Main run whole
## (`tests/_main/main_probe.gd`), in a world of its own, with the view switched on: Start builds one
## view, of Main's `Player`; Watch builds none.
##
## It reads (tests/_vision/vision_probe.gd) the `PlayerView` nodes under the world. Scripted Von; a
## scratch settings file, never the real one.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const Probe := preload("res://tests/_vision/vision_probe.gd")
const SCRATCH := "user://settings_vision_start_test.json"
## The setup window's choice: one NPC a side; the mode is set by each phase.
const CONFIG := {
	"seed": 5,
	"side": "defender",
	"lead": false,
	"defenders": { "count": 1 },
	"invaders": { "count": 1 },
}


func describe() -> Dictionary:
	return {
		"name": "Main builds a view for Start only",
		"description": "Start in the setup window builds one view, of the human; Watch builds "
			+ "none.",
		"tags": ["vision", "match", "setup"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.switch(&"vision.enabled", true)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", Settings.debug)
	s.von_script([])


func run(t: TestContext) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	var played := await _start(t, "play")
	if not t.require(played != null, "Start builds a match"):
		return
	var found := Probe.views(t)
	t.check(found.size() == 1, "Start builds one view (%d found)" % found.size())
	if found.size() == 1:
		t.check(
			found[0].viewer() == played.get_node_or_null("Player"),
			"the view is of the human, Main's Player",
		)
	var watched := await _start(t, "watch")
	if not t.require(watched != null, "Watch builds a match"):
		return
	t.check(Probe.views(t).is_empty(), "Watch builds no view (%d found)" % Probe.views(t).size())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


## Start a match of `mode` ("play" or "watch") in a fresh Main of its own, closing the one before;
## the match's `World`, or null if none was built in time. Built is a combatant in the `World`:
## `MatchBuilder.populate` spawns them and watches the human in one frame, after the staged build
## (the district and its nav) has added the `World`'s first children over several.
func _start(t: TestContext, mode: String) -> Node:
	for old in t.world.find_children("MainViewport", "SubViewport", false, false):
		await MainProbe.close(t, old)
	var viewport := MainProbe.viewport(t)
	var main = MainProbe.open(viewport)
	var menu := MainProbe.setup_menu(main)
	if menu == null:
		return null
	menu.start_requested.emit(CONFIG.merged({ "mode": mode }))
	var built := func() -> bool:
		var world := _world(main)
		return world != null and _has_combatant(world)
	if not await t.until(built, 10.0):
		return null
	await t.frames(3)
	return _world(main)


func _world(main: Node) -> Node:
	if not is_instance_valid(main):
		return null
	for child in main.get_children():
		if child.is_in_group(&"match_world"):
			return child
	return null


## Whether a character (the group `characters`) stands under `world`.
func _has_combatant(world: Node) -> bool:
	for character in world.get_tree().get_nodes_in_group(&"characters"):
		if world.is_ancestor_of(character):
			return true
	return false
