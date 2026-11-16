extends GameTest
## V7 (`docs/player-vision.md`): the overlays are drawn over the view, in their own colours, and
## are never remembered. In a world with the player's view, an NPC with every debug overlay on, the
## navigation holes, the squad leaders' crowns and the stack, order and contact markers each sit on
## the visibility bit `ViewLayers.OVERLAY` (so no mover's cut or remembered look touches them) and,
## in the 3D render (`GroundLayer.enabled`, with the match's shared ground layer), lie flat on the
## ground under that layer, over the 3D picture and under the HUD, still visible.
## (`general/ground_overlays_3d` runs Main whole and follows the layer's transform with the
## camera.)
##
## It reads (tests/_vision/vision_probe.gd) each overlay's `visibility_layer`, its place under a
## `GroundLayer` and `GroundLayer.overlays_of`; the NPC's overlays are found by the flags of the
## overlay table (`OverlayRegistry`).

const Probe := preload("res://tests/_vision/vision_probe.gd")
const Registry := preload("res://scenes/ui/overlays/overlay_registry.gd")
const StackMarkers := preload("res://scenes/ui/hud/stack_markers.gd")
const OrderMarkers := preload("res://scenes/ui/command/order_markers.gd")
const ContactMarkers := preload("res://scenes/ui/hud/contact_markers.gd")
## Overlays that are not drawn in the world (the performance panel is a screen panel).
const NOT_IN_WORLD := [Registry.PERF]


func describe() -> Dictionary:
	return {
		"name": "The overlays and markers draw over the view and are never remembered",
		"description": "Every debug overlay of an NPC, the navigation holes, the leaders' crowns "
			+ "and the stack, order and contact markers are on ViewLayers.OVERLAY and lie flat "
			+ "under the match's ground layer, visible.",
		"tags": ["vision", "ui", "overlay", "render", "3d"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1400, 700))
	s.set_static(GroundLayer, &"enabled", true)
	s.switch(&"vision.enabled", true)
	s.actor(&"you", &"player", Vector2(150, 350))
	s.actor(&"npc", &"defender", Vector2(700, 350))
	s.actor(&"mate", &"puppet", Vector2(400, 200))
	s.squads({ "human": &"you" })
	s.von_script([{ "pick": "investigate" }])
	var flags: Array = []
	for row: Dictionary in Registry.ENTRIES:
		if not NOT_IN_WORLD.has(row["flag"]):
			flags.append(row["flag"])
	s.show_overlays(flags)


func run(t: TestContext) -> void:
	var view := Probe.view(t)
	if not t.require(view != null and view.ground != null, "the world has a 3D view"):
		return
	await t.frames(3)
	# The match's one layer for the overlays, made as the 3D view makes it; what is made after it
	# is adopted at once, what was made before is handed to it.
	var layer := GroundLayer.shared()
	t.world.add_child(layer)
	var overlays := _overlays(t)
	await t.frames(2)
	for named: String in overlays:
		if _layer_of(overlays[named]) == null:
			GroundLayer.adopt(overlays[named])
	await t.frames(3)
	for named: String in overlays:
		var item: CanvasItem = overlays[named]
		t.check(
			item.visibility_layer == ViewLayers.OVERLAY,
			"%s is on ViewLayers.OVERLAY (layer %d)" % [named, item.visibility_layer],
		)
		t.check(_layer_of(item) == layer, "%s lies flat under the ground layer" % named)
		t.check(item.is_visible_in_tree(), "%s is visible" % named)
	GroundLayer.forget()


## The ground layer `item` is drawn under, or null.
func _layer_of(item: Node) -> GroundLayer:
	var node := item.get_parent()
	while node != null and not node is GroundLayer:
		node = node.get_parent()
	return node as GroundLayer


## Every overlay of the world by a name for a failure line: the NPC's (one for each per-NPC flag of
## the table, as the table says), the navigation holes, the leaders' crowns, and the three kinds of
## markers made as Main makes them.
func _overlays(t: TestContext) -> Dictionary:
	var out := {}
	var npc := t.actor(&"npc")
	for row: Dictionary in Registry.ENTRIES:
		var flag: String = row["flag"]
		if Registry.is_global(flag):
			continue
		var found := false
		for child in npc.get_children():
			if flag in child:
				out["%s (%s)" % [child.name, flag]] = child
				found = true
		t.check(found, "premise: the NPC has an overlay for %s" % flag)
	var holes := _with(t.world, "show_holes")
	t.check(holes != null, "premise: the world has the navigation holes overlay")
	if holes != null:
		out["nav holes"] = holes
	var crowns := _with(t.world, Registry.LEADERS)
	t.check(crowns != null, "premise: the world has the squad leaders overlay")
	if crowns != null:
		out["leaders"] = crowns
	out["stack markers"] = _stack_markers(t)
	out["order markers"] = _order_markers(t)
	out["contact markers"] = _contact_markers(t)
	return out


## The first node under `root` that has the property `flag`, or null.
func _with(root: Node, flag: String) -> Node:
	for node in root.find_children("*", "", true, false):
		if flag in node:
			return node
	return null


func _stack_markers(t: TestContext) -> Node2D:
	var stack := FakeStack.new()
	t.world.add_child(stack)
	var markers: Node2D = StackMarkers.new()
	t.world.add_child(markers)
	markers.watch(stack)
	return markers


func _order_markers(t: TestContext) -> Node2D:
	var markers: Node2D = OrderMarkers.new()
	t.world.add_child(markers)
	markers.watch(func() -> Dictionary: return {})
	return markers


func _contact_markers(t: TestContext) -> Node2D:
	var markers: Node2D = ContactMarkers.new()
	t.world.add_child(markers)
	markers.set_contacts([])
	return markers


## A stand-in for the human's stack: whatever `view()` it is told to give.
class FakeStack extends Node:
	var current := {}

	func view() -> Dictionary:
		return current
