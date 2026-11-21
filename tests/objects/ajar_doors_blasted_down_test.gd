extends GameTest
## D18 / DR11 (#194 flatdoor): a blast that fells an ajar door leaves its doorway clear, whichever
## way the leaf stood and whichever side of the wall the frag went off: four hollow doors in the gun
## range's doorways, ajar from 20 to 85 degrees, either hinge, swinging out or into their rooms,
## each blown down in turn by a frag, from the range's side or the room's.

const AjarFall := preload("res://tests/_objects/ajar_fall_probe.gd")
const ANGLES := [20.0, 45.0, 70.0, 85.0]
const HINGES := [-1.0, 1.0, 1.0, -1.0]
const INTOS := [Vector2.UP, Vector2.DOWN, Vector2.UP, Vector2.DOWN]
## The side of the wall each frag goes off on: the thrown way is away from it.
const SIDES := [Vector2.DOWN, Vector2.UP, Vector2.UP, Vector2.DOWN]


func describe() -> Dictionary:
	return {
		"name": "An ajar door blasted down leaves its doorway clear",
		"description": "Hollow doors ajar at four angles, either hinge, either swing, blown down "
			+ "by a frag from either side of their wall: they settle clear of their doorways.",
		"tags": ["door", "objects", "blast"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.layout(AjarFall.GunRange._rooms(), AjarFall.doorways(ANGLES, HINGES, INTOS, "hollow"))
	s.actor(&"you", &"player", Vector2(240, 320), { "start_slot": 6 })


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	await AjarFall.blast_all(t, ANGLES, SIDES)
