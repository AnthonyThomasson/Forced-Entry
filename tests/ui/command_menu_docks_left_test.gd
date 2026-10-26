extends GameTest
## LD11 (`docs/leadership.md`): the command menu's panel docks on the side of the screen away from
## the click that opened it, so it never covers what it is about. Here the click is in the right
## half: a right-click on a teammate's body in the Terrace house's back garden, then a left-click on
## it and on the teammate beside it to select both. The panel docks on the left and covers neither
## the click nor a selected body. On a player's screen (the project's window size), headless too:
## the checks are `order_menu_probe.gd`'s `check_dock`.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const OrderMenu := preload("res://tests/_ai/order_menu_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A click in the right half docks the command menu on the left",
		"description": "A right-click on a teammate in the right half of the screen opens the "
			+ "menu with its panel docked on the left, clear of the click and of the teammates "
			+ "selected there (LD11).",
		"tags": ["ui", "hud", "leadership", "order"],
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.lock_interaction([&"camera", &"pause"])
	# The leader by the back doorway on the left, its teammates on the right (the framing centres
	# the three).
	s.actor(&"t1", &"puppet", Vector2(1150, 330), { "faction": &"invader" })
	s.actor(&"t2", &"puppet", Vector2(1110, 420), { "faction": &"invader" })
	s.actor(&"me", &"puppet", Vector2(900, 500), { "faction": &"invader" })


func run(t: TestContext) -> void:
	var t1 := t.actor(&"t1")
	await OrderMenu.check_dock(t, t1.global_position, t.actor(&"me"), [t1, t.actor(&"t2")], "right")
