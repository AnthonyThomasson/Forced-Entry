extends GameTest
## Pointer's aim hit in the 3D render (#194 D8, interface 26): the cursor's line of sight (the
## camera's own direction through the ground point under the mouse) is cast into the twin space.
## Over a standing body's head it meets that body's twin at head height (`kind` body, a head-zone
## height); over a piece of cover that hides a ducked body behind it, the point on the cover (`kind`
## cover, the table's top); over bare floor it meets nothing (an empty answer: the player aims
## level). The player's own body is looked through. The camera is tilted to 45 degrees so cover
## hides what is behind it by its height.

const RigProbe := preload("res://tests/_general/rig_probe.gd")
const AT := Vector2(300, 250)
const STANDER := Vector2(600, 150)
const DUCKER := Vector2(600, 350)
const TABLE_TOP := 31.0
## The table's depth along the line of sight, and the gap between it and the ducked body.
const TABLE_DEPTH := 40.0
const GAP := 0.5
## The plan direction the line of sight runs at yaw 90: toward -x (the camera is on the +x side:
## ground +x is down the screen). The table is put on the camera's side of the ducked body.
const RUN := Vector2(-1.0, 0.0)


func describe() -> Dictionary:
	return {
		"name": "The cursor aims at a body's head, at cover hiding a body, else level",
		"description": "The cursor's line cast into the twin space meets a standing body's head "
			+ "at head height, the table's top when a ducked body hides behind it and nothing "
			+ "over bare floor; the player's own body is no obstacle.",
		"tags": ["pointer", "3d", "aim", "twins", "cover"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.lock_interaction([&"camera"])
	s.arena(Rect2(0, 0, 1000, 500))
	s.switch(&"nav.rebake", false)
	s.set_static(RenderConfig, &"pitch_degrees", 45.0)
	s.actor(&"you", &"player", AT)
	s.actor(&"stander", &"puppet", STANDER, { "facing": Vector2.LEFT })
	s.actor(&"ducker", &"puppet", DUCKER, { "facing": Vector2.LEFT })
	var table := WorldGen.object_definition("table").duplicate()
	table["size"] = Vector2(TABLE_DEPTH, 120.0)
	table["anchored"] = true
	s.object(&"hider", table, _edge() - RUN * TABLE_DEPTH * 0.5)


func run(t: TestContext) -> void:
	var camera := Camera2D.new()
	camera.position = AT
	t.world.add_child(camera)
	camera.make_current()
	var rig := RigProbe.open(t.world, camera, 90.0)
	await t.frames(4)
	var you := t.actor(&"you")
	t.check(t.actor(&"ducker").movement.set_posture(&"crouch"), "the second body ducks")
	var look := -rig.camera.global_transform.basis.z
	var run_dir := Vector2(look.x, look.z).normalized()
	t.require(
		run_dir.is_equal_approx(RUN),
		"premise: at yaw 90 the line of sight runs along -x (%s)" % run_dir,
	)

	await _check_head(t, you, look)
	await _check_cover(t, you, look)
	await _check_floor(t, you, look)


## The cursor over a standing body's head.
func _check_head(t: TestContext, you: Node, look: Vector3) -> void:
	var head := PlanSpace.lift(STANDER, BodyHeights.head_top(BodyHeights.STAND) - 6.0)
	Pointer.inject(_screen_over(you, head, look))
	await t.frames(2)
	var meets := Pointer.aim_hit(you, you)
	t.expect_eq(
		meets.get("kind"),
		&"body",
		"the cursor over the head meets the body (%s)" % [meets],
	)
	t.expect_eq(
		BodyHeights.zone_at(BodyHeights.STAND, float(meets.get("height", -1.0))), &"head",
		"at head height (%.1f px)" % float(meets.get("height", -1.0)),
	)
	t.check(
		(meets.get("plan", Vector2.INF) as Vector2).distance_to(STANDER) < 15.0,
		"over the body (%s)" % [meets.get("plan")],
	)
	await t.frames(2)
	t.expect_eq(you.movement.aim_height, float(meets.get("height", -9.0)), "the player aims at it")
	t.check(
		you.movement.aim_point.distance_to(meets.get("plan", Vector2.INF)) < 0.01,
		"and faces that point",
	)


## The cursor over cover that hides a ducked body: the table sits on the camera's side of it, and
## the cursor goes over its top a little before its far edge, where the line goes on through the
## gap into the body.
func _check_cover(t: TestContext, you: Node, look: Vector3) -> void:
	Pointer.inject(_screen_over(you, PlanSpace.lift(_edge() - RUN * 3.0, TABLE_TOP), look))
	await t.frames(2)
	var cover := Pointer.aim_hit(you, you)
	t.expect_eq(cover.get("kind"), &"cover", "the cursor over the table meets cover (%s)" % [cover])
	t.expect_near(float(cover.get("height", -1.0)), TABLE_TOP, 0.6, "its top")


## The cursor over bare floor, and over the player's own body.
func _check_floor(t: TestContext, you: Node, look: Vector3) -> void:
	Pointer.inject(Pointer.screen_of(you, Vector2(850, 450)))
	await t.frames(2)
	t.check(Pointer.aim_hit(you, you).is_empty(), "the cursor over bare floor meets nothing")
	t.expect_eq(you.movement.aim_height, CharacterMovement.AIM_LEVEL, "so the player aims level")
	t.check(you.movement.aim_point.distance_to(Vector2(850, 450)) < 2.0, "at the floor point")

	var own := PlanSpace.lift(AT, 40.0)
	Pointer.inject(_screen_over(you, own, look))
	await t.frames(2)
	t.check(Pointer.aim_hit(you, you).is_empty(), "the player's own body is looked through")


## The table's far edge, next to the ducked body.
func _edge() -> Vector2:
	return DUCKER - RUN * (14.0 + GAP)


## The screen point whose line of sight passes through the 3D point `through`: the ground point
## `look` leads to.
func _screen_over(node: Node, through: Vector3, look: Vector3) -> Vector2:
	var ground := through + look * (-through.y / look.y)
	return Pointer.screen_of(node, PlanSpace.plan_of(ground))
