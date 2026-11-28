extends GameTest
## D18 (#194, `docs/doors.md` DR11): a blast that fells a door tears it off its hinges as a
## free 3D body, a real object: the frag goes off west of a hollow door, close to its middle, and
## the leaf is thrown east, topples and lies on the floor as physics decides, asleep, flat (its
## 3D body a `PieceBody`, the truth, the door's 2D body its footprint). No fixed fall.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const DOORWAY := Vector2(400, 300)
const HINGE := Vector2(400, 280)
const BURST_AT := Vector2(360, 300)
const BURST_HEIGHT := 42.0
## The second doorway, blasted from the pull side (the side the leaf swings toward: east).
const PULL_DOORWAY := Vector2(400, 600)
const PULL_BURST_AT := Vector2(440, 600)
## A leaf lying flat is as high as it is thick; allow the body's resting gap.
const FLAT_TOP := 9.0


func describe() -> Dictionary:
	return {
		"name": "A blast knocks a door off its hinges and it lies as a free body",
		"description": "A frag west of a hollow door fells it: its 3D body is a free piece, it is "
			+ "thrown east and lies flat and asleep on the floor beyond the doorway, its 2D "
			+ "body following it.",
		"tags": ["door", "objects", "damage", "blast", "3d", "tipping"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 800) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 800) },
	], [{
		"pos": DOORWAY, "width": 52.0,
		"door": {
			"name": "blown", "material": "hollow", "style": "flush",
			"hinge": HINGE, "swing_into": Vector2.RIGHT,
		},
	}, {
		"pos": PULL_DOORWAY, "width": 52.0,
		"door": {
			"name": "blown_pull", "material": "hollow", "style": "flush",
			"hinge": PULL_DOORWAY + Vector2(0.0, -20.0), "swing_into": Vector2.RIGHT,
		},
	}])
	s.von_down()


func run(t: TestContext) -> void:
	await t.frames(3)
	var door = t.object(&"blown")
	t.require(not door.is_down(), "premise: the door stands")
	t.require(
		not TwinSpace.twin_for(door) is PieceBody, "premise: a standing door is no free piece",
	)
	var row := GrenadeConfig.row(&"frag").duplicate()
	row["fragments"] = 0
	Explosion.frag(BURST_AT, t.world, null, row, BURST_HEIGHT)
	await t.seconds(0.3)
	t.check(door.is_down(), "the blast fells the door (hp %.0f)" % door.damage.hp)
	var lead := Probe.body(door)
	if not t.require(lead is PieceBody, "its 3D body is a free piece (PieceBody)"):
		return
	t.check(
		await Probe.settle(t, door, 12.0),
		"it comes to rest and sleeps, as a piece does",
	)
	t.check(
		Probe.lean(door) > 70.0,
		"it lies on its side (%.0f degrees from upright)" % Probe.lean(door),
	)
	t.check(
		Probe.top(door) <= FLAT_TOP,
		"flat: its top is %.1f px, a leaf's thickness" % Probe.top(door),
	)
	t.check(
		Probe.middle(door).x > DOORWAY.x + 20.0,
		"it was thrown east, away from the blast (x %.0f)" % Probe.middle(door).x,
	)
	var under := PlanSpace.plan_of(lead.global_position)
	t.check(
		door.global_position.distance_to(under) < 0.5,
		"the 2D door follows its 3D body (%.2f px apart)" % door.global_position.distance_to(under),
	)
	t.check(door.gap() >= door.width, "the doorway is clear")
	await _from_the_pull_side(t)


## The same blast from the side the leaf swings toward fells it and throws it the other way.
func _from_the_pull_side(t: TestContext) -> void:
	var door = t.object(&"blown_pull")
	t.require(not door.is_down(), "premise: the second door stands")
	var row := GrenadeConfig.row(&"frag").duplicate()
	row["fragments"] = 0
	Explosion.frag(PULL_BURST_AT, t.world, null, row, BURST_HEIGHT)
	await t.seconds(0.3)
	t.check(door.is_down(), "a blast from the pull side fells the door (hp %.0f)" % door.damage.hp)
	t.check(Probe.body(door) is PieceBody, "its 3D body is a free piece")
	t.check(await Probe.settle(t, door, 12.0), "it comes to rest and sleeps")
	t.check(
		Probe.middle(door).x < PULL_DOORWAY.x - 20.0,
		"it was thrown west, away from the blast (x %.0f)" % Probe.middle(door).x,
	)
	t.check(
		Probe.top(door) <= FLAT_TOP,
		"and lies flat (top %.1f px, lean %.0f)" % [Probe.top(door), Probe.lean(door)],
	)
