extends GameTest
## LD15 / D17 / D18 (`docs/leadership.md`): ambush a door. An `ambush` order
## `{ opening, room, pos }` sends the member to a post in the room on the click's side of the
## doorway: off the doorway's axis, inside the room's walls, out of the fatal funnel, with a clear
## line to the threshold, and unseen from outside, with no line to any of the slots or pie steps of
## an entry into the room by that doorway. There it holds, crouched, its gun on the threshold, and
## fires the moment a line opens (the watch stage). The order ends `done` on first contact (a
## hostile seen), and the member then fights on its own.
##
## The doorway is the Terrace house's hall / living room doorway (`door_150_360`, 80 px, in the
## living room's south wall), ambushed from the living room, the attacker coming from the hall. It
## is the only Terrace doorway with a post hidden from every slot and pie step in the plan's
## candidate ring (40 to 160 px back from the wall, 30 to 260 px past the jamb): such a post is
## tucked against the door's wall well along from it, and only the living room's south wall runs far
## enough east of this doorway (330 px). The slots and pie steps are the test's own copy of the
## entry geometry (`docs/tactical-entry.md`: slots `SLOT_STANDOFF` out from the wall, the first a
## body clear of the jamb, then every `SLOT_SPACING`, six a side; the pie `PIE_RADIUS` from the
## threshold, 55° to 25° off the axis, five steps), so the test checks the plan and not the code.
## Seen means a clear straight line on the solid layer, characters looked through.
##
## A defender in the living room is ordered (by its squad's leader, a household puppet in the
## kitchen) to ambush the doorway. Once it holds its post, an intruder puppet walks along the hall
## and steps into the doorway: the defender fires at it, its order is ended (`ordered` gone from its
## next decision, `order_step` `done` radioed) and it fights on (a COMBAT decision; scripted Von,
## the first option offered). The intruder is unkillable and never shoots.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const DOOR_ID := "door_150_360"
const DOOR := Maps.DOOR_HALL_LIVING
const DOOR_WIDTH := 80.0
## The unit normal out of the ambush room (the living room) through the doorway: into the hall.
const OUT := Vector2.DOWN
## The test's copy of the entry geometry (the defaults of the NPC's `tuning.entry_geometry`).
const SLOT_STANDOFF := 28.0
const SLOT_FIRST := 18.0
const SLOT_SPACING := 44.0
const SLOTS_A_SIDE := 6
const PIE_RADIUS := 100.0
const PIE_STEPS := 5
## A body's radius (px): off the axis means clear of the doorway's width by a body.
const BODY := 14.0
## The click that orders the ambush: in the living room, on the doorway's axis.
const CLICK := Vector2(150, 330)
## Where the intruder steps into the doorway from, along the hall, and the doorway itself.
const HALL_START := Vector2(560, 430)
const HALL_BY_DOOR := Vector2(150, 425)
## In the threshold on the living room's side of the wall (its face at y 354, the wall 12 thick):
## sight is symmetric, so a post hidden from outside cannot see a body whose centre is still outside
## the wall plane. The puppet stops `arrive_distance` (6 px) short, centre ~350.
const IN_DOORWAY := Vector2(150, 344)
## Facing within this of the threshold (dot of the facing with the direction to it) is the gun on
## it.
const ON_DOOR_DOT := 0.8


func describe() -> Dictionary:
	return {
		"name": "An ambusher holds a hidden post on the doorway and fires on the first to step in",
		"description": "Ordered to ambush the hall doorway from the living room, a defender holds "
			+ "a post off the axis, unseen from every slot and pie step outside, crouched, gun on "
			+ "the threshold; it fires at an intruder stepping into the doorway, its order ends "
			+ "and it fights on (LD15, D17, D18).",
		"tags": ["ai", "combat", "leadership", "order", "ambush", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([])
	s.switch(&"projectile.flyover", false)
	s.actor(&"a", &"defender", Vector2(240, 150))
	s.actor(&"lead", &"puppet", Vector2(700, 120), { "faction": &"household" })
	s.actor(
		&"intruder",
		&"puppet",
		HALL_START,
		{ "faction": &"invader", "max_health": 1_000_000.0 },
	)
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	var a := t.actor(&"a")
	var brain := await _take_post(t, a)
	if brain == null:
		return
	await _check_post(t, a)
	await _spring(t, a, brain)


## Orders the ambush and waits for the defender to take it and reach its post; the brain, or null
## when a step fails.
func _take_post(t: TestContext, a: Node) -> Node:
	var squad: Node = t.world.squad(&"household")
	await t.seconds(0.5)
	var order := Order.issue(squad, { "kind": Order.AMBUSH, "to": [a], "pos": CLICK })
	if not t.require(
			not order.is_empty(),
			"the squad posts the ambush order (issue of kind ambush returned %s)" % str(order),
	):
		return null
	t.expect_eq(String(order.get("opening", "")), DOOR_ID, "on the hall doorway")
	t.expect_eq(String(order.get("room", "")), "living_room", "from the living room")
	var brain := Order.brain(t, &"a")
	if not t.require(
			await t.until(func(): return Order.primitive(brain) == "ambush", 5.0),
			"the defender takes the ambush (primitive %s)" % Order.primitive(brain),
	):
		return null
	if not t.require(
			await t.until(func(): return not Order.progress(t, "in_position", a).is_empty(), 20.0),
			"it reaches its post and radios in_position",
	):
		return null
	await t.seconds(1.0)
	return brain


## The post: inside the room, off the axis, a line to the threshold, unseen from outside, crouched,
## its gun on the threshold.
func _check_post(t: TestContext, a: Node) -> void:
	var p: Vector2 = a.global_position
	t.check(
		Maps.HOUSE_LIVING.grow(-BODY).has_point(p),
		"the post is inside the living room's walls (%s)" % str(p.round()),
	)
	var lateral := absf((p - DOOR).dot(OUT.orthogonal()))
	t.check(
		lateral >= DOOR_WIDTH * 0.5 + BODY,
		"off the doorway's axis, out of its funnel (%.0f px along the wall from its centre)"
			% lateral,
	)
	t.check(Probe.line_clear(t, p, DOOR - OUT * 4.0), "with a clear line to the threshold")
	var seen_from := _observers().filter(func(o): return Probe.line_clear(t, o, p))
	t.check(
		seen_from.is_empty(),
		"unseen from every slot and pie step outside the doorway (seen from %s)"
			% str(seen_from.map(func(o): return (o as Vector2).round())),
	)
	t.expect_eq(String(a.movement.posture()), "crouch", "crouched at its post")
	var share := await _share_on(t, a, DOOR, 1.5)
	t.check(share >= 0.7, "its gun on the threshold (%.0f%% of 1.5 s)" % (share * 100.0))


## The intruder steps into the doorway: the ambusher fires, its order ends and it fights on.
func _spring(t: TestContext, a: Node, brain: Node) -> void:
	var puppet := t.puppet(&"intruder")
	puppet.walk_to(HALL_BY_DOOR)
	if not t.require(
			await t.until(puppet.has_arrived, 10.0),
			"the intruder walks along the hall to the doorway",
	):
		return
	t.check(
		Order.progress(t, "done", a).is_empty(),
		"the ambush holds while nobody has shown (no done yet)",
	)
	var stepped_at := t.time
	puppet.walk_to(IN_DOORWAY)
	var fired := func(): return t.happened(&"shot", func(d): return d.get("attacker") == a)
	t.check(
		await t.until(fired, 4.0),
		"the ambusher fires at the intruder stepping into the doorway",
	)
	var shots := Probe.raw(t, &"shot", func(d): return d.get("attacker") == a)
	if not shots.is_empty():
		t.check(
			float(shots[0]["time"]) >= stepped_at,
			"not before the intruder stepped in (stepped at %.2f s, first shot at %.2f s)"
				% [stepped_at, float(shots[0]["time"])],
		)
	t.check(
		await t.until(func(): return not Order.progress(t, "done", a).is_empty(), 4.0),
		"first contact ends the order: it radios done",
	)
	var ends := func():
		return Order.decisions(brain) > 0 and not Order.ordered(brain) and not Order.on_order(brain)
	t.check(
		await t.until(ends, 4.0),
		"its next decision holds no order (ordered %s, act %s)"
			% [str(Order.ordered(brain)), brain.current_act()],
	)
	t.check(
		String(brain.current_act()).begins_with("combat"),
		"and it fights on its own (act %s)" % brain.current_act(),
	)


## The slots and pie steps of an entry into the living room by the doorway, the test's own copy:
## where the stack and the point stand.
func _observers() -> Array:
	var along := OUT.orthogonal()
	var out: Array = []
	for side in [1, -1]:
		for k in SLOTS_A_SIDE:
			out.append(DOOR + OUT * SLOT_STANDOFF
					+ along * side * (DOOR_WIDTH * 0.5 + SLOT_FIRST + k * SLOT_SPACING))
		for i in PIE_STEPS:
			var theta := deg_to_rad(lerpf(55.0, 25.0, float(i) / float(PIE_STEPS - 1)))
			out.append(DOOR + OUT * cos(theta) * PIE_RADIUS
					+ along * side * sin(theta) * PIE_RADIUS)
	return out


## The share of `duration` s that `c` faces `at` within `ON_DOOR_DOT`.
func _share_on(t: TestContext, c: Node2D, at: Vector2, duration: float) -> float:
	var seen := 0
	var on := 0
	var end := t.time + duration
	while t.time < end:
		seen += 1
		if c.facing.normalized().dot((at - c.global_position).normalized()) >= ON_DOOR_DOT:
			on += 1
		await t.frames(1)
	return float(on) / float(maxi(seen, 1))
