extends GameTest
## A character put onto or under a piece it is interacting with does not shove it (#194): the
## interaction's collision exception between the two bodies holds for their 3D bodies too, so a bed
## that someone lies on, or hides under, stays where it stands (its free 3D body is not pushed out
## from under a body that is snapped onto its centre), and the exception is dropped again once the
## character is up and clear.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const BED_AT := Vector2(300, 200)


func describe() -> Dictionary:
	return {
		"name": "Lying on or hiding under a bed leaves it where it stands",
		"description": "A character lies on a bed, then gets up and hides under it: the bed does "
			+ "not move either time, and a push on it afterwards moves it as before.",
		"tags": ["interaction", "lie", "hide", "bed", "3d"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.object(&"bed", "bed", BED_AT)
	s.actor(&"sleeper", &"puppet", BED_AT + Vector2(0.0, 70.0))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	var bed := t.object(&"bed")
	await Probe.settle(t, bed, 5.0)
	var rest: Vector2 = bed.global_position
	var sleeper := t.actor(&"sleeper")
	var puppet := t.puppet(&"sleeper")
	for action: String in ["lie", "hide"]:
		sleeper.global_position = bed.global_position + Vector2(0.0, 40.0)
		await t.frames(2)
		puppet.interact(bed, action)
		await t.seconds(1.0)
		t.check(sleeper.use.is_busy(), "%s: the character is on the bed's interaction" % action)
		t.expect_near(
			bed.global_position.distance_to(rest), 0.0, 1.0,
			"%s: the bed stayed where it was (%.1f px off)" % [
				action,
				bed.global_position.distance_to(rest),
			],
		)
		puppet.end_interaction()
		await t.until(func() -> bool: return not sleeper.use.is_busy(), 3.0)
		await t.seconds(0.5)
	# the exception is gone: the bed is a body to the character again, and a shove moves it
	sleeper.global_position = bed.global_position + Vector2(0.0, 120.0)
	await t.seconds(0.5)
	Knockback.push(bed, Vector2(0.0, 6000.0) * bed.get_mass())
	await t.seconds(0.5)
	t.check(
		bed.global_position.distance_to(rest) > 5.0,
		"after it, a shove moves the bed (%.1f px)" % bed.global_position.distance_to(rest),
	)
