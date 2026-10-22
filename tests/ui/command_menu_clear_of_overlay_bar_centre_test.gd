extends GameTest
## LD11 (`docs/leadership.md`) with Debug on: a click in the left half close to the centre, where
## the command menu's panel cannot dock on the right beside it (its column, left of the overlay
## bar's, holds the click and the teammates), docks it at the top or the bottom of the screen
## instead, still on the right, so it covers neither the bar, the click nor a selected body. The
## camera frames the leader alone, so the back doorway and the two teammates by it sit in the band
## near the screen's bottom that a panel hanging from the top leaves free; a right-click on the
## doorway, then a left-click on each teammate's body to select it. On a player's screen (the
## project's window size), headless too: the checks are `order_probe.gd`'s `check_clear_of_bar`.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "The command menu docks above or below a click near the centre",
		"description": "With the overlay toggle bar shown, a right-click on a doorway in the left "
			+ "half close to the centre docks the menu's panel at the top or the bottom of the "
			+ "screen, on the right, clear of the bar, the click and the teammates selected "
			+ "(LD11).",
		"tags": ["ui", "hud", "leadership", "order", "overlays"],
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.lock_interaction([&"camera", &"pause"])
	# The camera frames the leader alone (at its closest zoom): north of the teammates in the back
	# garden, it puts them and the back doorway near the screen's bottom, left of its centre.
	s.actor(&"t1", &"puppet", Vector2(905, 268), { "faction": &"invader" })
	s.actor(&"t2", &"puppet", Vector2(935, 250), { "faction": &"invader" })
	s.actor(&"me", &"puppet", Vector2(960, 117), { "faction": &"invader" })
	s.camera_follow([&"me"])


func run(t: TestContext) -> void:
	await Order.check_clear_of_bar(
		t, Order.BACK_SOUTH, t.actor(&"me"), [t.actor(&"t1"), t.actor(&"t2")], "vertical",
	)
