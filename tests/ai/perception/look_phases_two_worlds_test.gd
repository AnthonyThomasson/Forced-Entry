extends GameTest
## The phases NPCs look for the house on (`LookPhases`) are handed out in turn within each world
## root. Two roots asking alternately in one process (two worlds of one test run, a world replaced
## while another still ticks) each keep an even spread of phases over the cycle: the one's
## next phase is not reset by the other's ask.

const LookPhases := preload("res://scenes/ai/perception/look_phases.gd")
const CYCLE := 6
## NPCs per root: two full cycles.
const PER_ROOT := 12


func describe() -> Dictionary:
	return {
		"name": "Look phases are spread evenly in each of two worlds",
		"description": "Two world roots hand out look phases alternately; each root's NPCs fill "
			+ "every phase of the cycle equally often.",
		"tags": ["ai", "perception"],
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	var roots: Array[Node] = []
	var walkers: Array[Walker] = []
	for i in 2:
		var root := Node2D.new()
		t.world.add_child(root)
		var walker := Walker.new()
		walker.root = root
		root.add_child(walker)
		roots.append(root)
		walkers.append(walker)
	var seen: Array = [[], []]
	for i in PER_ROOT:
		for r in 2:
			seen[r].append(LookPhases.next(walkers[r], CYCLE))
	for r in 2:
		var counts := {}
		for phase in seen[r]:
			counts[phase] = int(counts.get(phase, 0)) + 1
		t.expect_eq(counts.size(), CYCLE, "root %d uses every phase of the cycle" % r)
		for phase in counts:
			t.expect_eq(
				counts[phase],
				2,
				"root %d: phase %d is handed out twice" % [r, phase],
			)


## A stand-in for a character: it answers which world root it belongs to.
class Walker:
	extends Node
	var root: Node

	func world_root() -> Node:
		return root
