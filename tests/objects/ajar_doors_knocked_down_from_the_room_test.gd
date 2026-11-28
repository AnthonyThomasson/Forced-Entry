extends GameTest
## D18 / DR11 (#194): once a door is down its doorway is clear, whichever way an ajar leaf
## stood. Four solid doors in the gun range's doorways, ajar from 20 to 85 degrees, hinged on
## either jamb and swinging out onto the range or into their rooms, are kicked down along
## `Vector2.DOWN` (from the room): each leaf settles clear of its frame (it may lean on a wall
## beside).

const AjarFall := preload("res://tests/_objects/ajar_fall_probe.gd")
const ANGLES := [20.0, 45.0, 70.0, 85.0]
const HINGES := [-1.0, 1.0, 1.0, -1.0]
const INTOS := [Vector2.UP, Vector2.DOWN, Vector2.UP, Vector2.DOWN]


func describe() -> Dictionary:
	return {
		"name": "An ajar door kicked down from the room leaves its doorway clear",
		"description": "Solid doors ajar at four angles, either hinge, either swing: kicked down "
			+ "they settle clear of their doorways.",
		"tags": ["door", "objects"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	var gun_range := AjarFall.GunRange
	s.layout(gun_range._rooms(), AjarFall.doorways(ANGLES, HINGES, INTOS))
	s.actor(&"you", &"player", Vector2(240, 320), { "start_slot": 6 })


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	await AjarFall.fell_all(t, ANGLES, Vector2.DOWN, "room")
