extends GameTest
## A shoved piece and its footprint (`TwinSpace`, interface 29; #194 furn3d reversed the direction:
## the free 3D body is the truth of a piece of furniture and its 2D body follows it): a coffee
## table, asleep, struck off centre slides and spins in 3D; every frame its 2D body stands where the
## 3D body did this frame or the one before (the engine moves a rigid body in its step, after the
## scripts the twin space writes in: at most one step behind), and once it lies still they match
## exactly, so a ray dropped on the table's turned corner lands on it and one dropped on the
## corner's old place does not. A table a script moves (its 2D body is teleported) is adopted: the
## 3D body goes there.

const Probe := preload("res://tests/_general/twin_probe.gd")
const Piece := preload("res://tests/_objects/piece_probe.gd")
const AT := Vector2(300, 250)
## How far (px) and how much (rad) a twin may differ from the body's pose of this or the last frame.
const NEAR := 0.05
const NEAR_TURN := 0.001
## The coffee table's top (px).
const TOP := 18.0


func describe() -> Dictionary:
	return {
		"name": "A shoved table's twin follows it, a step behind at most, and rests where it does",
		"description": "A coffee table is struck off centre: each frame its twin is at the body's "
			+ "pose of this frame or the one before; at rest it matches exactly and a ray on its "
			+ "turned corner lands on it, while the corner's old place is empty.",
		"tags": ["twins", "3d", "furniture", "knockback"],
		"timeout": 14.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.object(&"table", "coffee_table", AT)
	# a blast-free room: nothing else is shoved, nothing re-bakes mid-slide
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	var table := t.object(&"table") as Node2D
	# it settles and sleeps first: the shove then wakes a piece the twin space has stopped reading
	await Piece.settle(t, table, 5.0)
	t.require(Piece.asleep(table), "premise: the table is asleep before it is shoved")
	var twins := Probe.twins(t)
	var half := (table.get("size") as Vector2) * 0.5
	var corner := Vector2(half.x - 4.0, half.y - 4.0)
	var start := table.global_transform
	Knockback.push(table, Vector2(4000.0, 0.0), Vector2(0.0, 12.0), 9.0)
	await t.frames(2)
	t.require(not Piece.asleep(table), "premise: the shove woke it")
	var off := await _slide(t, twins, table)
	if not t.require(Piece.asleep(table), "premise: the table comes to rest"):
		return
	t.require(
		table.global_position.distance_to(AT) > 20.0 and absf(table.rotation) > 0.05,
		"premise: it slid and turned (%s, %.2f rad)" % [table.global_position, table.rotation],
	)
	t.expect_eq(off, 0, "its 2D body was never more than a step behind the 3D body")
	await t.frames(3)
	t.check(
		_near(
			table.global_transform,
			PlanSpace.plan_transform(twins.twin_of(table).global_transform),
		),
		"at rest its 2D body matches the 3D body exactly",
	)
	var new_corner := table.global_transform * corner
	t.check(
		Probe.down(t, new_corner).get("owner") == table,
		"a ray on the turned corner lands on it",
	)
	t.expect_near(Probe.top_at(t, new_corner), TOP, 0.5, "at the table's top")
	_check_old_corners(t, table, start, corner)
	await _teleported(t, twins, table)
	await _reparented(t, twins, table)


## Wait for `table` to fall asleep, counting the frames its 2D body was more than a step behind its
## 3D body (the twin's pose, now or a frame ago).
func _slide(t: TestContext, twins: TwinSpace, table: Node2D) -> int:
	var twin := twins.twin_of(table)
	var previous := PlanSpace.plan_transform(twin.global_transform)
	var off := 0
	var frames := 0
	while frames < 600 and not Piece.asleep(table):
		await t.frames(1)
		frames += 1
		var now := PlanSpace.plan_transform(twin.global_transform)
		if not _near(table.global_transform, now) and not _near(table.global_transform, previous):
			off += 1
		previous = now
	return off


## A corner of the table's first footprint (`start`) that its footprint now leaves bare: a ray on it
## misses the table.
func _check_old_corners(
	t: TestContext, table: Node2D, start: Transform2D, corner: Vector2,
) -> void:
	var half := (table.get("size") as Vector2) * 0.5
	var bare: Array[Vector2] = []
	for sign_x in [-1.0, 1.0]:
		for sign_y in [-1.0, 1.0]:
			var old_corner := start * Vector2(corner.x * sign_x, corner.y * sign_y)
			var inside := table.global_transform.affine_inverse() * old_corner
			if absf(inside.x) > half.x or absf(inside.y) > half.y:
				bare.append(old_corner)
	t.require(not bare.is_empty(), "premise: it left a corner of its first footprint bare")
	for old_corner in bare:
		t.check(
			Probe.down(t, old_corner).get("owner") != table,
			"its old corner %s is empty" % old_corner.round(),
		)


## The resting table, asleep and off the follow list, is moved by a script (`global_position =`):
## its twin is at the new place within a few frames, and the old place is empty.
func _teleported(t: TestContext, twins: TwinSpace, table: Node2D) -> void:
	t.require(Piece.asleep(table), "premise: the table is asleep before it is teleported")
	var from := table.global_position
	var to := Vector2(700.0, 120.0)
	table.global_position = to
	await t.frames(3)
	t.check(
		_near(
			table.global_transform,
			PlanSpace.plan_transform(twins.twin_of(table).global_transform),
		),
		"its 3D body followed the teleport",
	)
	t.check(Probe.down(t, to).get("owner") == table, "a ray at the new place lands on the table")
	t.check(Probe.down(t, from).get("owner") != table, "the old place is empty")


## The table leaves the tree and comes back (a reparent): it has one twin, and it is not watched
## twice for waking (the connection of its first twin went with it).
func _reparented(t: TestContext, twins: TwinSpace, table: Node2D) -> void:
	var parent := table.get_parent()
	var before := twins.count
	parent.remove_child(table)
	parent.add_child(table)
	await t.frames(3)
	t.expect_eq(twins.count, before, "one twin for the table, as before")
	var watching := 0
	for link: Dictionary in Piece.body(table).sleeping_state_changed.get_connections():
		if (link["callable"] as Callable).get_object() == twins:
			watching += 1
	t.expect_eq(watching, 1, "the twin space watches its 3D body's sleep once")
	t.check(
		Probe.down(t, table.global_position).get("owner") == table,
		"a ray on the table lands on its new twin",
	)


## Whether the 2D transform `xf` is the plan transform `plan` (the 3D body's, in plan space).
func _near(xf: Transform2D, plan: Transform2D) -> bool:
	return (
		plan.origin.distance_to(xf.origin) < NEAR
		and absf(angle_difference(plan.get_rotation(), xf.get_rotation())) < NEAR_TURN
	)
