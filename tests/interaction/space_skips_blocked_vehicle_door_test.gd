extends GameTest
## A candidate that cannot act is skipped (ticket #193, decision G7): Space falls back to the next
## nearest. The car's front-left door cannot open, an armchair standing in its swing, and the
## mouse is on the car, nearer it than the armchair. Space sits on the armchair instead of doing
## nothing; with the armchair gone the same press boards.
##
## The car (220 x 110 at (620, 300), front-left handle (600, 245), hinge (635, 245), the rear-left
## handle 50 px further back, out of the player's reach) has the armchair (50 x 50 at (610, 200))
## in its front-left door's swing. The player stands at (655, 230), 56 px from the handle and 20 px
## from the armchair.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const PlayerPointer := preload("res://tests/_character/player_pointer_probe.gd")
const STANDING := Vector2(655, 230)
## Inside the car, just past its front-left handle; the armchair's nearest point is 25 px away.
const ON_THE_CAR := Vector2(600, 250)


func describe() -> Dictionary:
	return {
		"name": "Space skips a vehicle door that cannot open",
		"description": "An armchair blocks the car's only door in reach, and the mouse is on the "
			+ "car: Space sits on the armchair; with it gone Space boards the car.",
		"tags": ["interaction", "vehicle", "player", "input", "keybinds"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(620, 300))
	s.object(&"chair", "armchair", Vector2(610, 200))
	s.actor(&"you", &"player", STANDING)


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"you"]):
		return
	var you := t.actor(&"you")
	await PlayerPointer.aim(t, you, ON_THE_CAR)
	t.check(not you.use.interactions_in_reach().is_empty(), "premise: the armchair is in reach")
	await _tap(t)
	t.check(you.use.is_busy() and you.use.vehicle() == null, "Space sits on the armchair")
	await t.seconds(0.5)
	t.check(you.use.vehicle() == null, "and the blocked door never opened")
	await _tap(t)
	if not t.require(
			await t.until(func(): return not you.use.is_busy(), 1.0), "Space again stands up"
	):
		return

	t.object(&"chair").free()
	await t.seconds(0.3)
	you.global_position = STANDING
	await PlayerPointer.aim(t, you, ON_THE_CAR)
	await _tap(t)
	t.check(
		await t.until(func(): return you.use.is_in_vehicle(), 6.0),
		"with the armchair gone the same press boards: it was the armchair blocking the door",
	)


## Tap Space: press for a few frames, then release.
func _tap(t: TestContext) -> void:
	Input.action_press(Keybinds.INTERACT)
	await t.frames(2)
	Input.action_release(Keybinds.INTERACT)
	await t.frames(1)
