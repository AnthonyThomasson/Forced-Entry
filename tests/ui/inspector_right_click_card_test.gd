extends GameTest
## The spectator inspector selects with the right button: a right-click on an NPC selects it (its
## overlays show) and opens its detail card, docked top-left, holding its name and side, the held
## item and its ammo, what it wears (each garment and plate by name, with the plates' condition,
## docs/outfits.md O13) and its decision path; a right-click on it again, or on empty ground, closes
## the card and clears the selection; a left-click on an NPC does nothing. Nothing is shown before
## the first right-click. The clicks are real mouse input at a world point's place on screen (once
## the framing camera has settled); the NPC's vision overlay turning on shows the click selected it.

const OutfitProbe := preload("res://tests/_outfit/outfit_probe.gd")
const Inspector := preload("res://scenes/ui/hud/spectator_inspector.gd")
const OverlayToggles := preload("res://scenes/ui/overlays/overlay_toggles.gd")
const InspectorProbe := preload("res://tests/_ui/inspector_probe.gd")
const AT := Vector2(450, 250)
## Empty ground, far from the NPC: a click there clears the selection.
const GROUND := Vector2(150, 420)
const KIT := {
	"head": &"helmet", "body": &"shirt", "vest": &"plate_carrier", "pants": &"tactical_pants",
	"feet": &"boots", "front_plate": &"ceramic_iv", "back_plate": &"steel_iii",
}


func describe() -> Dictionary:
	return {
		"name": "A right-click opens the selected NPC's detail card",
		"description": "Right-clicking an NPC in a helmet, shirt, plate carrier (ceramic front, "
			+ "steel back), tactical pants and boots selects it and opens a card with its name "
			+ "and side, item and ammo, every garment and plate with its condition and its "
			+ "decision path; right-clicking it again or empty ground closes the card; a "
			+ "left-click on it selects nothing.",
		"tags": ["outfit", "ui", "inspector", "spectator"],
		"timeout": 8.0,
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
	if not OutfitProbe.require_api(t, npc):
		return
	if not t.require(
			not OutfitProbe.options().is_empty(),
			"LoadoutConfig.outfit_options() names the plates (docs/outfits.md O11)",
	):
		return
	OutfitProbe.wear(npc, KIT)
	var inspector := CanvasLayer.new()
	inspector.set_script(Inspector)
	t.world.add_child(inspector)
	# the width Main hands it
	inspector.call("setup", [npc], { "show_vision": true }, OverlayToggles.RESERVED_WIDTH)
	await t.seconds(1.5)  # the framing camera settles, so a point's place on screen holds still
	var card := inspector.get_node_or_null("DetailCard") as Control
	if not t.require(card != null, "the inspector builds a DetailCard"):
		return
	t.check(not card.visible, "no card before an NPC is selected")

	await InspectorProbe.click(t, npc.global_position, MOUSE_BUTTON_LEFT)
	t.check(not _vision_on(npc) and not card.visible, "a left-click on an NPC selects nothing")

	await InspectorProbe.click(t, npc.global_position, MOUSE_BUTTON_RIGHT)
	if not t.require(
			_vision_on(npc) and card.visible, "a right-click selects the NPC and opens its card",
	):
		return
	_check_card(t, card, npc)

	await InspectorProbe.click(t, npc.global_position, MOUSE_BUTTON_RIGHT)
	t.check(not _vision_on(npc) and not card.visible, "a second right-click closes the card")
	await InspectorProbe.click(t, npc.global_position, MOUSE_BUTTON_RIGHT)
	t.check(_vision_on(npc) and card.visible, "and a right-click opens it again")
	await InspectorProbe.click(t, GROUND, MOUSE_BUTTON_RIGHT)
	t.check(
		not _vision_on(npc) and not card.visible,
		"a right-click on empty ground clears the selection and closes the card",
	)
	inspector.queue_free()


## What the open `card` holds of `npc`: its name and side, item and ammo, outfit and decision path.
func _check_card(t: TestContext, card: Control, npc: Node) -> void:
	var shown := _shown(card)
	t.check(shown.contains(str(npc.name)), "the card names the NPC:\n%s" % shown)
	t.check(shown.contains("defender"), "and its side")
	t.check(shown.contains(npc.inventory.item_name()), "and the held item")
	var rounds: int = npc.ammo.rounds()
	t.check(rounds >= 0, "premise: the held item has ammo")
	t.check(shown.contains("%d/%d" % [rounds, npc.ammo.capacity()]), "and its ammo")
	var names: Array[String] = []
	var view := OutfitProbe.view(npc)
	for slot: String in ["head", "body", "vest", "pants", "feet"]:
		names.append(str(view.get(slot, "")))
	for side: String in ["front_plate", "back_plate"]:
		names.append(OutfitProbe.label_of(side, KIT[side]))
	t.check(not names.has(""), "every garment and plate has a name to show (%s)" % [names])
	for n: String in names:
		t.check(shown.contains(n), "the card lists %s" % n)
	t.check(shown.contains("100%"), "and the plates' condition (100%%, new)")
	var path: String = t.controller(&"npc", &"debug_status").debug_status()
	t.check(path != "" and shown.contains(path), "and the decision path '%s'" % path)


## Whether `npc`'s vision overlay is switched on.
func _vision_on(npc: Node) -> bool:
	for child in npc.get_children():
		if "show_vision" in child and bool(child.get("show_vision")):
			return true
	return false


## The text of every visible label under `node`, one per line.
func _shown(node: Node) -> String:
	var out: Array[String] = []
	for label in node.find_children("*", "Label", true, false):
		if (label as Label).is_visible_in_tree():
			out.append((label as Label).text)
	return "\n".join(out)
