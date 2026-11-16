extends GameTest
## The player's view and the debug overlays in the 3D render mode (#193 rule 5, decisions G9 and
## G10): the 2D world is hidden in 3D, so Main's played match moves each overlay under a
## `GroundLayer` (a `CanvasLayer` is not hidden by the hidden world) over the 3D view, where the
## overlay still draws its own 2D code flat on the ground. Main is run whole over a played match
## with 3D chosen by the spec: the view is two masks for the shaders (no composite to draw flat) and
## every NPC overlay and the navigation holes are visible in the tree on a ground layer (one shared
## layer for all the overlays, not one per NPC) whose transform is the 3D camera's ground-to-screen
## affine (hand-worked at yaw 120 and pitch 80: 100 px of ground along +x shows (-50, 85.287) px
## from the screen's middle, the focus at the middle), so they line up with the 3D floor at any yaw;
## an overlay flag still reaches the moved overlays and the detail card finds them by name; a 2D
## match moves nothing.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const OverlayRegistryProbe := preload("res://tests/_general/overlay_lookup_probe.gd")
const SCRATCH := "user://settings_ground_overlays_test.json"
const FOCUS := Vector2(300.0, 200.0)
const YAW := 120.0
const SPEC := {
	"seed": 3,
	"defenders": { "count": 1 },
	"invaders": { "count": 1 },
}


func describe() -> Dictionary:
	return {
		"name": "In 3D the debug overlays draw flat on the ground, the view is masks",
		"description": "A played match with 3D chosen: the view holds masks and no composite, "
			+ "each NPC's overlays and the navigation holes sit on ground layers that follow "
			+ "the camera's ground-to-screen affine at yaw 120, are visible though the world is "
			+ "hidden, still take their flags and are found by name; a 2D match moves nothing.",
		"tags": ["render", "3d", "vision", "overlays"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_2D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.set_static(GroundLayer, &"enabled", false)
	s.switch(&"vision.enabled", true)
	s.von_script([])


func run(t: TestContext) -> void:
	var viewport := MainProbe.viewport(t)
	var main := MainProbe.open(viewport)
	var camera := Camera2D.new()
	camera.name = "MainCamera"
	camera.position = FOCUS
	main.add_child(camera)
	camera.make_current()
	var built := await _play(main, "3d")
	if not t.require(not built.is_empty(), "premise: a played match started in 3D"):
		await MainProbe.close(t, viewport)
		return
	var world: Node2D = built["world"]
	t.check(not world.visible, "the 2D world is hidden")
	var view: CanvasLayer = main.get_node("View3D")
	view.rig.yaw = YAW
	await t.frames(5)
	_view_is_masks_not_an_overlay(t, world)
	var shared: Node = main.get_node("View3D/GroundOverlays")
	_one_shared_overlay_layer(t, main, shared)
	_npc_overlays_are_flat(t, built, shared)
	await _overlays_follow_their_npc(t, built)
	_navigation_holes_are_flat(t, built)
	_flags_reach_the_moved_overlays(t, main, built)
	_layer_is_the_cameras_affine(t, viewport, built)
	await _overlay_goes_with_its_owner(t, world)
	# The next match is a 2D one: nothing moves.
	main.remove_child(world)
	world.queue_free()
	await t.frames(3)
	built = await _play(main, "2d", false)
	if t.require(not built.is_empty(), "premise: a match started in 2D"):
		t.check(not GroundLayer.enabled, "2D: ground layers are off")
		await t.frames(3)
		t.expect_eq(_ground_layers(built["world"]).size(), 0, "2D: no overlay moved")
	await MainProbe.close(t, viewport)


## A match in the render mode `render`: played by the scene's own `Player` or, with no `human`,
## only watched.
func _play(main: Node, render: String, human := true) -> Dictionary:
	var spec := SPEC.duplicate(true)
	spec["render"] = render
	if human:
		spec["human"] = { "node": main.get_node("Player"), "side": &"invader", "lead": false }
	return await main.start_match(spec)


## The ground layer `item` is drawn under (null when it is on none).
func _layer_of(item: Node) -> GroundLayer:
	var node := item.get_parent()
	while node != null and not node is GroundLayer:
		node = node.get_parent()
	return node as GroundLayer


func _ground_layers(under: Node) -> Array:
	return under.find_children("*", "CanvasLayer", true, false).filter(
		func(n: Node) -> bool: return n is GroundLayer
	)


## The player's view is no flat overlay in 3D: it is two masks the toon shaders read, so the view
## holds no screen picture and no ground layer of its own.
func _view_is_masks_not_an_overlay(t: TestContext, world: Node) -> void:
	var view := world.find_child("PlayerView", true, false) as PlayerView
	if not t.require(view != null, "the match has the human's view"):
		return
	t.check(view.ground != null, "the view is the 3D one (two masks for the shaders)")
	t.expect_eq(
		view.find_children("*", "SubViewport", true, false).size(),
		2,
		"its only viewports are the live window and the memory",
	)
	t.expect_eq(_ground_layers(view).size(), 0, "and no ground layer under the view")
	t.check(
		RenderConfig.canvas_layer < RenderConfig.overlay_layer and RenderConfig.overlay_layer < 1,
		"the 3D view, then the overlays, all under the HUD's layer",
	)


## However many NPCs the match has, its overlays share ONE ground layer on the overlay layer (a
## canvas layer per NPC costs a draw pass each).
func _one_shared_overlay_layer(t: TestContext, main: Node, shared: Node) -> void:
	var on_overlay_layer := _ground_layers(main).filter(
		func(layer: CanvasLayer) -> bool: return layer.layer == RenderConfig.overlay_layer
	)
	t.expect_eq(on_overlay_layer.size(), 1, "one ground layer for all the overlays")
	t.check(shared in on_overlay_layer, "and it is the view's")


## Every NPC's overlays are on its ground layer and draw.
func _npc_overlays_are_flat(t: TestContext, built: Dictionary, shared: Node) -> void:
	for npc: Node in built["combatants"]:
		if (npc.get_node_or_null("PlayerController") != null
				or npc.get_node_or_null("GoalController") == null):
			continue
		var overlay := OverlayRegistryProbe.named(npc, "VisionDebug") as CanvasItem
		if not t.check(overlay != null, "%s's vision overlay is on its ground layer" % npc.name):
			continue
		t.check(
			overlay.is_visible_in_tree(),
			"%s's overlay draws though the world is hidden" % npc.name,
		)
		t.check(npc.get_node_or_null("AgentDebug") == null, "it left the NPC's own children")
		t.check(
			_layer_of(overlay) == shared,
			"on the one shared overlay layer, not a layer of its own",
		)


## A moved overlay keeps the frame of the NPC it belongs to (it draws from its owner's origin and
## turns with it, as it did in 2D): the NPC moved 50 px, its overlay is where it is.
func _overlays_follow_their_npc(t: TestContext, built: Dictionary) -> void:
	for npc: Node2D in built["combatants"]:
		var overlay := OverlayRegistryProbe.named(npc, "VisionDebug") as Node2D
		if overlay == null:
			continue
		npc.global_position += Vector2(50.0, 0.0)
		await t.frames(2)
		t.check(
			overlay.global_position.distance_to(npc.global_position) < 0.5,
			"%s's overlay follows it (%s, NPC at %s)" % [
				npc.name,
				overlay.global_position,
				npc.global_position,
			],
		)
		return
	t.check(false, "an NPC with an overlay to follow")


## An overlay moved off its owner still goes when the owner does, and follows it while it stays.
func _overlay_goes_with_its_owner(t: TestContext, world: Node) -> void:
	var owner := Node2D.new()
	world.add_child(owner)
	var overlay := Node2D.new()
	owner.add_child(overlay)
	ViewLayers.overlay(overlay)
	await t.frames(3)
	t.check(_layer_of(overlay) != null, "premise: the overlay moved onto the ground layer")
	owner.queue_free()
	await t.frames(3)
	t.check(not is_instance_valid(overlay), "the overlay left with its owner")


func _navigation_holes_are_flat(t: TestContext, built: Dictionary) -> void:
	var holes: Node = built.get("nav_debug")
	if not t.require(holes != null, "the match has the navigation holes overlay"):
		return
	t.check(_layer_of(holes) != null, "the navigation holes are on a ground layer")
	t.check((holes as CanvasItem).is_visible_in_tree(), "and draw")


## A flag still reaches an overlay that was moved, and the detail card's lookup finds it by name.
func _flags_reach_the_moved_overlays(t: TestContext, main: Node, built: Dictionary) -> void:
	main.set_overlay("show_vision", true)
	for npc: Node in built["combatants"]:
		if npc.get_node_or_null("GoalController") == null:
			continue
		var overlay := OverlayRegistryProbe.named(npc, "VisionDebug")
		if overlay != null:
			t.check(
				overlay.get("show_vision") == true,
				"the vision flag reaches %s's overlay" % npc.name,
			)
		t.check(
			OverlayRegistryProbe.found(npc, "AgentDebug"),
			"the detail card finds %s's agent overlay by name" % npc.name,
		)
	main.set_overlay("show_vision", false)


## The layer's transform is the 3D camera's affine from the ground to the screen, worked by hand at
## yaw 120 and zoom 1: the focus is the screen's middle and 100 px along +x is (-50, 85.287) from it
## (sin 80 * 100 * sin 120).
func _layer_is_the_cameras_affine(t: TestContext, viewport: SubViewport, built: Dictionary) -> void:
	var holes: Node = built.get("nav_debug")
	if holes == null or _layer_of(holes) == null:
		return
	var layer := _layer_of(holes) as CanvasLayer
	var middle := Vector2(viewport.size) * 0.5
	var at_focus := layer.transform * FOCUS
	var along_x := layer.transform * (FOCUS + Vector2(100.0, 0.0))
	t.check(
		at_focus.distance_to(middle) < 0.3,
		"the focus is mid-screen on the layer (%s)" % at_focus,
	)
	t.check(
		along_x.distance_to(middle + Vector2(-50.0, 85.287)) < 0.3,
		"100 px along +x lands (-50, 85.287) px from the middle at yaw 120 (%s)" % along_x,
	)
