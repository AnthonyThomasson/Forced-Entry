extends GameTest
## An NPC that leaves the tree with its decision half built (freed, despawned) never advances that
## decision again, and the decision pool does not wait for it: the next NPC claims on the very next
## frame (`GoalController._exit_tree` releases the job from the pool's roster). Two invaders see a
## trespasser at once with every piece priced and one unit a frame; the first claims and is
## mid-build when it is freed.

const Probe := preload("res://tests/_ai/pool_release_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A freed NPC's decision frees the pool at once",
		"description": "The elder of two invaders is freed mid-build: the younger claims its "
			+ "decision on the very next frame.",
		"tags": ["ai", "decision", "scripted"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	Probe.configure(s)


func run(t: TestContext) -> void:
	await Probe.run(t, func(): t.actor(&"inv0").free())
