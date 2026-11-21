extends GameTest
## A piece is tipped past `PieceBodyConfig.tipped_degrees` (25) and upright again only under
## `upright_degrees` (15): one leaning on a wall's skirting at 24.9 and 25.1 degrees does not toggle
## sit and lie on and off. Its footprint hull (and the nav hole cut from it) is cut again only when
## the hull really changed, not on every frame a lying piece slides (#194 furn3d review).

const Probe := preload("res://tests/_objects/piece_probe.gd")
const CHAIR_AT := Vector2(150, 150)
const SHELF_AT := Vector2(400, 250)


func describe() -> Dictionary:
	return {
		"name": "A tipped piece stays tipped until it is nearly upright, and slides without recuts",
		"description": "A chair held at 20 degrees is upright, tipped after it passed 30, upright "
			+ "again under 15; a bookshelf lying on its side and slid cuts its footprint hull a "
			+ "few times, not every frame.",
		"tags": ["furniture", "3d", "tipping", "navigation"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 400))
	s.object(&"chair", "chair", CHAIR_AT)
	s.object(&"shelf", "bookshelf", SHELF_AT)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	var chair := t.object(&"chair")
	var body := Probe.body(chair)
	body.freeze = true  # the poses below are held, whatever the physics would do
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	var at := body.global_position
	body.global_transform = _leaning(20.0, at)
	t.check(not body.tipped(), "a chair that never tipped, at 20 degrees, is upright")
	body.global_transform = _leaning(30.0, at)
	t.check(body.tipped(), "at 30 degrees it is tipped")
	body.global_transform = _leaning(20.0, at)
	t.check(body.tipped(), "back at 20 degrees it is still tipped (not toggling on the edge)")
	body.global_transform = _leaning(10.0, at)
	t.check(not body.tipped(), "under 15 degrees it is upright again")
	body.global_transform = _leaning(20.0, at)
	t.check(not body.tipped(), "and at 20 it is upright, as it was")
	await _slide(t)


func _leaning(degrees: float, at: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.BACK, deg_to_rad(degrees)), at)


## A bookshelf laid on its side and slid along the floor.
func _slide(t: TestContext) -> void:
	var shelf := t.object(&"shelf")
	Knockback.push(shelf, Vector2(5000.0, 0.0), Vector2.ZERO, Probe.top(shelf) - 4.0)
	await t.seconds(0.3)
	await Probe.settle(t, shelf, 10.0)
	if not t.require(Probe.lean(shelf) > 60.0, "premise: the bookshelf lies on its side"):
		return
	var stamp: int = shelf.footprint_stamp
	var from: Vector2 = shelf.global_position
	Knockback.push(shelf, Vector2(4000.0, 0.0), Vector2.ZERO, Probe.centre(shelf))
	await t.seconds(0.4)
	await Probe.settle(t, shelf, 10.0)
	t.check(
		shelf.global_position.x - from.x > 5.0,
		"premise: it slid (%.1f px)" % (shelf.global_position.x - from.x),
	)
	var cuts: int = shelf.footprint_stamp - stamp
	t.check(cuts <= 2, "its hull was cut %d times for the slide, not every frame" % cuts)
