extends GameTest
## With an NPC selected, a left-click on one of its tactical points (an entry of its
## `debug_zones()`) highlights the point (the controller's `debug_focus`, which its tactics overlay
## rings) and fills the card's Point section with the point's category, label and the reasoning text
## Von read. Before the click the section says "—"; a left-click on nothing leaves it as it was. The
## clicks are real mouse input at a world point's place on screen (once the framing camera has
## settled). Scripted Von (the first option offered), and an intruder in view, so the NPC has
## weighed points to click.

const Inspector := preload("res://scenes/ui/hud/spectator_inspector.gd")
const OverlayToggles := preload("res://scenes/ui/overlays/overlay_toggles.gd")
const InspectorProbe := preload("res://tests/_ui/inspector_probe.gd")
const AT := Vector2(450, 250)
## How near (px) two points may lie before a click on one may pick the other.
const NEAR := 40.0


func describe() -> Dictionary:
	return {
		"name": "A left-click on a tactical point fills the card's Point section",
		"description": "With a defender selected by a right-click, a left-click on one of its "
			+ "weighed points sets its debug_focus and shows the point's category, label and "
			+ "reasoning in the card.",
		"tags": ["ui", "inspector", "spectator"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.von_script([])
	s.lock_interaction([&"camera", &"pause"])
	s.actor(&"npc", &"defender", AT, { "movement:speed": 0.0, "facing": Vector2.RIGHT })
	# An intruder in plain view, unkillable: the defender weighs fire and flank points against it.
	s.actor(
		&"intruder",
		&"puppet",
		AT + Vector2(250, 0),
		{ "faction": &"invader", "max_health": 1_000_000.0, "facing": Vector2.LEFT },
	)


func run(t: TestContext) -> void:
	var npc := t.actor(&"npc")
	var ctrl := t.controller(&"npc", &"debug_zones")
	var inspector := CanvasLayer.new()
	inspector.set_script(Inspector)
	t.world.add_child(inspector)
	inspector.call("setup", [npc], { "show_tactics": true }, OverlayToggles.RESERVED_WIDTH)
	await t.seconds(1.5)  # the framing camera settles, so a point's place on screen holds still
	var card := inspector.get_node_or_null("DetailCard") as Control
	if not t.require(card != null, "the inspector builds a DetailCard"):
		return
	if not t.require(
			await t.until(func(): return not _pickable(ctrl.debug_zones()).is_empty(), 8.0),
			"the NPC weighs a point to click",
	):
		return
	await InspectorProbe.click(t, npc.global_position, MOUSE_BUTTON_RIGHT)
	if not t.require(card.visible, "a right-click opens the card"):
		return
	t.check(_point_section(card) == "—", "the Point section says — before a point is clicked")
	t.check(ctrl.debug_focus == Vector2.INF, "and no point is highlighted")

	var zone := {}
	for attempt in 3:  # a new decision in between may change the points: take them fresh
		var zones := _pickable(ctrl.debug_zones())
		if zones.is_empty():
			continue
		zone = zones[0]
		await InspectorProbe.click(t, zone["point"], MOUSE_BUTTON_LEFT)
		if ctrl.debug_focus == zone["point"]:
			break
		zone = {}
	if not t.require(not zone.is_empty(), "a left-click on a point highlights it (debug_focus)"):
		return
	await t.frames(2)
	var shown := _point_section(card)
	t.check(shown.contains(String(zone["category"]).to_upper()), "the card names its category")
	t.check(String(zone.get("label", "")) != "", "premise: the point has a label")
	t.check(String(zone.get("desc", "")) != "", "premise: the point has a reasoning text")
	t.check(shown.contains(String(zone["label"])), "and its label:\n%s" % shown)
	t.check(shown.contains(String(zone.get("desc", ""))), "and its reasoning:\n%s" % shown)

	await InspectorProbe.click(t, Vector2(30, 470), MOUSE_BUTTON_LEFT)
	t.check(ctrl.debug_focus == zone["point"], "a left-click on nothing keeps the point")
	await InspectorProbe.click(t, npc.global_position, MOUSE_BUTTON_RIGHT)
	t.check(ctrl.debug_focus == Vector2.INF, "closing the card clears the highlight")
	inspector.queue_free()


## The zones of `zones` that have a label and a reasoning text and that no other zone is near enough
## to be picked instead (a click on a point where two lie would pick either).
func _pickable(zones: Array) -> Array:
	var out := []
	for zone: Dictionary in zones:
		var alone := String(zone.get("label", "")) != "" and String(zone.get("desc", "")) != ""
		for other: Dictionary in zones:
			if other != zone and (other["point"] as Vector2).distance_to(zone["point"]) < NEAR:
				alone = false
		if alone:
			out.append(zone)
	return out


## The body text of the card's Point section: the label after the POINT heading.
func _point_section(card: Control) -> String:
	var labels := card.find_children("*", "Label", true, false)
	for i in labels.size() - 1:
		if (labels[i] as Label).text == "POINT":
			return (labels[i + 1] as Label).text
	return ""
