extends GameTest
## Rounds go by material and thickness (#194, D20, `docs/stacked-items.md`): a pistol round
## through a plate on a stack of crates goes through it (a plate is thin ceramic) and knocks it
## off; the same round at a crate loses most of its speed in it and is stopped by the crate behind,
## so the target behind them is unhurt.

const PLATE_ROW := 120.0
const CRATE_ROW := 340.0
const SHOOTER_X := 100.0
const AT_X := 400.0
## Where a plate rests on two crates (32 px) and how high the round meets it.
const PLATE_HEIGHT := 32.8


func describe() -> Dictionary:
	return {
		"name": "A round passes a plate and is stopped by a crate",
		"description": "A level-ish pistol round at a plate on two crates penetrates it and knocks "
			+ "it off the stack; at a crate (wood, 20 px) with a second crate behind it, it "
			+ "penetrates the first, loses its speed and is blocked by the second, and the "
			+ "puppet behind is not wounded.",
		"tags": ["items", "stacking", "bullets", "penetration", "projectile"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
	s.set_static(GunConfig, "guns", straight)
	s.actor(&"plate_gun", &"puppet", Vector2(SHOOTER_X, PLATE_ROW), { "start_slot": 3 })
	s.actor(&"crate_gun", &"puppet", Vector2(SHOOTER_X, CRATE_ROW), { "start_slot": 3 })
	s.object(&"stand", "crate", Vector2(AT_X, PLATE_ROW))
	s.object(&"stand_top", "crate", Vector2.ZERO, { "on": &"stand" })
	s.object(&"plate", "plate", Vector2.ZERO, { "on": &"stand_top" })
	s.object(&"first", "crate", Vector2(AT_X, CRATE_ROW))
	s.object(&"second", "crate", Vector2(AT_X + 21.0, CRATE_ROW))
	s.actor(&"target", &"puppet", Vector2(AT_X + 80.0, CRATE_ROW), { "max_health": 400.0 })
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.seconds(1.0)
	var plate_at: Vector2 = t.object(&"plate").global_position
	t.puppet(&"plate_gun").aim_at(plate_at, PLATE_HEIGHT)
	t.puppet(&"crate_gun").aim_at(Vector2(AT_X, CRATE_ROW), 9.0)
	await t.seconds(0.6)
	t.puppet(&"plate_gun").shoot()
	await t.seconds(0.5)
	var on_plate := t.events_of(&"hit", func(d): return d["victim"] == t.object(&"plate"))
	t.check(not on_plate.is_empty(), "the round hit the plate")
	if not on_plate.is_empty():
		t.check(
			on_plate[0]["outcome"] == &"penetrate",
			"and went through it (%s)" % on_plate[0]["outcome"],
		)
	t.check(
		t.object(&"plate").global_position.distance_to(plate_at) > 3.0
			or _plate_height(t) < PLATE_HEIGHT - 5.0,
		"the plate was knocked off its place",
	)
	for i in 3:
		t.puppet(&"crate_gun").shoot()
		await t.seconds(0.4)
	var first := t.events_of(&"hit", func(d): return d["victim"] == t.object(&"first"))
	var second := t.events_of(&"hit", func(d): return d["victim"] == t.object(&"second"))
	t.check(
		first.any(func(d): return d["outcome"] == &"penetrate"),
		"a round went through the first crate (%d hits)" % first.size(),
	)
	t.check(
		second.any(func(d): return d["outcome"] == &"blocked"),
		"and was stopped by the second (%d hits)" % second.size(),
	)
	t.check(
		t.actor(&"target").health == t.actor(&"target").max_health,
		"the puppet behind the crates is unhurt",
	)


## How high (px) the plate's body stands now.
func _plate_height(t: TestContext) -> float:
	return TwinSpace.twin_for(t.object(&"plate")).global_position.y / RenderConfig.unit
