extends GameTest
## A gun's spread scatters a shot up and down as well as sideways (D8). An SMG of 12 degrees of
## spread fires from its standing muzzle (65 px) at a long low table (31 px), aimed at 22 px up
## on it: some rounds strike the table, some fly high over it and strike the wardrobe behind it,
## some go low into the floor. With the vertical scatter turned off
## (`BallisticsFlightConfig.vertical_spread_scale` 0) every round strikes the table, a table long
## enough that the sideways spread never misses it.

const SHOOT_AT := Vector2(120, 250)
const TABLE_AT := Vector2(400, 250)
const SPREAD_DEG := 12.0
const AIM_HEIGHT := 22.0
const BACKSTOP_AT := Vector2(520, 250)


func describe() -> Dictionary:
	return {
		"name": "Vertical spread can miss high and low",
		"description": "A burst at a long low table with the vertical scatter on strikes the "
			+ "table with some rounds only, the rest over it onto the wardrobe or into the floor; "
			+ "with it off every round strikes the table.",
		"tags": ["projectile", "spread", "aim", "ballistics"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.set_static(BloodConfig, &"enabled", false)
	s.set_static(BallisticsPenetrationConfig, &"min_speed", 1.0e9)
	s.set_static(BallisticsFlightConfig, &"vertical_spread_scale", 1.0)  # restored after the test
	var guns: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in guns:
		guns[gun]["spread_deg"] = SPREAD_DEG
		guns[gun]["fire_interval"] = 0.05
	s.set_static(GunConfig, &"guns", guns)
	var table := WorldGen.object_definition("table").duplicate()
	table["size"] = Vector2(40, 460)
	table["anchored"] = true  # the rounds do not push it off its line
	s.object(&"table", table, TABLE_AT)
	var backstop := WorldGen.object_definition("wardrobe").duplicate()
	backstop["size"] = Vector2(40, 460)
	backstop["anchored"] = true
	s.object(&"backstop", backstop, BACKSTOP_AT)
	s.actor(&"shooter", &"puppet", SHOOT_AT, { "start_slot": 5 })


func run(t: TestContext) -> void:
	var puppet := t.puppet(&"shooter")
	puppet.aim_at(TABLE_AT, AIM_HEIGHT)
	await t.seconds(0.5)

	await _burst(t)
	var rounds := _shots(t)
	var table := _hits(t, t.object(&"table"))
	var over := _backstop_hits(t)
	t.check(rounds >= 10, "the burst fired a good many rounds (%d)" % rounds)
	t.check(table > 0 and table < rounds, "only some strike the table (%d of %d)" % [table, rounds])
	t.check(over > 0, "some fly high over it onto the wardrobe behind (%d)" % over)
	t.check(table + over < rounds, "and some go low into the floor (%d + %d of %d)"
			% [table, over, rounds])

	BallisticsFlightConfig.vertical_spread_scale = 0.0
	var before := _hits(t, t.object(&"table"))
	var over_before := _backstop_hits(t)
	var shot_before := _shots(t)
	await _burst(t)
	var flat_rounds := _shots(t) - shot_before
	t.check(flat_rounds >= 10, "a second burst fired (%d)" % flat_rounds)
	t.expect_eq(_hits(t, t.object(&"table")) - before, flat_rounds,
			"with no vertical scatter every round strikes the table")
	t.expect_eq(_backstop_hits(t), over_before, "and none flies over it")


## Hold the trigger for 0.9 s (a magazine holds 32), let go and let the rounds land.
func _burst(t: TestContext) -> void:
	var puppet := t.puppet(&"shooter")
	puppet.hold_fire(true)
	await t.seconds(0.9)
	puppet.hold_fire(false)
	await t.seconds(1.0)


func _shots(t: TestContext) -> int:
	return t.events_of(&"shot").size()


func _backstop_hits(t: TestContext) -> int:
	return _hits(t, t.object(&"backstop"))


func _hits(t: TestContext, victim: Node) -> int:
	return t.events_of(&"hit", func(d): return d["victim"] == victim).size()
