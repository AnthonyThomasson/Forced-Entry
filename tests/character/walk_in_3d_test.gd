extends GameTest
## A character is a 3D body that walks in the twin space (#194, D13, interface 29): its
## `CharacterBody3D` is the truth of where it stands and its 2D body the footprint written from it.
## What the 3D space holds stops it, at the heights it stands in: a block that only the 3D space
## has (a wall of the twin world) stops a walker and the 2D body is found beside it; a handle with
## no twin does not stop it; a beam hung over a doorway at 40 to 60 px is walked
## under crouched (36 px tall) and strikes a standing body (74 px).

const START := Vector2(100, 150)
const STAND_WALL := Vector2(300, 150)
const BEAM_X := 300.0
## The body's radius (px): the circle it has always been.
const RADIUS := 14.0


func describe() -> Dictionary:
	return {
		"name": "A character walks as a 3D body, its 2D body the footprint",
		"description": "A block in the 3D space stops a walker (the 2D body ends beside it, "
			+ "written from the 3D one); a plan handle with no twin does not; a beam hung at "
			+ "40 to 60 px is walked under crouched and stops a standing body.",
		"tags": ["twins", "3d", "character", "movement", "leader"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.set_static(CharacterPostureConfig, &"change_time", 0.0)
	s.actor(&"walker", &"puppet", START)
	s.actor(&"ducker", &"puppet", START + Vector2(0, 150))


func run(t: TestContext) -> void:
	await t.frames(3)
	var body := t.actor(&"walker")
	var lead := TwinSpace.twin_for(body)
	if not t.require(lead is CharacterBody3D, "premise: the walker's twin is a CharacterBody3D"):
		return
	t.check(TwinSpace.walker_of(body) == lead, "TwinSpace.walker_of names it")
	await _blocked_in_3d(t, body, lead as CharacterBody3D)
	await _blocked_by_a_handle_only(t)
	await _beam(t)


## A 3D-only wall across the way: the walker stops against it, and its 2D body is written from the
## 3D one (the same plan point every frame).
func _blocked_in_3d(t: TestContext, body: Node2D, lead: CharacterBody3D) -> void:
	var wall := _block(t, Rect2(STAND_WALL.x, 100, 30, 100), 0.0, 90.0)
	t.puppet(&"walker").walk(Vector2.RIGHT)
	await t.seconds(2.0)
	t.check(
		body.global_position.x < STAND_WALL.x - RADIUS + 1.0,
		"the 3D wall stops the walker (x %.1f)" % body.global_position.x,
	)
	t.check(
		body.global_position.x > STAND_WALL.x - RADIUS - 8.0,
		"it came up against it (x %.1f)" % body.global_position.x,
	)
	var plan := PlanSpace.plan_of(lead.global_position)
	t.check(plan.distance_to(body.global_position) < 0.01, "the 2D body is where the 3D body is")
	t.expect_near(lead.global_position.y, 0.0, 0.01, "it stays on the floor")
	t.puppet(&"walker").walk(Vector2.ZERO)
	wall.queue_free()


## A plan handle with no twin (a bare `Node2D` of `TwinSpace.BODIES`) does not stop a walker: the
## 3D body is the truth, and a handle is only where it stands.
func _blocked_by_a_handle_only(t: TestContext) -> void:
	var rock := Node2D.new()
	rock.position = Vector2(500, 150)
	rock.add_to_group(TwinSpace.BODIES)
	t.world.add_child(rock)
	var body := t.actor(&"walker")
	t.puppet(&"walker").walk(Vector2.RIGHT)
	await t.until(func() -> bool: return body.global_position.x > 560.0, 4.0)
	t.check(
		body.global_position.x > 540.0,
		"a handle with no twin does not stop it (x %.1f)" % body.global_position.x,
	)
	t.puppet(&"walker").walk(Vector2.ZERO)
	rock.queue_free()


## A beam over the way, 40 to 60 px up: a crouched body walks under it, a standing one is stopped.
func _beam(t: TestContext) -> void:
	var beam := _block(t, Rect2(BEAM_X, 200, 30, 200), 40.0, 60.0)
	var ducker := t.actor(&"ducker")
	t.require(t.actor(&"ducker").movement.set_posture(&"crouch"), "premise: it can crouch")
	t.puppet(&"ducker").walk(Vector2.RIGHT)
	await t.until(func() -> bool: return ducker.global_position.x > BEAM_X + 60.0, 4.0)
	t.check(
		ducker.global_position.x > BEAM_X + 40.0,
		"a crouched body walks under a beam at 40 px (x %.1f)" % ducker.global_position.x,
	)
	var walker := t.actor(&"walker")
	walker.global_position = Vector2(START.x, 250)
	await t.frames(2)
	t.puppet(&"walker").walk(Vector2.RIGHT)
	await t.seconds(2.0)
	t.check(
		walker.global_position.x < BEAM_X,
		"a standing body is stopped by it (x %.1f)" % walker.global_position.x,
	)
	t.puppet(&"walker").walk(Vector2.ZERO)
	beam.queue_free()


## A solid of the 3D space only: `rect` (plan px) from `base` to `top` px up.
func _block(t: TestContext, rect: Rect2, base: float, top: float) -> StaticBody3D:
	var block := StaticBody3D.new()
	block.collision_layer = PhysicsLayers.TWIN_WORLD
	block.collision_mask = 0
	block.add_child(TwinShapes.box(rect, Transform2D.IDENTITY, base, top))
	t.world.twin_space().add_child(block)
	return block
