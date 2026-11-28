extends GameTest
## The planning ring's bake (`urgent`) waits for no turn (`domain-navigation` `rebake.md`, "A bake
## waits its turn"). With one place and an avoid map in it, a district re-bake's planning bake is
## held while its ring starts at the ask and lands `NavBakeConfig.ring_frames` on; `done` waits for
## the held planning bake, which starts when the avoid map lands.

const RING_FRAMES := 10
const AVOID_FRAMES := 20
const DISTRICT_FRAMES := 15


func describe() -> Dictionary:
	return {
		"name": "A planning ring bake waits for no turn",
		"description": "With the one place taken by an avoid map, a district re-bake's ring lands "
			+ "on its own count while the planning bake waits, and done waits for both.",
		"tags": ["navigation", "bake", "ring", "district"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.district(7)
	s.switch(&"nav.rebake", false)
	s.set_static(NavBakeConfig, &"at_once", 1)
	s.set_static(NavBakeConfig, &"ring_frames", RING_FRAMES)
	s.set_static(NavBakeConfig, &"avoid_frames", AVOID_FRAMES)
	s.set_static(NavBakeConfig, &"district_frames", DISTRICT_FRAMES)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var district: Node2D = t.world.district
	var rooms := WorldGen.district_rooms(district)
	var region: NavigationRegion3D = t.world.find_children(
		"NavRegion", "NavigationRegion3D", true, false,
	)[0]
	var ring := NavRing.region_of(region)
	if not t.require(ring != null, "premise: the district has a planning ring"):
		return
	var started_before := NavBake.started_total
	var start := GameClock.frame()
	NavBuilder.avoid_map(region, "taken", [_hole(district.position)])
	var avoid := region.get_child(region.get_child_count() - 1) as NavigationRegion3D
	var done := [-1]  # a lambda captures an int by value
	var bakes := NavBuilder.rebake_async(
		region, district, rooms, NavBuilder.AGENT_RADIUS,
		func() -> void: done[0] = GameClock.frame() - start,
	)
	if not t.require(bakes.size() == 2, "the district re-bakes with its ring"):
		return
	t.expect_eq(
		NavBake.started_total - started_before,
		2,
		"started at the ask (the avoid map and the ring, not the planning bake)",
	)
	var landed := await _landings(t, { "avoid": avoid, "ring": ring, "planning": region }, start)
	if not t.require(landed.size() == 3 and done[0] >= 0, "all three land (%s)" % str(landed)):
		return
	t.expect_eq(landed["ring"], RING_FRAMES, "the ring lands its count after the ask")
	t.expect_eq(landed["avoid"], AVOID_FRAMES, "the avoid map lands its count after the ask")
	t.expect_eq(
		landed["planning"],
		AVOID_FRAMES + DISTRICT_FRAMES,
		"the planning bake waits for the avoid map's place",
	)
	t.expect_eq(done[0], landed["planning"], "done waits for the planning bake")


## The frame (counted from `start`) each of `regions` (name -> region) took its new polygon in.
func _landings(t: TestContext, regions: Dictionary, start: int) -> Dictionary:
	var held := {}
	for key: String in regions:
		held[key] = NavPlan.polygon_of(regions[key])
	var landed := {}
	for _frame in AVOID_FRAMES + DISTRICT_FRAMES + 5:
		await t.frames(1)
		for key: String in regions:
			if not landed.has(key) and NavPlan.polygon_of(regions[key]) != held[key]:
				landed[key] = GameClock.frame() - start
	return landed


## A strip of floor at the district's `origin` for the avoid map to carve.
func _hole(origin: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		origin + Vector2(100, 100), origin + Vector2(130, 100),
		origin + Vector2(130, 130), origin + Vector2(100, 130),
	])
