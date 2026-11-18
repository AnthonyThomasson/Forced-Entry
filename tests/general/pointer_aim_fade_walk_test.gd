extends GameTest
## The player's aim looks through every twin the wall fade holds faded, however many lie on the
## cursor's line (interface 26): a body stands behind a row of nine thin tall pieces, all held
## faded, and the cursor over it still meets the body. A look through a faded piece costs no step of
## the aim's walk, which is bounded (`Pointer.AIM_WALK`) for the solid things it passes.

const RigProbe := preload("res://tests/_general/rig_probe.gd")
const STANDER := Vector2(500, 250)
## The row's first piece starts this far (px) toward the camera from the body; nine of them, each
## `DEPTH` deep, all within the fade's reach of the body.
const FIRST := 16.0
const DEPTH := 2.5
const PIECES := 9
const RUN := Vector2(-1.0, 0.0)

var _look := Vector3.ZERO


func describe() -> Dictionary:
	return {
		"name": "The cursor aims through a row of faded pieces at the body behind them",
		"description": "Nine thin tall pieces held faded stand between the camera and a body; "
			+ "the cursor over the body meets it, the row looked through.",
		"tags": ["pointer", "3d", "aim", "twins", "wall-fade"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.lock_interaction([&"camera"])
	s.arena(Rect2(0, 0, 1000, 500))
	s.switch(&"nav.rebake", false)
	s.set_static(RenderConfig, &"pitch_degrees", 45.0)
	s.actor(&"you", &"player", Vector2(300, 250))
	s.actor(&"stander", &"puppet", STANDER, { "facing": Vector2.LEFT })
	for i in PIECES:
		var thin := WorldGen.object_definition("table").duplicate()
		thin["size"] = Vector2(DEPTH, 40.0)
		thin["art_opts"] = { "height": 70.0 }
		thin["anchored"] = true
		s.object(StringName("thin_%d" % i), thin, STANDER - RUN * (FIRST + DEPTH * (i + 0.5)))


func run(t: TestContext) -> void:
	var camera := Camera2D.new()
	camera.position = Vector2(300, 250)
	t.world.add_child(camera)
	camera.make_current()
	var rig := RigProbe.open(t.world, camera, 90.0)
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	var fade := WallFade.new()
	view.add_child(mirror)
	view.add_child(fade)
	fade.set_process(false)
	fade.listen(mirror)
	ObjectMeshes.register(mirror.builders)
	mirror.mirror(t.world)
	await t.frames(4)
	_look = -rig.camera.global_transform.basis.z
	var you := t.actor(&"you")
	var aim_at := PlanSpace.lift(STANDER, 20.0)
	var ground := aim_at + _look * (-aim_at.y / _look.y)
	Pointer.inject(Pointer.screen_of(you, PlanSpace.plan_of(ground)))
	await t.frames(2)
	t.expect_eq(Pointer.aim_hit(you, you).get("kind"), &"cover", "premise: the row is aimed at")
	for i in 14:
		fade.step(0.05, 90.0, PackedVector2Array([STANDER]))
	await t.frames(2)
	t.expect_eq(FadedTwins.count(), PIECES, "premise: all nine pieces are held faded")
	var meets := Pointer.aim_hit(you, you)
	t.expect_eq(meets.get("kind"), &"body", "the body behind the row is met (%s)" % [meets])
