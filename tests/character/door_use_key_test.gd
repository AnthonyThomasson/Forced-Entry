extends GameTest
## DR6 (ticket #21): the Use key (E) works a door. A tap swings a shut door fully open and a second
## shuts it again, the door turning at the release of the key (a hold is for scrolling, DR7); with a
## door and a vehicle's door both in reach E acts on the nearer; in a vehicle E gets out, though a
## door stands in reach.
##
## A south room holds a car (220 x 110 at (620, 300): its front-left handle at (600, 245), its
## rear-left one at (550, 245), the driver's seat at (630, 275) facing east). The wall above it,
## y = 170, has a doorway at x = 580 whose hollow door `d` is hinged on its west jamb, x = 560, and
## swings down into the room; the leaf standing open lies 3 px east of the hinge, from 3.5 to
## 42.5 px below the wall. A second wall, at x = 760, has a doorway at y = 250 whose door `e` stands
## open, in the seat's line east. The player is always at one of the spots below.

const PlayerPointer := preload("res://tests/_character/player_pointer_probe.gd")
const ALONE := Vector2(580, 140)
## West of the open leaf, its end 19 px away, with the car's rear-left handle 45 px away, within
## its 60 px reach: the door is the nearer.
const BY_THE_DOOR := Vector2(544, 200)
## Beside the car's front-left handle (18 px) with the open leaf's end 43 px away, within the door
## reach of 48 px: the car's door is the nearer.
const BY_THE_CAR := Vector2(603, 227)
## The middle of `d`'s leaf standing open.
const OPEN_LEAF := Vector2(563, 193)
## The door reach a seated player is given: from the seat the doorway is far, whatever is near the
## car.
const SEATED_REACH := 150.0
## A door ajar: part way open (the brief's ajar is 15 to 35).
const AJAR := 25.0
## A door "fully open" is the brief's 90 degrees.
const FULL := 90.0


func describe() -> Dictionary:
	return {
		"name": "Use opens and shuts a door, or acts on the nearer of door and vehicle",
		"description": "E tapped swings a shut door open and again shuts it (turning at the "
			+ "release); beside a door and a car's door it acts on the nearer, either way; seated, "
			+ "it gets out with a door in reach.",
		"tags": ["door", "player", "input", "keybinds", "vehicle"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "north", "type": "living_room", "rect": Rect2(0, 0, 800, 170) },
		{ "key": "south", "type": "bedroom", "rect": Rect2(0, 170, 760, 430) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(760, 170, 40, 430) },
	], [{
		"pos": Vector2(580, 170), "width": 52.0,
		"door": {
			"name": "d", "material": "hollow", "style": "flush",
			"hinge": Vector2(560, 170), "swing_into": Vector2.DOWN,
		},
	}, {
		"pos": Vector2(760, 250), "width": 52.0,
		"door": {
			"name": "e", "material": "hollow", "style": "flush",
			"hinge": Vector2(760, 230), "swing_into": Vector2.LEFT, "angle": 90.0,
		},
	}])
	s.set_static(
		CharacterDoorConfig,
		&"reach",
		CharacterDoorConfig.reach,
	)  # restored after the test
	s.von_down()
	s.vehicle(&"car", &"car", Vector2(620, 300))
	s.actor(&"you", &"player", ALONE)


func run(t: TestContext) -> void:
	var you := t.actor(&"you")
	var door := t.object(&"d")
	var east := t.object(&"e")
	if not t.require(
			door != null and east != null and t.vehicle(&"car") != null,
			"the two doors and the car stand",
	):
		return
	await _tap_opens_and_shuts(t, you, door)
	await _door_nearer(t, you, door)
	if await _vehicle_nearer(t, you, door):
		await _seated_beside_a_door(t, you, east)


## Alone with the door: held, nothing moves; a tap opens it at the release and the next shuts it.
func _tap_opens_and_shuts(t: TestContext, you: Node, door: Node) -> void:
	await _place(t, you, ALONE, Vector2(580, 230))
	Input.action_press(Keybinds.USE)
	await t.seconds(0.25)
	t.expect_near(door.angle(), 0.0, 0.01, "the door does not move while E is held")
	Input.action_release(Keybinds.USE)
	t.check(await _reaches(t, door, FULL), "E opens a shut door fully")
	t.expect_near(door.angle(), FULL, 0.1, "the door is open 90 degrees")
	await _tap(t)
	t.check(await _reaches(t, door, 0.0), "E again shuts it")
	door.turn_by(AJAR, null)
	await _reaches(t, door, AJAR)
	await _tap(t)
	t.check(await _reaches(t, door, FULL), "E swings an ajar door fully open")
	await _tap(t)
	t.check(await _reaches(t, door, 0.0), "and shuts it again")


## Both in reach, the door the nearer: E works the door and the car stays.
func _door_nearer(t: TestContext, you: Node, door: Node) -> void:
	door.open_fully(null)
	await _reaches(t, door, FULL)
	await _place(t, you, BY_THE_DOOR, OPEN_LEAF)
	t.check(you.use.doors.door_in_reach() == door, "the door is in reach beside the car")
	await _tap(t)
	t.check(await _reaches(t, door, 0.0), "nearer the door, E works it (it shuts)")
	await t.seconds(0.5)
	t.check(not you.use.is_busy(), "and does not board the car")


## The car's handle the nearer: E boards, the open door stays as it is (false: ends the test).
func _vehicle_nearer(t: TestContext, you: Node, door: Node) -> bool:
	door.open_fully(null)
	await _reaches(t, door, FULL)
	await _place(t, you, BY_THE_CAR, Vector2(590, 100))
	t.check(you.use.doors.door_in_reach() == door, "the door is in reach beside the car's door too")
	await _tap(t)
	if not t.require(
			await t.until(func(): return you.use.is_in_vehicle(), 6.0),
			"nearer the car's door, E gets in",
	):
		return false
	t.expect_near(door.angle(), FULL, 0.1, "and the open door is left open")
	return true


## Seated, a door in reach ahead: E gets out and leaves the door as it is.
func _seated_beside_a_door(t: TestContext, you: Node, east: Node) -> void:
	CharacterDoorConfig.reach = SEATED_REACH
	await t.seconds(0.5)
	t.check(you.use.doors.door_in_reach() == east, "a door is in reach of the seat")
	await _tap(t)
	t.check(
		await t.until(func(): return you.use.vehicle() == null, 8.0),
		"in a vehicle, E gets out",
	)
	t.expect_near(east.angle(), FULL, 0.1, "and the open door is left open")


## Whether the door's leaf comes to `angle` degrees within the swing's time and a margin.
func _reaches(t: TestContext, door: Node, angle: float) -> bool:
	return await t.until(func(): return absf(door.angle() - angle) <= 0.1, 2.0)


## Stand the player at `spot` and aim at the world point `toward`: the pointer is injected on the
## screen point that world point is at, again each frame, until the aim has held on it with the
## camera settled (the test camera is still easing toward its framing and carries the point).
func _place(t: TestContext, you: Node, spot: Vector2, toward: Vector2) -> void:
	you.global_position = spot
	await PlayerPointer.aim(t, you, toward)


## Tap E: press for a few frames, then release.
func _tap(t: TestContext) -> void:
	Input.action_press(Keybinds.USE)
	await t.frames(2)
	Input.action_release(Keybinds.USE)
	await t.frames(1)
