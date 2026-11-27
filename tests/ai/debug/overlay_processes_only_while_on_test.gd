extends GameTest
## A debug overlay that is off does not process (#194 perf: a match holds hundreds), as built and
## after its toggles are turned off; turned on, it processes and redraws on the next frame. The
## tactics overlay processes with both toggles off, as it draws the ring of the controller's
## `debug_focus`.

const Registry := preload("res://scenes/ui/overlays/overlay_registry.gd")
const BASE := "res://scenes/ai/debug/debug_overlay.gd"
const TACTICS := "TacticsDebug"


func describe() -> Dictionary:
	return {
		"name": "A debug overlay processes only while it is on",
		"description": "Every AI overlay that is off has its processing off, from its building and "
			+ "its toggles' setters; turned on it redraws next frame; the tactics overlay keeps "
			+ "following the debug focus.",
		"tags": ["overlays", "debug", "perf"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 500, 300))
	s.switch(&"nav.rebake", false)
	s.actor(&"npc", &"defender", Vector2(250, 150))


func run(t: TestContext) -> void:
	await t.frames(3)
	var npc: Node = t.actor(&"npc")
	var overlays := Registry.overlays_of(npc).filter(_is_overlay)
	if not t.require(overlays.size() >= 14, "the NPC has its overlays (%d)" % overlays.size()):
		return
	for overlay: Node in overlays:
		_check_processing(t, overlay, overlay.call("_on"), "as built")
	_set_all(overlays, false)
	for overlay: Node in overlays:
		_check_processing(t, overlay, false, "toggled off")
	var drawn := {}
	await t.frames(2)
	for overlay: CanvasItem in overlays:
		overlay.draw.connect(func() -> void: drawn[overlay.name] = true)
	await t.frames(2)
	var quiet := drawn.keys().filter(func(n: StringName) -> bool: return n != TACTICS)
	t.check(quiet.is_empty(), "off, none redraws (%s)" % str(quiet))
	_set_all(overlays, true)
	for overlay: Node in overlays:
		_check_processing(t, overlay, true, "toggled on")
	await t.frames(2)
	for overlay: Node in overlays:
		t.check(drawn.has(overlay.name), "%s redraws once on" % overlay.name)
	_set_all(overlays, false)
	await _check_focus(t, npc)


func _is_overlay(node: Node) -> bool:
	var script: Script = node.get_script()
	while script != null:
		if script.resource_path == BASE:
			return true
		script = script.get_base_script()
	return false


## The tactics overlay processes whatever its toggles say; the others as `on`.
func _check_processing(t: TestContext, overlay: Node, on: bool, when: String) -> void:
	var want := on or overlay.name == TACTICS
	var got := overlay.is_processing()
	t.check(got == want, "%s %s: processing %s (want %s)" % [overlay.name, when, got, want])


## Set every `show_*` flag of `overlays`.
func _set_all(overlays: Array, on: bool) -> void:
	for overlay: Node in overlays:
		for property: Dictionary in overlay.get_property_list():
			if String(property["name"]).begins_with("show_") and property["type"] == TYPE_BOOL:
				overlay.set(property["name"], on)


## With both its toggles off the tactics overlay still redraws for a new debug focus.
func _check_focus(t: TestContext, npc: Node) -> void:
	var tactics := Registry.overlay_of(npc, TACTICS) as CanvasItem
	await t.frames(2)
	var redrawn := [0]
	tactics.draw.connect(func() -> void: redrawn[0] += 1)
	npc.get_node(^"GoalController").set("debug_focus", Vector2(300, 150))
	await t.frames(3)
	t.check(redrawn[0] > 0, "tactics off still draws the debug focus")
