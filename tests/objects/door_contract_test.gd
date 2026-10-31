extends GameTest
## The door contract (architecture interface 24), as the player's Use key, a scroll and the AI will
## drive it: `toggle` swings a shut or ajar door fully open and an open one shut, in about 0.4 s;
## `turn_by` turns it by degrees between shut and open (20 degrees a scroll notch) and it stays
## there; `open_fully` opens it; `angle()`, `open_amount()`, `gap()` and `is_down()` say where it
## is; `latch_side_spot(from)` is where to stand to work its latch; the signal `changed` says the
## state moved; the shadow turns with the leaf; a knocked-down door is no longer usable and leaves
## the doorway clear. Both hinge sides work, a puppet walks through an open door.

const JAMB := 20.0
## The doorway's free width (jamb to jamb) the leaf fills.
const LEAF := 40.0
const FULL := 90.0
## The swing's time, and the slack for a frame or two.
const SWING := 0.4
const SLACK := 0.15


func describe() -> Dictionary:
	return {
		"name": "The door contract swings, turns and reports",
		"description": "toggle, turn_by and open_fully swing a door between shut and 90 degrees "
			+ "in about 0.4 s, clamped, from either hinge; angle, open_amount and gap say where "
			+ "it is; latch_side_spot names the latch side; changed fires; the shadow turns "
			+ "with the leaf; a fallen door is unusable and the doorway clear.",
		"tags": ["door", "objects", "contract"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 600) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 600) },
	], [
		_doorway(100.0, -1.0, Vector2.RIGHT, "upper"),
		_doorway(250.0, 1.0, Vector2.LEFT, "lower"),
		_doorway(400.0, -1.0, Vector2.RIGHT, "felled"),
		_doorway(520.0, -1.0, Vector2.RIGHT, "ajar", 25.0),
	])
	s.von_down()
	s.actor(&"walker", &"puppet", Vector2(330, 250))


## A doorway at row `y` with its hinge on the jamb `side` (-1 above the centre, +1 below) and the
## door swinging toward `swing`, standing `start` degrees open.
func _doorway(y: float, side: float, swing: Vector2, id: String, start := 0.0) -> Dictionary:
	return {
		"pos": Vector2(400, y), "width": 52.0,
		"door": {
			"name": id, "material": "hollow", "style": "flush",
			"hinge": Vector2(400, y + side * JAMB), "swing_into": swing, "angle": start,
		},
	}


func run(t: TestContext) -> void:
	var upper = t.object(&"upper")
	var lower = t.object(&"lower")
	var changes := [0]
	upper.changed.connect(func(): changes[0] += 1)
	t.check(upper.angle() == 0.0 and upper.open_amount() == 0.0, "a door starts shut")
	t.check(upper.gap() == 0.0 and not upper.is_down(), "shut, it passes nobody and stands")
	var shut_box := _shadow_box(upper)
	t.check(shut_box.size.y > shut_box.size.x, "its shadow lies along the doorway while shut")
	t.expect_eq(upper.swing_into, Vector2.RIGHT, "it swings into the room it was told")
	t.expect_eq(upper.open_angle, FULL, "it opens to 90 degrees")

	upper.toggle(null)
	await t.seconds(SWING / 2.0)
	t.check(
		upper.angle() > 10.0 and upper.angle() < FULL - 10.0,
		"half a swing in, the door is part way (angle %.0f)" % upper.angle(),
	)
	await t.seconds(SWING / 2.0 + SLACK)
	t.check(upper.angle() == FULL, "a shut door toggled swings fully open (%.0f)" % upper.angle())
	t.check(upper.open_amount() == 1.0, "open_amount is 1 when it is wide open")
	t.check(changes[0] > 0, "changed fired as it moved")
	upper.toggle(null)
	await t.seconds(SWING + SLACK)
	t.check(upper.angle() == 0.0, "an open door toggled swings shut (%.0f)" % upper.angle())

	await _turning(t, upper)
	lower.open_fully(null)
	await t.seconds(SWING + SLACK)
	t.check(lower.angle() == FULL, "open_fully opens a door hinged below (%.0f)" % lower.angle())
	var lower_box := _shadow_box(lower)
	t.check(
		lower_box.size.x > lower_box.size.y and lower_box.get_center().x < 400.0,
		"a door told to swing west opens into the west room (%s)" % lower_box,
	)
	await _walk_through(t)
	await _spots_and_fallen(t)
	_ajar_start(t)


## `turn_by` turns by degrees between shut and open, clamped, and a part-open door toggles open.
func _turning(t: TestContext, upper: Node2D) -> void:
	upper.turn_by(30.0, null)
	await t.seconds(SWING)
	t.check(
		upper.angle() == 30.0,
		"turn_by turns it by degrees and it stays (%.0f)" % upper.angle(),
	)
	t.check(
		is_equal_approx(upper.open_amount(), 30.0 / FULL),
		"open_amount is the share of the way open (%.2f)" % upper.open_amount(),
	)
	_check_gap(t, upper, 30.0)
	upper.turn_by(20.0, null)
	await t.seconds(SWING)
	_check_gap(t, upper, 50.0)
	upper.turn_by(-100.0, null)
	await t.seconds(SWING + SLACK)
	t.check(upper.angle() == 0.0, "turning past shut stops at shut (%.0f)" % upper.angle())
	upper.turn_by(40.0, null)
	await t.seconds(SWING)
	upper.toggle(null)
	await t.seconds(SWING + SLACK)
	t.check(upper.angle() == FULL, "an ajar door toggled swings fully open (%.0f)" % upper.angle())
	_check_gap(t, upper, FULL)
	var open_box := _shadow_box(upper)
	t.check(
		open_box.size.x > open_box.size.y and open_box.get_center().x > 400.0,
		"its shadow has turned with the leaf, along the east room's wall now (%s)" % open_box,
	)


## The gap of `door` at `angle`: the straight way from the leaf's free end to the opposite jamb,
## worked out here from the hinge, the swing and the leaf, capped at the doorway's width.
func _check_gap(t: TestContext, door: Node2D, angle: float) -> void:
	var along: Vector2 = (Vector2(400, door.hinge.y + JAMB) - door.hinge).normalized()
	var tip: Vector2 = door.hinge + LEAF * (along * cos(deg_to_rad(angle))
			+ door.swing_into * sin(deg_to_rad(angle)))
	var expected := minf(tip.distance_to(door.hinge + along * LEAF), LEAF)
	t.check(
		absf(door.gap() - expected) < 1.5,
		"at %.0f degrees the gap is %.1f px (%.1f)" % [angle, expected, door.gap()],
	)


## The box the door's shadow covers now, in the world (an empty box for a door with none).
func _shadow_box(door: Node2D) -> Rect2:
	var occluders := door.find_children("*", "LightOccluder2D", true, false)
	if occluders.is_empty():
		return Rect2()
	var occ: LightOccluder2D = occluders[0]
	var box := Rect2(occ.global_transform * occ.occluder.polygon[0], Vector2.ZERO)
	for p in occ.occluder.polygon:
		box = box.expand(occ.global_transform * p)
	return box


## A door placed ajar stays as it was placed, with the gap that angle leaves.
func _ajar_start(t: TestContext) -> void:
	var ajar = t.object(&"ajar")
	t.check(ajar.angle() == 25.0, "a door placed ajar stays there (%.0f)" % ajar.angle())
	_check_gap(t, ajar, 25.0)


## A puppet walks through the open door hinged below, west to east.
func _walk_through(t: TestContext) -> void:
	t.puppet(&"walker").walk_to(Vector2(500, 250))
	t.check(
		await t.until(func(): return t.actor(&"walker").global_position.x > 480.0, 4.0),
		"a puppet walks through an open door (x %.0f)" % t.actor(&"walker").global_position.x,
	)


## The latch side spot is on the latch jamb's side of the doorway and on `from`'s side of the wall;
## a door knocked down is unusable and its doorway is clear.
func _spots_and_fallen(t: TestContext) -> void:
	var upper = t.object(&"upper")
	var west: Vector2 = upper.latch_side_spot(Vector2(300, 100))
	t.check(
		west.x < 395.0 and west.x > 340.0 and west.y > 100.0 and west.y < 120.0,
		"from the west the latch side spot is by the latch jamb, west of the wall (%s)" % west,
	)
	var east: Vector2 = upper.latch_side_spot(Vector2(500, 100))
	t.check(
		east.x > 405.0 and east.x < 460.0 and east.y > 100.0 and east.y < 120.0,
		"from the east it is on the east side (%s)" % east,
	)
	var felled = t.object(&"felled")
	felled.take_damage(1000.0)
	var before := [felled.angle(), felled.is_down()]
	felled.toggle(null)
	felled.turn_by(-45.0, null)
	await t.seconds(SWING + SLACK)
	t.check(felled.is_down() and before[1], "a fallen door is down")
	t.check(felled.gap() == LEAF, "and leaves the whole doorway clear (gap %.0f)" % felled.gap())
	t.check(felled.open_amount() == 1.0, "counted wide open")
	t.check(felled.angle() == before[0], "no use turns it (angle %.0f)" % felled.angle())
