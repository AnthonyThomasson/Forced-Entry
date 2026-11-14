extends GameTest
## An NPC that is moved in the tree (taken out and put back under the same parent) is still in its
## match with its decision half built: it keeps its place in the decision pool, and the NPC behind
## it still waits for it. Leaving the tree is not leaving the match (`GoalController` releases its
## job when it is freed, not when it exits the tree). Two invaders see a trespasser at once with
## every piece priced and one unit a frame; the first claims and is mid-build when it is moved.

const Probe := preload("res://tests/_ai/pool_release_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A reparented NPC keeps its place in the decision pool",
		"description": "The elder of two invaders is taken out of the tree and put back mid-build: "
			+ "the younger does not claim on the very next frame, it still waits behind it.",
		"tags": ["ai", "decision", "scripted"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	Probe.configure(s)


func run(t: TestContext) -> void:
	var elder := t.actor(&"inv0")
	var parent := elder.get_parent()
	var move := func() -> void:
		parent.remove_child(elder)
		parent.add_child(elder)
	await Probe.run(
		t, move, func(): return elder.is_inside_tree() and not elder.is_dead, false
	)
