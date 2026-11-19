extends GameTest
## A character that gets up from a chair keeps its collision exception with it until its body stands
## clear of the chair's 3D body (#194 chars3d-b): `CharacterUse` asks the twin space whether the
## body (its circle plus a margin) still overlaps, not the 2D footprint, so with the footprint's own
## shapes off the exception is still held while the character stands on the chair, and dropped once
## it has walked off.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const CHAIR_AT := Vector2(300, 200)


func describe() -> Dictionary:
	return {
		"name": "Getting up keeps the exception until the body clears the chair's 3D body",
		"description": "A character sits where it overlaps the chair, gets up: the exception holds "
			+ "while it overlaps the 3D body, with the 2D footprint's shapes off, and is dropped "
			+ "once it stands clear.",
		"tags": ["character", "interaction", "sit", "3d"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.object(&"chair", "chair", CHAIR_AT)
	s.actor(&"you", &"puppet", CHAIR_AT + Vector2(0.0, 4.0))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	var chair := t.object(&"chair")
	await Probe.settle(t, chair, 5.0)
	for shape in chair.find_children("*", "CollisionShape2D", true, false):
		(shape as CollisionShape2D).disabled = true
	var you := t.actor(&"you")
	you.global_position = chair.global_position + Vector2(0.0, 4.0)
	await t.frames(2)
	t.puppet(&"you").interact(chair, "sit")
	await t.seconds(0.3)
	t.require(you.use.is_busy(), "premise: the character sits")
	t.puppet(&"you").end_interaction()
	await t.until(func() -> bool: return not you.use.is_busy(), 3.0)
	await t.seconds(0.5)
	var walker := TwinSpace.walker_of(you) as PhysicsBody3D
	var twin := TwinSpace.twin_for(chair) as PhysicsBody3D
	t.check(
		walker.get_collision_exceptions().has(twin),
		"standing on the chair's 3D body, the exception is still held",
	)
	you.global_position = chair.global_position + Vector2(0.0, 80.0)
	await t.seconds(0.5)
	t.check(
		not walker.get_collision_exceptions().has(twin),
		"clear of it, the exception is dropped",
	)
