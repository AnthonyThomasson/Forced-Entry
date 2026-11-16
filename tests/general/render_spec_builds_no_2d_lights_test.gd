extends GameTest
## A match spec that names `render` decides how the match is drawn, whatever the saved render mode
## says (#193 rule 2, interface 23), and a 3D match builds no 2D lights (interface 27, ADR 0013):
## the dusk's `CanvasModulate`, its `PointLight2D`s and the `WorldLighting` node are 2D drawing the
## 3D view replaces, so 3D skips building them (the painters' textures and occluders are still
## built until the 2D render is deleted). Main is run whole (`tests/_main/main_probe.gd`) over the
## same spec each way: a spec of 3D with the setting on 2D hides the world, builds the 3D view and
## has no 2D light; a spec of 2D with the setting on 3D is the 2D game, its lights built (the
## premise that makes the absence above mean something).

const MainProbe := preload("res://tests/_main/main_probe.gd")
const SCRATCH := "user://settings_render_spec_test.json"
## The 3D view Main adds under the CanvasLayer below the HUD (its node name).
const VIEW := "View3D"
const SPEC := {
	"seed": 3,
	"defenders": { "count": 1 },
	"invaders": { "count": 1 },
}


func describe() -> Dictionary:
	return {
		"name": "A spec's render mode beats the setting; a 3D match builds no 2D lights",
		"description": "A spec of 3D over a setting of 2D hides the world, builds the 3D view and "
			+ "no 2D light; a spec of 2D over a setting of 3D draws the world and lights it.",
		"tags": ["settings", "render", "3d", "lighting"],
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
	var viewport := MainProbe.viewport(t)
	var main := MainProbe.open(viewport)
	var camera := Camera2D.new()
	camera.name = "MainCamera"
	main.add_child(camera)
	Settings.render_mode = Settings.RENDER_2D
	var spec := SPEC.duplicate(true)
	spec["render"] = Settings.RENDER_3D
	var built: Dictionary = await main.start_match(spec)
	if not t.require(not built.is_empty(), "premise: a match started with a spec of 3D"):
		await MainProbe.close(t, viewport)
		return
	var world: Node2D = built["world"]
	t.check(not world.visible, "spec 3D over setting 2D: the 2D world is not drawn")
	t.check(main.get_node_or_null(VIEW) != null, "spec 3D over setting 2D: the 3D view is built")
	t.expect_eq(_lights_of(world), [], "a 3D match builds no 2D light, modulate or lighting node")
	# The next match replaces it, as the endless run does: the old World goes first.
	main.remove_child(world)
	world.queue_free()
	await t.frames(3)
	Settings.render_mode = Settings.RENDER_3D
	spec["render"] = Settings.RENDER_2D
	built = await main.start_match(spec)
	if not t.require(not built.is_empty(), "premise: a match started with a spec of 2D"):
		await MainProbe.close(t, viewport)
		return
	world = built["world"]
	t.check(world.visible, "spec 2D over setting 3D: the 2D world is drawn")
	t.check(main.get_node_or_null(VIEW) == null, "spec 2D over setting 3D: no 3D view")
	var lights := _lights_of(world)
	t.check(
		lights.has("CanvasModulate") and lights.has("PointLight2D") and lights.has("WorldLighting"),
		"premise: a 2D match builds its lights (%s)" % str(lights),
	)
	Settings.render_mode = Settings.RENDER_2D
	await MainProbe.close(t, viewport)


## The kinds of 2D light drawing under `world`: `CanvasModulate`, `PointLight2D` and the
## `WorldLighting` node (its group), each named once when present.
func _lights_of(world: Node) -> Array:
	var found: Array = []
	if not world.find_children("*", "CanvasModulate", true, false).is_empty():
		found.append("CanvasModulate")
	if not world.find_children("*", "PointLight2D", true, false).is_empty():
		found.append("PointLight2D")
	for node in world.get_tree().get_nodes_in_group(&"world_lighting"):
		if world.is_ancestor_of(node):
			found.append("WorldLighting")
			break
	return found
