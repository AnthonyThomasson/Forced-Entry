extends GameTest
## D18 / DR11 (#194): Four ajar hollow doors kicked from their closed side with a desk 25
## px past each wall line on the landing side: each leaf leans on the desk or leaves the doorway
## clear, and the desk is not bulldozed.

const AjarFall := preload("res://tests/_objects/ajar_fall_probe.gd")
const ANGLES := [20.0, 45.0, 70.0, 85.0]
const HINGES := [-1.0, 1.0, 1.0, -1.0]
const INTOS := [Vector2.UP, Vector2.DOWN, Vector2.UP, Vector2.DOWN]


func describe() -> Dictionary:
	return {
		"name": "An ajar door kicked from its closed side leans on a desk or leaves it clear",
		"description": "Four ajar hollow doors kicked from their closed side with a desk "
			+ "25 px past each wall line on the landing side: each leaf leans on "
			+ "the desk or leaves the doorway clear, and the desk is not "
			+ "bulldozed.",
		"tags": ["door", "objects"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.layout(AjarFall.GunRange._rooms(), AjarFall.doorways(ANGLES, HINGES, INTOS, "hollow"))
	s.actor(&"you", &"player", Vector2(240, 320), { "start_slot": 6 })
	AjarFall.in_the_way(s, &"desk", HINGES, INTOS, false)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	await AjarFall.fell_into_the_way(t, ANGLES, INTOS, &"desk", false)
