extends GameTest
## A shoved piece's twin follows it (`TwinSpace`, interface 29): a coffee table, asleep, struck off
## centre slides and spins; every frame its twin stands where the 2D body stood this frame or the
## one before (the engine moves a rigid body in its step, after the scripts the twin is synced in:
## at most one step behind), and once it lies still the twin matches it exactly, so a ray dropped
## on the table's turned corner lands on it and one dropped on the corner's old place does not.

const Probe := preload("res://tests/_general/twin_probe.gd")
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
	var table := t.object(&"table") as RigidBody2D
	# it settles and sleeps first: the shove then wakes a piece the twin space has stopped reading
	await t.until(func() -> bool: return table.sleeping, 5.0)
	t.require(table.sleeping, "premise: the table is asleep before it is shoved")
	var twins := Probe.twins(t)
	var half := (table.get("size") as Vector2) * 0.5
	var corner := Vector2(half.x - 4.0, half.y - 4.0)
	var old_corner := table.global_transform * corner
	table.apply_impulse(Vector2(4000.0, 0.0), Vector2(0.0, 12.0))
	await t.frames(2)
	t.require(not table.sleeping, "premise: the shove woke it")
	var previous := table.global_transform
	var off := 0
	var frames := 0
	while frames < 600 and not table.sleeping:
		await t.frames(1)
		frames += 1
		var twin := twins.twin_of(table)
		if not _near(twin, table.global_transform) and not _near(twin, previous):
			off += 1
		previous = table.global_transform
	if not t.require(table.sleeping, "premise: the table comes to rest"):
		return
	t.require(
		table.global_position.distance_to(AT) > 20.0 and absf(table.rotation) > 0.05,
		"premise: it slid and turned (%s, %.2f rad)" % [table.global_position, table.rotation],
	)
	t.expect_eq(off, 0, "its twin was never more than a step behind")
	await t.frames(3)
	t.check(
		_near(twins.twin_of(table), table.global_transform),
		"at rest its twin matches the body exactly",
	)
	var new_corner := table.global_transform * corner
	t.check(
		Probe.down(t, new_corner).get("owner") == table,
		"a ray on the turned corner lands on it",
	)
	t.expect_near(Probe.top_at(t, new_corner), TOP, 0.5, "at the table's top")
	t.check(Probe.down(t, old_corner).get("owner") != table, "its old corner is empty")
	await _teleported(t, twins, table)
	await _reparented(t, twins, table)


## The resting table, asleep and off the follow list, is moved by a script (`global_position =`):
## its twin is at the new place within a few frames, and the old place is empty.
func _teleported(t: TestContext, twins: TwinSpace, table: RigidBody2D) -> void:
	t.require(table.sleeping, "premise: the table is asleep before it is teleported")
	var from := table.global_position
	var to := Vector2(700.0, 120.0)
	table.global_position = to
	await t.frames(3)
	t.check(_near(twins.twin_of(table), table.global_transform), "its twin followed the teleport")
	t.check(Probe.down(t, to).get("owner") == table, "a ray at the new place lands on the table")
	t.check(Probe.down(t, from).get("owner") != table, "the old place is empty")


## The table leaves the tree and comes back (a reparent): it has one twin, and it is not watched
## twice for waking (the connection of its first twin went with it).
func _reparented(t: TestContext, twins: TwinSpace, table: RigidBody2D) -> void:
	var parent := table.get_parent()
	var before := twins.count
	parent.remove_child(table)
	parent.add_child(table)
	await t.frames(3)
	t.expect_eq(twins.count, before, "one twin for the table, as before")
	var watching := 0
	for link: Dictionary in table.sleeping_state_changed.get_connections():
		if (link["callable"] as Callable).get_object() == twins:
			watching += 1
	t.expect_eq(watching, 1, "the twin space watches the table's sleep once")
	t.check(
		Probe.down(t, table.global_position).get("owner") == table,
		"a ray on the table lands on its new twin",
	)


## Whether `twin` stands where a body of 2D transform `xf` does.
func _near(twin: Node3D, xf: Transform2D) -> bool:
	var plan := PlanSpace.plan_transform(twin.global_transform)
	return (
		plan.origin.distance_to(xf.origin) < NEAR
		and absf(angle_difference(plan.get_rotation(), xf.get_rotation())) < NEAR_TURN
	)
