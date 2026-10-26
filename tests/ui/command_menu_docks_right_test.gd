extends GameTest
## LD11 (`docs/leadership.md`): the command menu's panel docks on the side of the screen away from
## the click that opened it, so it never covers what it is about. Here the click is in the left
## half: a right-click on the Terrace house's back doorway, two teammates beside it in the garden,
## each then selected by a left-click on its body. The panel docks on the right and covers neither
## the click nor a selected body. On a player's screen (the project's window size), headless too:
## the checks are `order_menu_probe.gd`'s `check_dock`.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const OrderMenu := preload("res://tests/_ai/order_menu_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A click in the left half docks the command menu on the right",
		"description": "A right-click on a doorway in the left half of the screen opens the menu "
			+ "with its panel docked on the right, clear of the click and of the teammates "
			+ "selected beside it (LD11).",
		"tags": ["ui", "hud", "leadership", "order"],
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.lock_interaction([&"camera", &"pause"])
	# The leader on the right, its teammates by the back doorway on the left (the framing centres
	# the three).
	s.actor(&"t1", &"puppet", Vector2(900, 330), { "faction": &"invader" })
	s.actor(&"t2", &"puppet", Vector2(940, 420), { "faction": &"invader" })
	s.actor(&"me", &"puppet", Vector2(1150, 500), { "faction": &"invader" })


func run(t: TestContext) -> void:
	await OrderMenu.check_dock(
		t, Order.BACK_SOUTH, t.actor(&"me"), [t.actor(&"t1"), t.actor(&"t2")], "left",
	)
