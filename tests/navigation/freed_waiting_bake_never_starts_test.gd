extends GameTest
## A waiting bake whose region is freed is never started (`domain-navigation` `rebake.md`, "A bake
## waits its turn"): nothing carries over from a torn-down world. With one place, `first` bakes and
## `freed` waits; its region is freed and `third` asked: only `first` and `third` are ever started.

const ARENA := Rect2(0, 0, 900, 500)
const WAIT := 12


func describe() -> Dictionary:
	return {
		"name": "A waiting bake whose region is freed never starts",
		"description": "One place: the second of three avoid maps has its region freed while it "
			+ "waits, so two bakes are started and the third lands after the first.",
		"tags": ["navigation", "bake", "avoid"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(ARENA)
	s.switch(&"nav.rebake", false)
	s.set_static(NavBakeConfig, &"at_once", 1)
	s.set_static(NavBakeConfig, &"house_frames", WAIT)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var region := NavBuilder.planning_region(NavWorld.map_of(t.world))
	if not t.require(region != null, "the planning region is found from the world's map"):
		return
	var started_before := NavBake.started_total
	var start := GameClock.frame()
	NavBuilder.avoid_map(region, "first", [_hole(0)])
	var first := _newest(region)
	NavBuilder.avoid_map(region, "freed", [_hole(1)])
	var freed := _newest(region)
	t.expect_eq(NavBake.started_total - started_before, 1, "the second one waits")
	freed.queue_free()
	await t.frames(1)
	NavBuilder.avoid_map(region, "third", [_hole(2)])
	var third := _newest(region)
	var landed := {}
	for _frame in WAIT * 4:
		await t.frames(1)
		var frame := GameClock.frame() - start
		if not landed.has("first") and NavPlan.polygon_of(first) != null:
			landed["first"] = frame
		if not landed.has("third") and NavPlan.polygon_of(third) != null:
			landed["third"] = frame
	t.expect_eq(NavBake.started_total - started_before, 2, "bakes started: the first and third")
	if not t.require(landed.size() == 2, "the first and third land (%s)" % str(landed)):
		return
	t.expect_eq(landed["third"], landed["first"] + WAIT, "the third starts when the first lands")


func _hole(i: int) -> PackedVector2Array:
	var x := 100.0 + 200.0 * i
	return PackedVector2Array([
		Vector2(x, 100), Vector2(x + 40, 100), Vector2(x + 40, 400), Vector2(x, 400),
	])


## The avoid region added last under `region`.
func _newest(region: NavigationRegion3D) -> NavigationRegion3D:
	return region.get_child(region.get_child_count() - 1) as NavigationRegion3D
