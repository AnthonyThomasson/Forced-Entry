extends GameTest
## The spectator detail card's Item section for an NPC holding nothing says "—" (the same dash every
## empty section says), not the inventory's "Unknown": the held item line before and after the NPC
## lets go of its gun.

const Inspector := preload("res://scenes/ui/hud/spectator_inspector.gd")
const OverlayToggles := preload("res://scenes/ui/overlays/overlay_toggles.gd")
const InspectorProbe := preload("res://tests/_ui/inspector_probe.gd")
const AT := Vector2(450, 250)


func describe() -> Dictionary:
	return {
		"name": "The detail card says — for an NPC holding nothing",
		"description": "A defender holding a pistol shows the pistol on the card's Item section; "
			+ "once it has dropped it, the held item line reads — and not Unknown.",
		"tags": ["ui", "inspector", "spectator"],
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
	var inspector := CanvasLayer.new()
	inspector.set_script(Inspector)
	t.world.add_child(inspector)
	inspector.call("setup", [npc], {}, OverlayToggles.RESERVED_WIDTH)
	await t.seconds(1.5)
	var card := inspector.get_node_or_null("DetailCard") as Control
	if not t.require(card != null, "the inspector builds a DetailCard"):
		return
	await InspectorProbe.right_click(t, npc.global_position)
	if not t.require(card.visible, "a right-click opens the card"):
		return
	var line := _held_line(card)
	t.check(npc.inventory.current_item() != null, "premise: the NPC holds an item")
	t.check(line.contains(npc.inventory.item_name()), "the held item is named: '%s'" % line)

	npc.inventory.drop_held(Vector2.ZERO)
	if not t.require(
			await t.until(func(): return npc.inventory.current_item() == null, 2.0),
			"premise: the NPC's hand is empty",
	):
		return
	await t.seconds(0.3)  # the card refreshes every 0.1 s
	line = _held_line(card)
	t.expect_eq(line, "—", "an empty hand reads —")
	inspector.queue_free()


## The first line of the card's Item section: the held item and its ammo.
func _held_line(card: Control) -> String:
	var labels := card.find_children("*", "Label", true, false)
	for i in labels.size() - 1:
		if (labels[i] as Label).text == "ITEM":
			return (labels[i + 1] as Label).text.split("\n")[0]
	return ""
