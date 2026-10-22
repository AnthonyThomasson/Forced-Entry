extends GameTest
## LD11 (`docs/leadership.md`) with Debug on: the overlay toggle bar holds a column at the screen's
## right edge, and the command menu's panel docked on the right keeps clear of it, as the
## inspector's outfit panel does. Here the click is far into the left half: a right-click on the
## Terrace house's back doorway, two teammates beside it in the garden, each then selected by a
## left-click on its body, the leader far to the east so the framing puts the three well left. The
## panel docks on the right, its right edge the bar's column plus its gap from the screen's edge,
## beside the three, and meets neither the bar, the click nor a selected body. On a player's screen
## (the project's window size), headless too: the checks are `order_probe.gd`'s
## `check_clear_of_bar`.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "The command menu docked on the right keeps clear of the overlay bar",
		"description": "With the overlay toggle bar shown, a right-click on a doorway far into the "
			+ "left half of the screen docks the menu's panel on the right, left of the bar's "
			+ "column and clear of the click and the selected teammates (LD11).",
		"tags": ["ui", "hud", "leadership", "order", "overlays"],
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.lock_interaction([&"camera", &"pause"])
	# The teammates by the back doorway, the leader far east: the framing centres the three, so the
	# doorway and the teammates land well into the left half.
	s.actor(&"t1", &"puppet", Vector2(910, 300), { "faction": &"invader" })
	s.actor(&"t2", &"puppet", Vector2(950, 360), { "faction": &"invader" })
	s.actor(&"me", &"puppet", Vector2(1700, 330), { "faction": &"invader" })


func run(t: TestContext) -> void:
	await Order.check_clear_of_bar(
		t, Order.BACK_SOUTH, t.actor(&"me"), [t.actor(&"t1"), t.actor(&"t2")], "beside",
	)
