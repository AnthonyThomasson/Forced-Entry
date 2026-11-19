extends GameTest
## A sliding piece hands its momentum to the character it strikes (a kinematic body the solver does
## not move), and does it without reading Jolt's contact events (#194 furn3d review): they are
## collected on worker threads and arrive in a different count and order run to run, so a
## character's velocity differed in the last bits and a recorded fight missed. The piece carries no
## contact monitor; a deterministic shape query of the moving piece against the characters, in a
## fixed order, finds the one it has struck, and the hand-over is made once per touch.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const SOFA_AT := Vector2(150, 200)
const PUPPET_AT := Vector2(290, 200)
const SHOVE := Vector2(80_000.0, 0.0)


func describe() -> Dictionary:
	return {
		"name": "A sliding sofa shoves the character it strikes, with no contact events read",
		"description": "A sofa shoved along +x slides into a puppet: the puppet is handed momentum "
			+ "and moves on along +x, and the sofa has no contact monitor.",
		"tags": ["furniture", "3d", "knockback", "determinism"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 400))
	s.object(&"sofa", "sofa", SOFA_AT)
	s.actor(&"puppet", &"puppet", PUPPET_AT, { "max_health": 1_000_000.0 })
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	var sofa := t.object(&"sofa")
	var puppet := t.actor(&"puppet")
	t.check(not Probe.body(sofa).contact_monitor, "the sofa's 3D body reads no contact events")
	Knockback.push(sofa, SHOVE)
	await t.seconds(0.2)
	var moved: float = puppet.global_position.x - PUPPET_AT.x
	await t.seconds(1.5)
	var later: float = puppet.global_position.x - PUPPET_AT.x
	t.check(moved > 8.0, "the puppet was struck and is moving on along +x (%.1f px)" % moved)
	t.check(later >= moved, "and was not pulled back (%.1f px later)" % later)
	t.check(
		absf(puppet.global_position.y - PUPPET_AT.y) < 6.0,
		"straight along the shove (%.1f px off)" % (puppet.global_position.y - PUPPET_AT.y),
	)
