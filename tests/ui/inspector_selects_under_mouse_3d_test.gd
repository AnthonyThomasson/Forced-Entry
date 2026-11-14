extends GameTest
## The spectator inspector in the 3D render mode (#193 rule 5): a right-click selects the NPC under
## the mouse's ground point. At yaw 45 and zoom 0.2 with the camera 100 px along -x of the NPC,
## the NPC shows (14.142, 8.165) px from the screen's middle (the isometric projection worked by
## hand); a right-click there selects it (its vision overlay turns on), and a right-click on the
## screen point where a flat reading would put it (100 px right of the middle) selects nothing.

const Inspector := preload("res://scenes/ui/hud/spectator_inspector.gd")
const OverlayToggles := preload("res://scenes/ui/overlays/overlay_toggles.gd")
const InspectorProbe := preload("res://tests/_ui/inspector_probe.gd")
const RigProbe := preload("res://tests/_general/rig_probe.gd")
const AT := Vector2(450, 250)
const ZOOM := 0.2


func describe() -> Dictionary:
	return {
		"name": "In 3D a right-click selects the NPC under the mouse's ground point",
		"description": "At yaw 45 the NPC shows at a hand-worked screen point; right-clicking "
			+ "there selects it, right-clicking where a flat reading puts it selects nothing.",
		"tags": ["ui", "inspector", "spectator", "3d", "pointer"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"ai.vision", false)
	s.von_down()
	s.lock_interaction([&"camera", &"pause"])
	s.actor(&"npc", &"defender", AT, { "movement:speed": 0.0, "start_slot": 3 })


func run(t: TestContext) -> void:
	var npc := t.actor(&"npc")
	var camera := Camera2D.new()
	camera.position = AT - Vector2(100.0, 0.0)
	camera.zoom = Vector2(ZOOM, ZOOM)
	t.world.add_child(camera)
	camera.make_current()
	RigProbe.open(t.world, camera, 45.0)
	var inspector := CanvasLayer.new()
	inspector.set_script(Inspector)
	t.world.add_child(inspector)
	inspector.call("setup", [npc], { "show_vision": true }, OverlayToggles.RESERVED_WIDTH)
	await t.frames(6)
	var middle := t.world.get_viewport().get_visible_rect().size * 0.5

	await InspectorProbe.click_screen(t, middle + Vector2(100.0, 0.0) * ZOOM, MOUSE_BUTTON_RIGHT)
	t.check(not _vision_on(npc), "a right-click where a flat reading puts the NPC selects nothing")

	await InspectorProbe.click_screen(t, middle + Vector2(14.142, 8.165), MOUSE_BUTTON_RIGHT)
	t.check(_vision_on(npc), "a right-click on the NPC's hand-worked screen point selects it")
	inspector.queue_free()


func _vision_on(npc: Node) -> bool:
	return InspectorProbe.overlays_with(npc, "show_vision").any(
		func(o: Node) -> bool: return bool(o.get("show_vision"))
	)
