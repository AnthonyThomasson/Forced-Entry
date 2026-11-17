extends GameTest
## Space measures every candidate from the mouse the same way (ticket #193, decision G7): the gap to
## the nearest point of what it would act on, never to an origin. A large piece with the mouse on it
## beats a door whose leaf is nearer than the piece's centre; the mouse on the door beats the piece.
##
## A wall at y = 170 has a doorway at x = 580 whose hollow door `d` is hinged on its west jamb
## (560, 170) and swings down into the room (shut, its leaf runs along the wall to x = 612). A bed
## (120 x 180: x 620 to 740, y 185 to 365, its centre at (680, 275)) lies east of the player, who
## stands at (600, 200) with the leaf 29 px north and the bed's edge 20 px east.

const PlayerPointer := preload("res://tests/_character/player_pointer_probe.gd")
const STANDING := Vector2(600, 200)
## On the bed's near corner: its centre is 89 px away, the shut leaf's end 37 px.
const ON_THE_BED := Vector2(640, 195)
## On the leaf near its hinge: the bed's edge is 47 px away.
const ON_THE_LEAF := Vector2(575, 172)
const FULL := 90.0


func describe() -> Dictionary:
	return {
		"name": "Space acts on the large piece the mouse is on, not a nearer-centred door",
		"description": "A bed and a shut door in reach: the mouse on the bed corner makes Space "
			+ "use the bed though the door's leaf is nearer than the bed's centre; the mouse on "
			+ "the leaf opens the door at the release.",
		"tags": ["interaction", "door", "player", "input", "keybinds"],
		"timeout": 20.0,
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
	s.object(&"bed", "bed", Vector2(680, 275))
	s.actor(&"you", &"player", STANDING)


func run(t: TestContext) -> void:
	var you := t.actor(&"you")
	var door := t.object(&"d")
	if not t.require(door != null and t.object(&"bed") != null, "the door and the bed stand"):
		return
	await _aim(t, you, ON_THE_BED)
	t.check(
		you.use.doors.door_in_reach() == door and not you.use.interactions_in_reach().is_empty(),
		"premise: the door and the bed are both in reach",
	)
	await _tap(t)
	t.check(you.use.is_busy(), "the mouse on the bed: Space uses the bed")
	t.expect_near(door.angle(), 0.0, 0.01, "and the door stays shut")
	await _tap(t)
	t.check(await t.until(func(): return not you.use.is_busy(), 1.0), "Space again ends it")

	await _aim(t, you, ON_THE_LEAF)
	await _tap(t)
	t.check(
		await t.until(func(): return absf(door.angle() - FULL) <= 0.1, 2.0),
		"the mouse on the leaf: the release opens the door",
	)
	t.check(not you.use.is_busy(), "and the bed is left alone")


func _aim(t: TestContext, you: Node, toward: Vector2) -> void:
	you.global_position = STANDING
	await PlayerPointer.aim(t, you, toward)


## Tap Space: press for a few frames, then release.
func _tap(t: TestContext) -> void:
	Input.action_press(Keybinds.INTERACT)
	await t.frames(2)
	Input.action_release(Keybinds.INTERACT)
	await t.frames(1)
