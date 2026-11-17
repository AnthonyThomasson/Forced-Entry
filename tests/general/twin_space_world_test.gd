extends GameTest
## The twin space (`TwinSpace`, interface 29, `docs/adr/0014-twin-staging-and-plan-space.md`): a
## test world (a walled arena, a sofa, a standing character) is staged with a 3D twin of every solid
## body in the 3D physics space the engine's Jolt runs, headless as it is here. Each twin is found
## by its 2D body (`twin_of`) and a ray into the space finds its 2D body back (`owner_of`); a body
## that never moves is written once (a still world writes nothing a frame); a body that is freed
## frees its twin and a ray then passes where it stood.

const Probe := preload("res://tests/_general/twin_probe.gd")
const SOFA_AT := Vector2(300, 250)


func describe() -> Dictionary:
	return {
		"name": "A test world has a twin space: a twin per solid body, freed with it",
		"description": "The stage builds the twin space under Jolt; every wall, floor, solid piece "
			+ "and character has a twin that a ray into the space maps back to its body; a still "
			+ "world writes no twin; freeing a body frees its twin.",
		"tags": ["twins", "3d", "heights"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.object(&"sofa", "sofa", SOFA_AT)
	s.actor(&"guard", &"puppet", Vector2(550, 250))


func run(t: TestContext) -> void:
	t.expect_eq(
		ProjectSettings.get_setting("physics/3d/physics_engine"),
		"Jolt Physics",
		"the 3D engine is Jolt (D6)",
	)
	await t.frames(3)
	var twins := Probe.twins(t)
	if not t.require(twins != null, "the stage built a twin space"):
		return
	var bodies := _bodies(t)
	t.require(bodies.size() >= 4, "premise: walls, floor, sofa and guard are in the world")
	for body in bodies:
		var twin := twins.twin_of(body)
		t.check(twin != null, "%s has a twin" % body.name)
		t.check(TwinSpace.owner_of(twin) == body, "%s's twin names it" % body.name)
	t.expect_eq(twins.count, bodies.size(), "no twin without a body")
	var sofa := t.object(&"sofa")
	var hit := Probe.down(t, SOFA_AT)
	t.check(hit.get("owner") == sofa, "a ray dropped on the sofa finds it: %s" % hit.get("owner"))
	t.check(
		TwinSpace.space_of(sofa) == twins.space(),
		"a sim node finds the twin space through its viewport",
	)
	await _still(t, twins)
	await _late_floor(t, twins)
	await _freed(t, twins, sofa)


## Every solid body the world holds: walls, floors, solid pieces and characters.
func _bodies(t: TestContext) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for node in t.world.find_children("*", "PhysicsBody2D", true, false):
		var body := node as Node2D
		if body.get("wall_thickness") != null or body.is_in_group(&"characters"):
			out.append(body)
		elif body.get("solid") == true and body.get("shape_type") != null:
			out.append(body)
	for floor_node in t.world.get_tree().get_nodes_in_group(&"floors"):
		if t.world.is_ancestor_of(floor_node):
			out.append(floor_node as Node2D)
	return out


## Nothing moves: after the sofa settles no twin is written, a frame after a frame.
func _still(t: TestContext, twins: TwinSpace) -> void:
	await t.seconds(2.0)
	var writes := 0
	for i in 20:
		await t.frames(1)
		writes += twins.written
	t.expect_eq(writes, 0, "a still world writes no twin")
	t.check(twins.followed >= 1, "the standing guard is read each frame all the same")


## A floor laid after the stage is twinned on the next frame, and a plain node beside it is not.
func _late_floor(t: TestContext, twins: TwinSpace) -> void:
	var before := twins.count
	var plain := Node2D.new()
	t.world.add_child(plain)
	var rect := Rect2(1000, 0, 300, 120)
	var laid := FloorFactory.spawn(rect, { "art": "floor" }, "Late floor", t.world)
	await t.frames(3)
	t.expect_eq(twins.count, before + 1, "one twin more: the floor's, not the plain node's")
	t.check(twins.twin_of(laid) != null, "the late floor has a twin")
	t.check(twins.twin_of(plain) == null, "a plain node has none")
	t.check(
		Probe.down(t, rect.get_center()).get("owner") == laid,
		"a ray over the late floor lands on it",
	)
	plain.queue_free()


## The sofa is freed, asleep and so off the follow list: its twin goes, and a ray over where it
## stood lands on the floor.
func _freed(t: TestContext, twins: TwinSpace, sofa: Node2D) -> void:
	t.require((sofa as RigidBody2D).sleeping, "premise: the sofa is asleep when it is freed")
	var twin := twins.twin_of(sofa)
	var before := twins.count
	sofa.queue_free()
	await t.frames(3)
	t.check(not is_instance_valid(twin), "the twin of a freed body is freed")
	t.expect_eq(twins.count, before - 1, "one twin fewer")
	var hit := Probe.down(t, SOFA_AT)
	t.check(
		hit.get("owner") != null and (hit["owner"] as Node).is_in_group(&"floors"),
		"a ray over where the sofa stood lands on the floor",
	)
