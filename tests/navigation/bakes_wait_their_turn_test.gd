extends GameTest
## No more than `NavBakeConfig.at_once` background bakes are between their start and their landing
## (`domain-navigation` `rebake.md`, "A bake waits its turn"): one asked past that is held, not
## started, until one of them lands, and its landing frame is counted from that start. Here eight
## avoid maps are asked two a frame with three at once: the first three land `WAIT` frames after
## their asks (one landing a frame), and each later one `WAIT` frames after the landing that freed
## its place, the oldest first, so none waits longer than its turn. A bake whose region was freed
## holds no place.

const ARENA := Rect2(0, 0, 900, 500)
const AT_ONCE := 3
const WAIT := 12
const ASKED := 8


func describe() -> Dictionary:
	return {
		"name": "A bake past the third in flight waits its turn",
		"description": "Eight avoid maps asked two a frame: at most three are baking, each held "
			+ "one starts when the oldest lands and lands its full count later, in order.",
		"tags": ["navigation", "bake", "avoid"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(ARENA)
	s.switch(&"nav.rebake", false)
	s.set_static(NavBakeConfig, &"at_once", AT_ONCE)
	s.set_static(NavBakeConfig, &"house_frames", WAIT)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var region := NavBuilder.planning_region(NavWorld.map_of(t.world))
	if not t.require(region != null, "the planning region is found from the world's map"):
		return
	var landed := await _ask_two_a_frame(t, region)
	_check_turns(t, landed)
	await _a_freed_region_holds_no_place(t, region)


## `ASKED` avoid maps asked two a frame: the frame each landed on and the frame each was asked on
## (counted from the first ask), as `[landed, asked]`; `[]` when one never landed or answers
## nothing. Checks that no more than `AT_ONCE` were baking at once.
func _ask_two_a_frame(t: TestContext, region: NavigationRegion3D) -> Array:
	var before := NavBake.started_total - NavBake.landed_total
	var regions: Array[NavigationRegion3D] = []
	var maps: Array[RID] = []
	var asked: Array[int] = []
	var landed: Array[int] = []
	landed.resize(ASKED)
	landed.fill(-1)
	var start := GameClock.frame()
	var most := 0
	for frame in WAIT * 6:
		while regions.size() < mini(ASKED, (frame + 1) * 2):
			var i := regions.size()
			maps.append(NavBuilder.avoid_map(region, "turn%d" % i, [_hole(i)]))
			regions.append(_newest(region))
			asked.append(GameClock.frame() - start)
		most = maxi(most, NavBake.started_total - NavBake.landed_total - before)
		await t.frames(1)
		for i in regions.size():
			if landed[i] < 0 and NavPlan.polygon_of(regions[i]) != null:
				landed[i] = GameClock.frame() - start
	if not t.require(not landed.has(-1), "every bake landed (frames %s)" % str(landed)):
		return []
	t.expect_eq(most, AT_ONCE, "no more than %d bakes were baking at once" % AT_ONCE)
	for i in ASKED:
		t.check(
			await t.until(func(): return NavBuilder.ready(maps[i]), 2.0),
			"map %d answers queries" % i,
		)
	return [landed, asked]


## The landing frames of `_ask_two_a_frame` (`ran`): the first `AT_ONCE` on their own counts, each
## later one its count after the landing that freed its place.
func _check_turns(t: TestContext, ran: Array) -> void:
	if ran.is_empty():
		return
	var landed: Array[int] = ran[0]
	var asked: Array[int] = ran[1]
	t.check(
		landed[0] == WAIT and landed[1] == WAIT + 1 and landed[2] == WAIT + 2,
		"the first three land on their own counts, one a frame (%s)" % str(landed),
	)
	for i in range(AT_ONCE, ASKED):
		t.check(
			landed[i] == landed[i - AT_ONCE] + WAIT,
			"bake %d starts when bake %d lands and lands %d frames later (%s)"
				% [i, i - AT_ONCE, WAIT, str(landed)],
		)
		var turns := floori(i / float(AT_ONCE)) + 1
		t.check(
			landed[i] - asked[i] <= turns * (WAIT + AT_ONCE),
			"bake %d lands within its turn's bound (%d frames after its ask)"
				% [i, landed[i] - asked[i]],
		)


## Three bakes in flight, their regions then freed: a fourth asked after starts at once.
func _a_freed_region_holds_no_place(t: TestContext, region: NavigationRegion3D) -> void:
	for i in AT_ONCE:
		NavBuilder.avoid_map(region, "freed%d" % i, [_hole(i)])
		_newest(region).queue_free()
		await t.frames(1)
	var asked := GameClock.frame()
	NavBuilder.avoid_map(region, "after", [_hole(4)])
	var after := _newest(region)
	var landed := -1
	for _frame in WAIT * 3:
		await t.frames(1)
		if NavPlan.polygon_of(after) != null:
			landed = GameClock.frame() - asked
			break
	t.check(
		landed >= WAIT and landed <= WAIT + AT_ONCE,
		"it waits for none of the freed ones (landed %d frames after its ask)" % landed,
	)


func _hole(i: int) -> PackedVector2Array:
	var x := 60.0 + 90.0 * i
	return PackedVector2Array([
		Vector2(x, 100), Vector2(x + 30, 100), Vector2(x + 30, 400), Vector2(x, 400),
	])


## The avoid region added last under `region`.
func _newest(region: NavigationRegion3D) -> NavigationRegion3D:
	return region.get_child(region.get_child_count() - 1) as NavigationRegion3D
