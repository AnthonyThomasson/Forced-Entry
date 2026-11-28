extends GameTest
## A held avoid bake whose asker asks every beat while it wants the map (`avoid_map`'s `repeats`:
## a hold's body maps) is dropped when its turn comes if nobody has asked for it in the last few
## frames, and a later ask bakes it then (`domain-navigation` `rebake.md`, "A bake waits its
## turn"). With one bake at a time: `first` bakes; `left` (asked once), `kept` (asked every second
## frame, the NPC's beat) and `once` (not a repeating asker) are held.

const ARENA := Rect2(0, 0, 900, 500)
const WAIT := 12


func describe() -> Dictionary:
	return {
		"name": "A held bake nobody asks for any more is not baked",
		"description": "Of three held avoid maps the one a repeating asker left is never baked "
			+ "until asked again; the one asked every beat and the plain one land in turn.",
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
	var maps := {}
	var regions := {}
	for key: String in ["first", "left", "kept", "once"]:
		maps[key] = NavBuilder.avoid_map(region, key, _holes(), key == "left" or key == "kept")
		regions[key] = _newest(region)
	var landed := {}
	for frame in WAIT * 5:
		if frame % 2 == 0 and not landed.has("kept"):
			NavBuilder.avoid_map(region, "kept", _holes(), true)
		await t.frames(1)
		for key: String in regions:
			if not landed.has(key) and NavPlan.polygon_of(regions[key]) != null:
				landed[key] = GameClock.frame() - start
	t.check(not landed.has("left"), "the map nobody asks for any more is not baked (%s)" % landed)
	t.check(not NavBuilder.ready(maps["left"]), "and answers nothing")
	t.expect_eq(NavBake.started_total - started_before, 3, "bakes started")
	if not t.require(
			landed.has("kept") and landed.has("once"),
			"the others land (%s)" % str(landed),
	):
		return
	t.check(
		landed["kept"] == landed["first"] + WAIT and landed["once"] == landed["kept"] + WAIT,
		"one after another, each its count after its turn came (%s)" % str(landed),
	)
	# Asked again: it bakes then, like a first ask.
	var asked := GameClock.frame()
	NavBuilder.avoid_map(region, "left", _holes(), true)
	var back := -1
	for _frame in WAIT * 2:
		await t.frames(1)
		if NavPlan.polygon_of(regions["left"]) != null:
			back = GameClock.frame() - asked
			break
	t.expect_eq(back, WAIT, "asked again it lands its count after the ask")
	t.check(
		await t.until(func(): return NavBuilder.ready(maps["left"]), 2.0),
		"and answers queries",
	)


func _holes() -> Array:
	return [PackedVector2Array([
		Vector2(400, 100), Vector2(440, 100), Vector2(440, 400), Vector2(400, 400),
	])]


## The avoid region added last under `region`.
func _newest(region: NavigationRegion3D) -> NavigationRegion3D:
	return region.get_child(region.get_child_count() - 1) as NavigationRegion3D
