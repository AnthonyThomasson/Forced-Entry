extends GameTest
## LD11 (`docs/leadership.md`) with Debug on, the crowded case: the command menu's panel docked on
## the right covers a selected teammate however it docks (beside the click, at the top or at the
## bottom of the screen), so it docks on the vertical side away from the centre of the click and the
## selected bodies, still clear of the overlay bar and of the click. The camera frames the leader
## alone: the back doorway and one teammate sit near the screen's bottom, left of its centre, the
## other teammate by the middle of the screen, where any dock on the right covers it; a right-click
## on the doorway, then both teammates ticked in the panel (the panel covers one of them). On a
## player's screen (the project's window size), headless too: the checks are `order_probe.gd`'s
## `check_clear_of_bar`.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A crowded command menu docks away from the click and the selection",
		"description": "With the overlay toggle bar shown, when no dock on the right clears a "
			+ "selected teammate, the menu's panel docks at the top or the bottom of the screen "
			+ "away from the click and the selection, still clear of the bar and the click (LD11).",
		"tags": ["ui", "hud", "leadership", "order", "overlays"],
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.lock_interaction([&"camera", &"pause"])
	# The camera frames the leader alone (at its closest zoom): t1 and the back doorway land near
	# the screen's bottom, t2 beside the leader near the middle of the screen.
	s.actor(&"t1", &"puppet", Vector2(905, 268), { "faction": &"invader" })
	s.actor(&"t2", &"puppet", Vector2(900, 130), { "faction": &"invader" })
	s.actor(&"me", &"puppet", Vector2(960, 117), { "faction": &"invader" })
	s.camera_follow([&"me"])


func run(t: TestContext) -> void:
	await Order.check_clear_of_bar(
		t, Order.BACK_SOUTH, t.actor(&"me"), [t.actor(&"t1"), t.actor(&"t2")], "crowded",
	)
