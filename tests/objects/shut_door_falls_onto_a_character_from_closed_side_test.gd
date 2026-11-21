extends GameTest
## D18 / DR11 (#194 ajarfall): Four shut hollow doors knocked down from their closed side with a
## character 14 px past each wall line on the landing side: each leaf lies down clear of its doorway
## and goes to sleep, and the character it fell on is shoved clear once, not pushed on while it
## rests (a leaf that fell on a character used to lean on them for ever, pushing them 7 px/s).

const AjarFall := preload("res://tests/_objects/ajar_fall_probe.gd")
const ANGLES := [0.0, 0.0, 0.0, 0.0]
const HINGES := [-1.0, 1.0, 1.0, -1.0]
const INTOS := [Vector2.UP, Vector2.DOWN, Vector2.UP, Vector2.DOWN]


func describe() -> Dictionary:
	return {
		"name": "A shut door downed from its closed side lies flat on a character",
		"description": "Four shut hollow doors kicked from their closed side with a character "
			+ "14 px past each wall line: each leaf lies flat and clear, is asleep within 4 s, "
			+ "and pushes the character no further once it rests.",
		"tags": ["door", "objects"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.layout(AjarFall.GunRange._rooms(), AjarFall.doorways(ANGLES, HINGES, INTOS, "hollow"))
	s.actor(&"you", &"player", Vector2(240, 320), { "start_slot": 6 })
	AjarFall.in_the_way(s, &"puppet", HINGES, INTOS, false)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	await AjarFall.fell_into_the_way(t, ANGLES, INTOS, &"puppet", false)
