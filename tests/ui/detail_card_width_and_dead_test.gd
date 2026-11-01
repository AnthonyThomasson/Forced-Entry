extends GameTest
## The spectator detail card is 560 px wide at the default window, docked top-left under the match
## timer, and clear of the overlay bar's column; when the NPC it shows dies the card stays open with
## "· DEAD" in its title and "dead" for its health, until it is closed. Geometry and text read off
## the card's rect and labels.

const Inspector := preload("res://scenes/ui/hud/spectator_inspector.gd")
const OverlayToggles := preload("res://scenes/ui/overlays/overlay_toggles.gd")
const OrderMenu := preload("res://tests/_ai/order_menu_probe.gd")
const InspectorProbe := preload("res://tests/_ui/inspector_probe.gd")
const AT := Vector2(450, 250)
## The card's width, left edge and top the brief names (px), and the window's width.
const WIDTH := 560.0
const LEFT := 24.0
const TOP := 76.0
const WINDOW_WIDTH := 1152.0


func describe() -> Dictionary:
	return {
		"name": "The detail card is 560 px wide and marks a dead NPC",
		"description": "A defender's card is 560 px wide at the default window, docked top-left "
			+ "and clear of the overlay bar; once the defender dies the card stays open, its "
			+ "title ending in DEAD and its health reading dead.",
		"tags": ["ui", "inspector", "spectator"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"ai.vision", false)
	s.von_down()
	s.lock_interaction([&"camera", &"pause"])
	s.actor(&"npc", &"defender", AT, { "movement:speed": 0.0 })


func run(t: TestContext) -> void:
	var npc := t.actor(&"npc")
	OrderMenu.player_screen(t, true)
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
	var rect := card.get_global_rect()
	t.expect_eq(rect.position, Vector2(LEFT, TOP), "the card is docked top-left under the timer")
	t.expect_eq(rect.size.x, WIDTH, "the card is 560 px wide")
	t.check(
		rect.end.x <= WINDOW_WIDTH - OverlayToggles.RESERVED_WIDTH,
		"and clear of the overlay bar's column (%s)" % rect,
	)
	var title: Label = _labels(card)[0]
	t.check(not title.text.contains("DEAD"), "premise: a living NPC's title is not marked dead")

	npc.take_damage(1.0e9)
	if not t.require(
			await t.until(func(): return npc.is_dead, 2.0), "premise: the damage kills the NPC",
	):
		return
	await t.seconds(0.4)  # the card refreshes every 0.1 s
	t.check(card.visible, "the card of a dead NPC stays open")
	t.check(title.text.ends_with("· DEAD"), "its title ends in DEAD: '%s'" % title.text)
	t.check(_labels(card).any(func(l): return l.text == "dead"), "and its health says dead")
	await InspectorProbe.right_click(t, npc.global_position)
	t.check(not card.visible, "a right-click on the body closes the card")
	inspector.queue_free()


## The labels of `card`, top to bottom.
func _labels(card: Control) -> Array:
	return card.find_children("*", "Label", true, false)
