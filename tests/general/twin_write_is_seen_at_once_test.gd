extends GameTest
## A twin is written and read in the same frame (`TwinSpace`, interface 29): a ray cast right after
## `update()` has moved a twin finds it at its new pose, not at the pose before (a `Node3D` pushes
## its transform to Jolt only at the frame's end unless it is pushed at the write: `_write` pushes
## it). A piece teleported by a script and followed by `update()` is hit by a ray in that same
## frame at its new place, and the place it left is clear.

const Probe := preload("res://tests/_general/twin_probe.gd")
const Piece := preload("res://tests/_objects/piece_probe.gd")
const SOFA_AT := Vector2(300, 250)
const MOVED_TO := Vector2(600, 250)


func describe() -> Dictionary:
	return {
		"name": "A twin that has just been written is where a ray finds it in the same frame",
		"description": "A sofa teleported by a script and followed by the twin space's update is "
			+ "hit by a ray at once at its new place and is no longer where it was.",
		"tags": ["twins", "3d"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.object(&"sofa", "sofa", SOFA_AT)


func run(t: TestContext) -> void:
	await t.frames(3)
	var sofa := t.object(&"sofa") as Node2D
	t.require(Probe.down(t, SOFA_AT).get("owner") == sofa, "premise: a ray on the sofa names it")
	Piece.body(sofa).sleeping = false
	await t.frames(1)
	sofa.global_position = MOVED_TO
	t.world.twin_space().update()
	var there := Probe.down(t, MOVED_TO, PhysicsLayers.TWIN_WORLD)
	t.check(there.get("owner") == sofa, "a ray in the frame of the write finds the sofa's twin")
	var left := Probe.down(t, SOFA_AT, PhysicsLayers.TWIN_WORLD)
	t.check(left.get("owner") != sofa, "and not where the sofa was")
