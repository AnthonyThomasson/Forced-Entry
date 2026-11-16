extends GameTest
## The render mode (#193 rule 2): a saved setting, 2D or 3D, 2D by default, in `Settings` (interface
## 14). Changing it saves at once and a reload restores it; a file naming something else keeps the
## default. It applies at the next match: Main run whole (`tests/_main/main_probe.gd`) reads it in
## `start_match`, so a match started with 3D chosen hides the 2D world and builds the 3D view, a
## match started after the setting went back to 2D is the 2D game as ever, and a change made while a
## match runs leaves that match as it is. Runs against a scratch settings file, never the real one.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const SCRATCH := "user://settings_render_mode_test.json"
## The 3D view Main adds under the CanvasLayer below the HUD (its node name).
const VIEW := "View3D"
const SPEC := {
	"seed": 3,
	"defenders": { "count": 1 },
	"invaders": { "count": 1 },
}


func describe() -> Dictionary:
	return {
		"name": "The render mode is a saved setting, applied at the next match",
		"description": "2D by default; set, saved and reloaded; a file with another value keeps "
			+ "the default; a match started in 3D hides the 2D world and builds the 3D view, one "
			+ "started in 2D has neither, and a change while a match runs waits for the next.",
		"tags": ["settings", "render", "3d"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_2D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.von_script([])


func run(t: TestContext) -> void:
	_remove_scratch()
	t.expect_eq(Settings.render_mode, Settings.RENDER_2D, "the render mode starts as 2D")
	t.expect_eq(Settings.RENDER_2D, "2d", "the 2D mode is saved as 2d")
	t.expect_eq(Settings.RENDER_3D, "3d", "the 3D mode is saved as 3d")
	await _check_saved(t)
	_check_unknown_value(t)
	await _check_applied_at_next_match(t)
	Settings.render_mode = Settings.RENDER_2D
	_remove_scratch()


## A change saves at once; a reload restores it; an unknown mode is refused.
func _check_saved(t: TestContext) -> void:
	Settings.set_render_mode(Settings.RENDER_3D)
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(SCRATCH))
	if not t.require(saved is Dictionary, "changing the mode writes the settings file"):
		return
	t.expect_eq(saved.get("render_mode"), "3d", "the file records the render mode")
	Settings.render_mode = Settings.RENDER_2D
	Settings.load_file()
	t.expect_eq(Settings.render_mode, Settings.RENDER_3D, "a reload restores the render mode")
	t.verdict.expect_log("is not a render mode")
	Settings.set_render_mode("hologram")
	await t.seconds(0.2)  # let the log watcher see the warning
	t.expect_eq(Settings.render_mode, Settings.RENDER_3D, "a mode that is not 2d or 3d is refused")
	Settings.set_render_mode(Settings.RENDER_2D)
	Settings.render_mode = Settings.RENDER_3D
	Settings.load_file()
	t.expect_eq(Settings.render_mode, Settings.RENDER_2D, "a reload restores 2D too")


## A file that names another value (or no value) keeps the mode as it was.
func _check_unknown_value(t: TestContext) -> void:
	_write('{ "render_mode": "hologram" }')
	Settings.render_mode = Settings.RENDER_2D
	Settings.load_file()
	t.expect_eq(Settings.render_mode, Settings.RENDER_2D, "an unknown saved mode is skipped")
	_write('{ "render_mode": 3 }')
	Settings.load_file()
	t.expect_eq(
		Settings.render_mode,
		Settings.RENDER_2D,
		"a saved mode of the wrong type is skipped",
	)
	_write('{ "debug": false }')
	Settings.render_mode = Settings.RENDER_3D
	Settings.load_file()
	t.expect_eq(Settings.render_mode, Settings.RENDER_3D, "a file without the mode leaves it")


## The mode Main reads when a match starts is the match's for as long as it runs.
func _check_applied_at_next_match(t: TestContext) -> void:
	var viewport := MainProbe.viewport(t)
	var main := MainProbe.open(viewport)
	var camera := Camera2D.new()
	camera.name = "MainCamera"
	main.add_child(camera)
	Settings.render_mode = Settings.RENDER_3D
	var built: Dictionary = await main.start_match(SPEC.duplicate(true))
	if not t.require(not built.is_empty(), "premise: a match started with 3D chosen"):
		await MainProbe.close(t, viewport)
		return
	var world: Node2D = built["world"]
	t.check(not world.visible, "3D chosen: the 2D world is not drawn")
	t.check(main.get_node_or_null(VIEW) != null, "3D chosen: Main built the 3D view")
	Settings.render_mode = Settings.RENDER_2D
	await t.frames(3)
	t.check(not world.visible, "the running match keeps the mode it started in")
	t.check(main.get_node_or_null(VIEW) != null, "and its 3D view")
	# The next match replaces it (as the endless run does: the old World goes first, with its nav
	# map).
	main.remove_child(world)
	world.queue_free()
	await t.frames(3)
	built = await main.start_match(SPEC.duplicate(true))
	if not t.require(not built.is_empty(), "premise: the next match started with 2D chosen"):
		await MainProbe.close(t, viewport)
		return
	world = built["world"]
	t.check(world.visible, "2D chosen: the 2D world is drawn, as it always was")
	t.check(main.get_node_or_null(VIEW) == null, "2D chosen: no 3D view is built")
	await MainProbe.close(t, viewport)


func _write(text: String) -> void:
	var file := FileAccess.open(SCRATCH, FileAccess.WRITE)
	file.store_string(text)


func _remove_scratch() -> void:
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
