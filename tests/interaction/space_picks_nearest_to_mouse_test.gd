extends GameTest
## Use merged into Space (ticket #193, rule 7, decision G7): Space acts on the reachable thing
## nearest the mouse, whether a chair, a house door or a vehicle's door. A door keeps its
## act-on-release (a tap toggles it at the let-go) and is only a candidate while ahead of the
## character; a chair and a vehicle act on the press. What decides is the mouse, not the body: the
## things below are placed so the one nearest the body is not the one nearest the mouse.
##
## A south room holds a car (220 x 110 at (620, 300): front-left handle (600, 245)) under a wall,
## y = 170, with a doorway at x = 580 whose hollow door `d` is hinged on its west jamb (560, 170)
## and swings down into the room (shut, its leaf runs along the wall to x = 612; open, it stands 3
## px east of the hinge, from 3.5 to 42.5 px below the wall). A chair sits at (650, 200).

const PlayerPointer := preload("res://tests/_character/player_pointer_probe.gd")
## Under the doorway, all three in reach: the shut leaf 34 px north, the chair's edge 40 px east
## (its real 28 px square, a 3D body: the reach is asked of the twin space), the car's front-left
## handle 40 px south.
const UNDER_THE_DOOR := Vector2(596, 205)
const AT_THE_CHAIR := Vector2(650, 200)
## On the shut leaf, near its hinge.
const AT_THE_LEAF := Vector2(575, 172)
## Beside the front-left handle (18 px), the open leaf 43 px away (within the 48 px door reach).
const BY_THE_CAR := Vector2(603, 227)
const AT_THE_OPEN_LEAF := Vector2(563, 195)
## Just off the handle (11 px), 39 px from the open leaf, which a player facing it has still ahead.
const AT_THE_HANDLE := Vector2(595, 235)
const FULL := 90.0


func describe() -> Dictionary:
	return {
		"name": "Space acts on the chair, door or vehicle nearest the mouse",
		"description": "Chair, house door and car door in reach together: Space sits, toggles the "
			+ "door at the release, or boards, by what the mouse is nearest, even when another is "
			+ "nearer the body.",
		"tags": ["interaction", "door", "vehicle", "player", "input", "keybinds"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "north", "type": "living_room", "rect": Rect2(0, 0, 800, 170) },
		{ "key": "south", "type": "bedroom", "rect": Rect2(0, 170, 760, 430) },
	], [{
		"pos": Vector2(580, 170), "width": 52.0,
		"door": {
			"name": "d", "material": "hollow", "style": "flush",
			"hinge": Vector2(560, 170), "swing_into": Vector2.DOWN,
		},
	}])
	s.von_down()
	s.vehicle(&"car", &"car", Vector2(620, 300))
	s.object(&"chair", "chair", AT_THE_CHAIR)
	s.actor(&"you", &"player", UNDER_THE_DOOR)


func run(t: TestContext) -> void:
	var you := t.actor(&"you")
	var door := t.object(&"d")
	if not t.require(door != null and t.object(&"chair") != null, "the door and the chair stand"):
		return
	await _place(t, you, UNDER_THE_DOOR, AT_THE_CHAIR)
	t.check(
		you.use.interactions_in_reach().size() == 1 and you.use.doors.door_in_reach() == door,
		"premise: the chair and the shut door are both in reach",
	)
	await _chair_nearest_the_mouse(t, you, door)
	await _door_nearest_the_mouse(t, you, door)
	# The chair stands where the car's front door swings; the car scenario goes without it.
	t.object(&"chair").free()
	await t.frames(2)
	await _vehicle_or_door_by_the_mouse(t, you, door)


## The mouse on the chair: Space sits at the press, the door and the car untouched; Space again
## stands up.
func _chair_nearest_the_mouse(t: TestContext, you: Node, door: Node) -> void:
	await _place(t, you, UNDER_THE_DOOR, AT_THE_CHAIR)
	Input.action_press(Keybinds.INTERACT)
	await t.frames(2)
	t.check(you.use.is_busy(), "Space sits on the chair at the press")
	Input.action_release(Keybinds.INTERACT)
	await t.seconds(0.3)
	t.check(you.use.is_busy() and you.use.vehicle() == null, "and not in the car")
	t.expect_near(door.angle(), 0.0, 0.01, "the door stays shut")
	await _tap(t)
	t.check(await t.until(func(): return not you.use.is_busy(), 1.0), "Space again stands up")


## The mouse on the shut leaf: nothing acts while Space is held; the release opens the door, and no
## chair is sat on nor car boarded.
func _door_nearest_the_mouse(t: TestContext, you: Node, door: Node) -> void:
	await _place(t, you, UNDER_THE_DOOR, AT_THE_LEAF)
	Input.action_press(Keybinds.INTERACT)
	await t.seconds(0.25)
	t.expect_near(door.angle(), 0.0, 0.01, "the door waits for the release")
	t.check(not you.use.is_busy(), "nothing was sat on or boarded at the press")
	Input.action_release(Keybinds.INTERACT)
	t.check(await _reaches(t, door, FULL), "the release opens the door")
	await t.seconds(0.4)
	t.check(not you.use.is_busy(), "and the chair and the car stay alone")


## With the door open and the car's handle the nearer to the body: the mouse on the leaf shuts the
## door and boards nothing; the mouse on the handle boards, the open door left open.
func _vehicle_or_door_by_the_mouse(t: TestContext, you: Node, door: Node) -> void:
	await _place(t, you, BY_THE_CAR, AT_THE_OPEN_LEAF)
	t.check(you.use.doors.door_in_reach() == door, "premise: the open leaf is in reach")
	await _tap(t)
	t.check(await _reaches(t, door, 0.0), "the mouse on the leaf: the door shuts")
	await t.seconds(0.4)
	t.check(not you.use.is_busy(), "and the car is not boarded")
	door.open_fully(null)
	await _reaches(t, door, FULL)
	await _place(t, you, BY_THE_CAR, AT_THE_HANDLE)
	t.check(you.use.doors.door_in_reach() == door, "premise: the open leaf is still in reach")
	await _tap(t)
	t.check(
		await t.until(func(): return you.use.is_in_vehicle(), 6.0),
		"the mouse on the car's handle: Space boards",
	)
	t.expect_near(door.angle(), FULL, 0.1, "and the open door is left open")


func _reaches(t: TestContext, door: Node, angle: float) -> bool:
	return await t.until(func(): return absf(door.angle() - angle) <= 0.1, 2.0)


## Stand the player at `spot` and aim at the world point `toward`.
func _place(t: TestContext, you: Node, spot: Vector2, toward: Vector2) -> void:
	you.global_position = spot
	await PlayerPointer.aim(t, you, toward)


## Tap Space: press for a few frames, then release.
func _tap(t: TestContext) -> void:
	Input.action_press(Keybinds.INTERACT)
	await t.frames(2)
	Input.action_release(Keybinds.INTERACT)
	await t.frames(1)
