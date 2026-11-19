extends GameTest
## A tipped piece is not sat on (#194 furn3d, D14): a chair knocked onto its side offers no `sit`
## (the interaction is refused and the character stays free), while one that stands is sat on.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const AT := Vector2(258, 200)


func describe() -> Dictionary:
	return {
		"name": "Sit on a tipped chair is refused",
		"description": "A chair is knocked onto its side: interact_with(chair, \"sit\") is "
			+ "refused and the character stays free; the chair beside it that stands is sat on.",
		"tags": ["interaction", "sit", "chair", "tipping", "3d"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.actor(&"sitter", &"puppet", Vector2(220, 200))
	s.object(&"chair", "chair", AT)
	s.object(&"upright", "chair", Vector2(220, 280))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	var sitter := t.actor(&"sitter")
	var p := t.puppet(&"sitter")
	var chair := t.object(&"chair")
	# knock it over, away from the sitter
	Knockback.push(chair, Vector2(3000.0, 0.0), Vector2.ZERO, 30.0)
	await t.seconds(0.2)
	await Probe.settle(t, chair, 10.0)
	var lean: float = Probe.lean(chair)
	if not t.require(lean > 60.0, "premise: the chair lies on its side (%.0f degrees)" % lean):
		return
	# the sitter walks to it (it lies where it fell)
	var beside: Vector2 = chair.global_position - Vector2(30.0, 0.0)
	sitter.global_position = beside
	p.aim_at(chair)
	await t.seconds(0.3)
	p.interact(chair, "sit")
	await t.seconds(0.3)
	t.check(not sitter.use.is_busy(), "sitting on the tipped chair does not start")
	t.check(not p.failed_interactions.is_empty(), "the interaction was refused")
	# the chair that stands is sat on, from the same spot
	var upright := t.object(&"upright")
	sitter.global_position = upright.global_position - Vector2(30.0, 0.0)
	p.aim_at(upright)
	await t.seconds(0.3)
	p.interact(upright, "sit")
	t.check(
		await t.until(sitter.use.is_busy, 1.0), "while the chair that stands is sat on",
	)
