extends GameTest
## H1 (docs/cover-and-stance.md): a shot is a 3D ray from the muzzle. With the cursor on the floor
## (no body under it) it flies level at the muzzle's height, so it clears what stands lower than
## that and is stopped by what stands higher. Two lanes, a standing body behind a table (30 px,
## under the standing muzzle's 65) and one behind a wardrobe (taller than it): the level round
## flies over the table and strikes the body behind it, and is stopped by the wardrobe.

const LANES := { &"table": 150.0, &"wardrobe": 350.0 }
const SHOOT_X := 120.0
const COVER_X := 400.0
const BODY_X := 520.0


func describe() -> Dictionary:
	return {
		"name": "A level shot flies over a table but not a wardrobe",
		"description": "A pistol round aimed level at the muzzle's height down two lanes: over "
			+ "the table it strikes the standing body behind; the wardrobe stops it before the "
			+ "body.",
		"tags": ["projectile", "cover", "ballistics", "aim"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.set_static(BloodConfig, &"enabled", false)
	# Nothing is punched through: what a round meets is what stops it.
	s.set_static(BallisticsPenetrationConfig, &"min_speed", 1.0e9)
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
	s.set_static(GunConfig, &"guns", straight)
	for lane: StringName in LANES:
		var y: float = LANES[lane]
		s.actor(StringName("shooter_%s" % lane), &"puppet", Vector2(SHOOT_X, y),
				{ "start_slot": 3 })
		s.object(StringName("cover_%s" % lane), String(lane), Vector2(COVER_X, y))
		s.actor(StringName("body_%s" % lane), &"puppet", Vector2(BODY_X, y),
				{ "max_health": 1_000_000.0, "facing": Vector2.LEFT })


func run(t: TestContext) -> void:
	var muzzle := BodyHeights.muzzle(BodyHeights.STAND)
	var table_top := PieceHeights.top_of(WorldGen.object_definition("table"))
	var wardrobe_top := PieceHeights.top_of(WorldGen.object_definition("wardrobe"))
	t.require(table_top < muzzle, "premise: the table (%.0f px) is under the muzzle (%.0f)"
			% [table_top, muzzle])
	t.require(
		wardrobe_top > muzzle,
		"premise: the wardrobe (%.0f px) is over the muzzle" % wardrobe_top,
	)
	for lane: StringName in LANES:
		t.puppet(StringName("shooter_%s" % lane)).aim_at(
				Vector2(900, LANES[lane]), CharacterMovement.AIM_LEVEL)
	await t.seconds(0.5)
	for lane: StringName in LANES:
		t.puppet(StringName("shooter_%s" % lane)).shoot()
	await t.seconds(1.0)

	t.expect_eq(_hits(t, t.object(&"cover_table")), 0, "the level round never touches the table")
	t.expect_eq(_hits(t, t.actor(&"body_table")), 1, "it strikes the standing body behind it")
	t.expect_eq(_hits(t, t.object(&"cover_wardrobe")), 1, "the wardrobe stops it")
	t.expect_eq(_hits(t, t.actor(&"body_wardrobe")), 0, "so the body behind the wardrobe is spared")


func _hits(t: TestContext, victim: Node) -> int:
	return t.events_of(&"hit", func(d): return d["victim"] == victim).size()
