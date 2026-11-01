extends GameTest
## V7 (`docs/player-vision.md`): the overlays are drawn over the view, in their own colours, and are
## never remembered. In a world with the player's view, an NPC with every debug overlay on, the
## navigation holes, the squad leaders' crowns and the stack, order and contact markers each draw
## at `DrawLayers.OVERLAY` (an absolute z, above the view's composite at `DrawLayers.VISION`) and
## sit on the visibility bit `ViewLayers.OVERLAY`, which the capture leaves out.
##
## It reads (tests/_vision/vision_probe.gd) the `PlayerView`'s `composite()` and `capture()`, and
## each overlay's `z_index`, `z_as_relative` and `visibility_layer`; the NPC's overlays are found by
## the flags of the overlay table (`OverlayRegistry`).

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
			+ "and the stack, order and contact markers are at DrawLayers.OVERLAY (absolute, above "
			+ "the view) on ViewLayers.OVERLAY, which the capture leaves out.",
		"tags": ["vision", "ui", "overlay"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1400, 700))
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
	if not t.require(view != null, "the world has a view"):
		return
	await t.frames(3)
	var overlays := _overlays(t)
	var composite := view.composite()
	t.check(_absolute_z(composite) == DrawLayers.VISION, "premise: the view is at VISION")
	t.check(
		(view.capture().canvas_cull_mask & ViewLayers.OVERLAY) == 0,
		"premise: the capture leaves OVERLAY out",
	)
	for named: String in overlays:
		var item: CanvasItem = overlays[named]
		t.check(
			_absolute_z(item) == DrawLayers.OVERLAY,
			"%s is at DrawLayers.OVERLAY, absolute (z %d)" % [named, _absolute_z(item)],
		)
		t.check(not item.z_as_relative, "%s sets its z absolute" % named)
		t.check(
			_absolute_z(item) > _absolute_z(composite),
			"%s is drawn over the view" % named,
		)
		t.check(
			item.visibility_layer == ViewLayers.OVERLAY,
			"%s is on ViewLayers.OVERLAY (layer %d)" % [named, item.visibility_layer],
		)
		t.check(not Probe.in_capture(view, item), "%s is not drawn by the capture" % named)


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


## Where `item` is drawn on the z ladder: its own rung when absolute, else the sum up its parents.
func _absolute_z(item: CanvasItem) -> int:
	var z := item.z_index
	var at: Node = item
	while at is CanvasItem and (at as CanvasItem).z_as_relative:
		at = at.get_parent()
		if at is CanvasItem:
			z += (at as CanvasItem).z_index
	return z


## A stand-in for the human's stack: whatever `view()` it is told to give.
class FakeStack extends Node:
	var current := {}

	func view() -> Dictionary:
		return current
