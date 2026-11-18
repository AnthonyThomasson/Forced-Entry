extends GameTest
## In the 3D render mode the human's aim and Space's nearest-to-mouse read the mouse's ground point
## (#193 rule 5): the point where the camera ray under the mouse meets the ground. At yaw 90, zoom
## 0.2 and the camera on the player, 100 px of ground along +x shows (0, 19.696) px from the
## screen's middle and 30 px along +y shows (-6, 0) (the near top-down projection worked by hand:
## (dx cos 90 - dy sin 90, sin 80 * (dx sin 90 + dy cos 90)) * zoom). The mouse is put (injected) at
## those hand-worked points, and the aim and the chair Space would use must be the ones there. Read
## as a flat screen the point over chair B would be exactly chair A's.

const RigProbe := preload("res://tests/_general/rig_probe.gd")
const AT := Vector2(450, 250)
const ZOOM := 0.2
## A chair 30 px along -x of the player and one 30 px along +y.
const CHAIR_A := Vector2(420, 250)
const CHAIR_B := Vector2(450, 280)


func describe() -> Dictionary:
	return {
		"name": "In 3D the aim and Space follow the mouse's ground point",
		"description": "The mouse at a hand-worked screen point aims the player at the ground "
			+ "point under it and Space picks the chair there, not the one a flat reading of the "
			+ "screen would.",
		"tags": ["pointer", "3d", "player", "interaction", "input"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.lock_interaction([&"camera"])
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.object(&"a", "chair", CHAIR_A)
	s.object(&"b", "chair", CHAIR_B)
	s.actor(&"you", &"player", AT)


func run(t: TestContext) -> void:
	var camera := Camera2D.new()
	camera.position = AT
	camera.zoom = Vector2(ZOOM, ZOOM)
	t.world.add_child(camera)
	camera.make_current()
	RigProbe.open(t.world, camera, 90.0)
	await t.frames(4)
	var you := t.actor(&"you")
	var middle := t.world.get_viewport().get_visible_rect().size * 0.5

	# The mouse over 100 px of ground along +x.
	Pointer.inject(middle + Vector2(0.0, 19.696))
	await t.frames(3)
	t.check(
		you.movement.aim_point.distance_to(AT + Vector2(100.0, 0.0)) < 3.0,
		"the aim is the ground point under the mouse (%s)" % you.movement.aim_point,
	)

	# The mouse over chair B: Space's nearest to the mouse is B (a flat reading of the screen point
	# is chair A).
	Pointer.inject(middle + Vector2(-6.0, 0.0))
	await t.frames(3)
	t.check(
		you.movement.aim_point.distance_to(CHAIR_B) < 8.0,
		"the aim is a point on chair B, which the cursor meets (D8a: %s)"
			% you.movement.aim_point,
	)
	var target: Dictionary = you.use.interact_target()
	t.check(
		target.get("kind", &"") == &"object" and target.get("object") == t.object(&"b"),
		"Space would use the chair under the mouse (%s)" % [target],
	)
