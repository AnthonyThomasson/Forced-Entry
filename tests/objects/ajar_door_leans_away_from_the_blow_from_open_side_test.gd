extends GameTest
## D18 / DR11 (#194 ajarfall): Four ajar hollow doors (20 and 85 degrees among them) kicked from
## their open side: the top of each leaf lies toward the blow's side of its face.

const AjarFall := preload("res://tests/_objects/ajar_fall_probe.gd")
const ANGLES := [20.0, 45.0, 70.0, 85.0]
const HINGES := [-1.0, 1.0, 1.0, -1.0]
const INTOS := [Vector2.UP, Vector2.DOWN, Vector2.UP, Vector2.DOWN]


func describe() -> Dictionary:
	return {
		"name": "An ajar door kicked from its open side leans away from the kicker",
		"description": "Four ajar hollow doors (20 and 85 degrees among them) kicked from "
			+ "their open side: the top of each leaf lies toward the blow's side "
			+ "of its face.",
		"tags": ["door", "objects"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.layout(AjarFall.GunRange._rooms(), AjarFall.doorways(ANGLES, HINGES, INTOS, "hollow"))
	s.actor(&"you", &"player", Vector2(240, 320), { "start_slot": 6 })


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	await AjarFall.fell_and_lean(t, ANGLES, INTOS, true)
