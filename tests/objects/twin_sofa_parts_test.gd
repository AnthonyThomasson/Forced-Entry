extends GameTest
## The 3D twin of a multi-part piece (`ObjectTwins`, interface 29, `PieceHeights`): a sofa is a box
## per part, so a ray dropped on its seat lands at the seat's height, one on an arm at the arm's,
## one on its back at the back's (18, 28, 38 px, the mesh's: `docs/research/3d-cover-heights.md`).
## The parts turn with the piece's facing: a sofa facing left (its body 50 wide, 120 tall) has its
## back on the right and an arm at each end. A level ray at 25 px passes over the seat and strikes
## the back.

const Probe := preload("res://tests/_general/twin_probe.gd")
const FACING_DOWN := Vector2(300, 250)
const FACING_LEFT := Vector2(600, 250)
## The mesh's heights (px).
const SEAT := 18.0
const ARM := 28.0
const BACK := 38.0


func describe() -> Dictionary:
	return {
		"name": "A sofa's twin has its seat, arms and back at their own heights, turned with it",
		"description": "Rays dropped on a 120x50 sofa facing down land at 18 (seat), 28 (arm) and "
			+ "38 (back); the same sofa facing left lands them on its right (back) and at its "
			+ "ends (arms); a level ray at 25 px passes over the seat and strikes the back.",
		"tags": ["twins", "3d", "heights", "furniture", "sofa"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.object(&"down", "sofa", FACING_DOWN)
	var left := WorldGen.object_definition("sofa").duplicate()
	left["size"] = Vector2(50, 120)
	s.object(&"left", left, FACING_LEFT, { "facing": Vector2.LEFT })


func run(t: TestContext) -> void:
	await t.frames(3)
	var down := t.object(&"down")
	t.check(
		Probe.down(t, FACING_DOWN + Vector2(0, 12)).get("owner") == down,
		"the seat is the sofa",
	)
	_top(t, "seat", FACING_DOWN + Vector2(0, 12), SEAT)
	_top(t, "back", FACING_DOWN + Vector2(0, -23.5), BACK)
	_top(t, "left arm", FACING_DOWN + Vector2(-58.5, 12), ARM)
	_top(t, "right arm", FACING_DOWN + Vector2(58.5, 12), ARM)
	# facing left: the front is toward -x, so the back is on the +x side
	_top(t, "turned seat", FACING_LEFT + Vector2(-12, 0), SEAT)
	_top(t, "turned back", FACING_LEFT + Vector2(23.5, 0), BACK)
	_top(t, "turned arm (north end)", FACING_LEFT + Vector2(-12, -58.5), ARM)
	_top(t, "turned arm (south end)", FACING_LEFT + Vector2(-12, 58.5), ARM)
	var over_seat := Probe.level(
		t, FACING_DOWN + Vector2(0, 80), FACING_DOWN + Vector2(0, -80), 25.0
	)
	# the sofa spans y 225 to 275, its back the rear strip: the ray is stopped inside the back's
	# strip (the rear half), not at the seat's front edge
	var struck := Vector2()
	if not over_seat.is_empty():
		struck = PlanSpace.plan_of(over_seat["position"])
	t.check(
		over_seat.get("owner") == down and struck.y >= 225.0 and struck.y < 250.0,
		"a ray at 25 px passes over the seat and strikes the back: %s" % struck,
	)


## The ray dropped on `at` lands `height` px up.
func _top(t: TestContext, what: String, at: Vector2, height: float) -> void:
	t.expect_near(Probe.top_at(t, at), height, 0.5, "the sofa's %s is %.0f px up" % [what, height])
