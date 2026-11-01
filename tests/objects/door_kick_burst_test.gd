extends GameTest
## DR10: a kick on a shut door from the side it swings away from (its push side) wears down its
## latch; when the latch gives, the door swings fully open at once. A hollow-core door's latch gives
## to the second kick (it holds the first), a solid wood door's to the fifth; no kick opens a steel
## door's. From the side it swings toward (its pull side) a kick only damages it, and a character
## walking into a door never opens it. The kick counts are the spec's (`docs/doors.md` DR13), kept
## here. An ajar door (30° here) is not latched whatever its material: one kick from its push side
## throws it fully open, steel too; one from its pull side turns it toward shut.

const JAMB := 20.0
## A front doorway is 60 px wide: its free passage is 48 px, jambs 24 px from its centre.
const FRONT_JAMB := 24.0
const PUSH_X := 370.0
const PULL_X := 430.0
## Seconds between two kicks (a kick takes 0.31 s to throw and draw back), and the time a burst has
## to throw the door open (a slower opening would be the swing, 0.4 s).
const BETWEEN := 0.55
const BURST := 0.3
const ROWS := {
	&"hollow": 100.0,
	&"hollow_pull": 250.0,
	&"steel": 400.0,
	&"solid": 550.0,
	&"walked": 700.0,
	&"punched": 850.0,
	&"front": 1000.0,
	&"ajar_hollow": 1150.0,
	&"ajar_solid": 1300.0,
	&"ajar_steel": 1450.0,
	&"ajar_pull": 1600.0,
	&"ajar_twice": 1750.0,
}
## Where a kicker stands to kick an ajar door (30°): its leaf crosses the kicker's line 11 px past
## the wall line, so the same 30 px from it as a shut door's kickers.
const AJAR_PUSH_X := 382.0
const AJAR_PULL_X := 441.0
## The shove of a kick (the spec's number: `docs/doors.md` DR10).
const KICK_IMPULSE := 2200.0


func describe() -> Dictionary:
	return {
		"name": "A latch gives to kicks from the push side",
		"description": "A hollow door holds the first kick and bursts open at the second; from "
			+ "the pull side it only takes damage; a solid door gives at the fifth, a steel one to "
			+ "no kick; punches and a puppet walking into a door do not open it; an ajar door, "
			+ "steel too, is thrown open by one kick from its push side and turned toward shut by "
			+ "one from its pull side.",
		"tags": ["door", "objects", "kick", "burst"],
		"timeout": 30.0,
	}


func _doorway(y: float, material: String, style: String, id: String, more := {}) -> Dictionary:
	var jamb: float = more.get("jamb", JAMB)
	return {
		"pos": Vector2(400, y), "width": 52.0 if jamb == JAMB else 60.0,
		"door": {
			"name": id, "material": material, "style": style,
			"hinge": Vector2(400, y - jamb), "swing_into": Vector2.RIGHT,
			"angle": more.get("angle", 0.0),
		},
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 1900) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 1900) },
	], [
		_doorway(ROWS[&"hollow"], "hollow", "flush", "hollow"),
		_doorway(ROWS[&"hollow_pull"], "hollow", "flush", "hollow_pull"),
		_doorway(ROWS[&"steel"], "steel", "riveted", "steel"),
		_doorway(ROWS[&"solid"], "solid", "panelled", "solid"),
		_doorway(ROWS[&"walked"], "hollow", "flush", "walked"),
		_doorway(ROWS[&"punched"], "hollow", "flush", "punched"),
		_doorway(ROWS[&"front"], "hollow", "flush", "front", { "jamb": FRONT_JAMB }),
		_doorway(ROWS[&"ajar_hollow"], "hollow", "flush", "ajar_hollow", { "angle": 30.0 }),
		_doorway(ROWS[&"ajar_solid"], "solid", "panelled", "ajar_solid", { "angle": 30.0 }),
		_doorway(ROWS[&"ajar_steel"], "steel", "riveted", "ajar_steel", { "angle": 30.0 }),
		_doorway(ROWS[&"ajar_pull"], "hollow", "flush", "ajar_pull", { "angle": 30.0 }),
		_doorway(ROWS[&"ajar_twice"], "hollow", "flush", "ajar_twice", { "angle": 30.0 }),
	])
	s.von_down()
	for id: StringName in [&"hollow", &"steel", &"solid", &"front"]:
		s.actor(StringName("%s_kicker" % id), &"puppet", Vector2(PUSH_X, ROWS[id]))
	# a punch is as hard a shove as a walking push: it never counts against a latch
	s.actor(&"punched_kicker", &"puppet", Vector2(PUSH_X, ROWS[&"punched"]), { "start_slot": 2 })
	s.actor(&"hollow_pull_kicker", &"puppet", Vector2(PULL_X, ROWS[&"hollow_pull"]))
	for id: StringName in [&"ajar_hollow", &"ajar_solid", &"ajar_steel"]:
		s.actor(StringName("%s_kicker" % id), &"puppet", Vector2(AJAR_PUSH_X, ROWS[id]))
	s.actor(&"ajar_pull_kicker", &"puppet", Vector2(AJAR_PULL_X, ROWS[&"ajar_pull"]))
	# in the arc of the front door, out at its latch end, where the leaf sweeps fastest
	s.actor(&"in_the_arc", &"puppet", Vector2(420, ROWS[&"front"] + 20.0))
	s.actor(&"walker", &"puppet", Vector2(300, ROWS[&"walked"]))


func run(t: TestContext) -> void:
	t.puppet(&"walker").walk_to(Vector2(500, ROWS[&"walked"]))
	for id: StringName in ROWS:
		var kicker := t.actor(StringName("%s_kicker" % id))
		if kicker != null:
			var toward := Vector2.LEFT if String(id).ends_with("_pull") else Vector2.RIGHT
			t.puppet(StringName("%s_kicker" % id)).aim_at(kicker.global_position + toward * 100.0)
	await t.seconds(0.6)
	await _hollow_door(t)
	await _pull_side(t)
	await _steel_and_solid(t)
	await _punched(t)
	await _burst_into_a_character(t)
	_walked_into(t)
	await _ajar(t)


## The hollow door holds the first kick from its push side and bursts open at the second.
func _hollow_door(t: TestContext) -> void:
	var hollow = t.object(&"hollow")
	await _kick(t, &"hollow")
	t.check(
		hollow.angle() == 0.0,
		"a hollow door holds the first kick (angle %.0f)" % hollow.angle(),
	)
	t.check(hollow.damage.hp < hollow.damage.max_hp, "but it is marked by it")
	await _kick(t, &"hollow")
	t.check(
		await t.until(func(): return hollow.angle() >= 89.0, BURST),
		"the second kick bursts the hollow door fully open at once (angle %.0f)" % hollow.angle(),
	)


## Kicked from the side it swings toward, a hollow door stays shut and only takes the damage.
func _pull_side(t: TestContext) -> void:
	var pulled = t.object(&"hollow_pull")
	for _i in 3:
		await _kick(t, &"hollow_pull")
	t.check(
		pulled.angle() == 0.0,
		"kicked from its pull side a hollow door stays shut (angle %.0f)" % pulled.angle(),
	)
	t.check(pulled.damage.hp < pulled.damage.max_hp - 40.0, "and only takes damage")


## No kick opens a steel door; a solid one holds four and gives to the fifth.
func _steel_and_solid(t: TestContext) -> void:
	var steel = t.object(&"steel")
	for _i in 8:
		await _kick(t, &"steel")
	t.check(steel.angle() == 0.0, "no kick opens a steel door (angle %.0f)" % steel.angle())
	var solid = t.object(&"solid")
	for _i in 4:
		await _kick(t, &"solid")
	t.check(solid.angle() == 0.0, "a solid door holds four kicks (angle %.0f)" % solid.angle())
	await _kick(t, &"solid")
	t.check(
		await t.until(func(): return solid.angle() >= 89.0, BURST),
		"and gives to the fifth (angle %.0f)" % solid.angle(),
	)


## Six punches from the push side leave the latch alone: the door is marked and stays shut.
func _punched(t: TestContext) -> void:
	var door = t.object(&"punched")
	for _i in 6:
		await _kick(t, &"punched", false)
	t.check(door.angle() == 0.0, "punches never burst a door (angle %.0f)" % door.angle())
	t.check(door.damage.hp < door.damage.max_hp, "though they mark it")


## A front door's longer leaf bursts open over a character at its latch end, which it nudges clear:
## the burst does not stall against it.
func _burst_into_a_character(t: TestContext) -> void:
	var front = t.object(&"front")
	var arc := t.actor(&"in_the_arc")
	await _kick(t, &"front")
	await _kick(t, &"front")
	t.check(
		await t.until(func(): return front.angle() >= 89.0, BURST),
		"a front door bursts fully open over a character in its arc (angle %.0f)" % front.angle(),
	)
	var pose: Transform2D = front.global_transform
	var half: float = front.leaf_size().x * 0.5
	var near := Geometry2D.get_closest_point_to_segment(
		arc.global_position, pose * Vector2(-half, 0.0), pose * Vector2(half, 0.0)
	)
	t.check(
		arc.global_position.distance_to(near) >= 12.5,
		"and the character is clear of the leaf (%.1f px)" % arc.global_position.distance_to(near),
	)


## The puppet that walked into the door has stopped at it, and the door stands shut.
func _walked_into(t: TestContext) -> void:
	var walked = t.object(&"walked")
	var at: float = t.actor(&"walker").global_position.x
	t.check(at < 395.0, "the walker is at the door (x %.0f)" % at)
	t.check(
		walked.angle() == 0.0,
		"walking into a door does not open it (angle %.0f)" % walked.angle(),
	)


## An ajar door is not latched: one kick from the push side throws a hollow, a solid and a steel
## door fully open; one from the pull side turns it toward shut and does not burst it.
func _ajar(t: TestContext) -> void:
	for id: StringName in [&"ajar_hollow", &"ajar_solid", &"ajar_steel"]:
		var door = t.object(id)
		t.check(
			is_equal_approx(door.angle(), 30.0),
			"premise: the %s door stands ajar at 30° (%.1f°)" % [id, door.angle()],
		)
		await _kick(t, id)
		t.check(
			await t.until(func(): return door.angle() >= 89.0, BURST),
			"one kick from the push side throws the %s fully open (%.0f°)" % [id, door.angle()],
		)
	var pulled = t.object(&"ajar_pull")
	await _kick(t, &"ajar_pull")
	t.check(
		pulled.angle() < 29.0,
		"one kick from the pull side turns an ajar door toward shut (%.1f°)" % pulled.angle(),
	)
	t.check(pulled.angle() > 10.0, "and does not burst it (%.1f°)" % pulled.angle())
	await _struck_twice(t)


## A second kick while the first has the door flying open does not throw it again: one burst, and
## the sound of one.
func _struck_twice(t: TestContext) -> void:
	var door = t.object(&"ajar_twice")
	var bursts := func(d: Dictionary) -> bool: return d["door"] == door and d["stage"] == &"burst"
	for _i in 2:
		door.apply_impulse(Vector2.RIGHT * KICK_IMPULSE)
		door.take_blow(&"kick", 14.0, Vector2.RIGHT * KICK_IMPULSE)
		await t.frames(3)
	await t.seconds(BURST)
	t.check(door.angle() >= 89.0, "two kicks in a moment leave the ajar door fully open")
	t.expect_eq(t.events_of(&"door", bursts).size(), 1, "and it burst once")


## One kick (or punch) by `id`'s kicker, then the wait for the next; it must land on the door.
func _kick(t: TestContext, id: StringName, with_foot := true) -> void:
	var door = t.object(id)
	var landed := func(d: Dictionary) -> bool: return d["body"] == door and d["hand"] >= 0
	var before := t.events_of(&"hit_landed", landed).size()
	if with_foot:
		t.puppet(StringName("%s_kicker" % id)).kick()
	else:
		t.puppet(StringName("%s_kicker" % id)).punch()
	t.require(
		await t.until(func(): return t.events_of(&"hit_landed", landed).size() > before, 1.0),
		"the %s kicker's kick lands on its door" % id,
	)
	await t.seconds(BETWEEN)
