extends GameTest
## An NPC that dies with its decision half built never advances that decision again, and the
## decision pool does not wait for it: the next NPC claims on the very next frame, not once the
## pool's roster forgets the dead one (`DecisionJob.release`, called by the controller on the
## character's `died`: a dead body no longer asks its controller to think). Two invaders see a
## trespasser at once with every piece priced and one unit a frame; the first claims and is
## mid-build when it is killed.

const Probe := preload("res://tests/_ai/pool_release_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A dead NPC's decision frees the pool at once",
		"description": "The elder of two invaders is killed mid-build: the younger claims its "
			+ "decision on the very next frame.",
		"tags": ["ai", "decision", "scripted"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	Probe.configure(s)


func run(t: TestContext) -> void:
	await Probe.run(t, func(): t.actor(&"inv0").take_damage(1_000_000.0))
