extends GameTest
## A burst of district-sized bakes never holds a frame for a thread (`domain-navigation`
## `rebake.md`, "A bake waits its turn"). `ASKED` avoid maps are asked within three frames and
## every frame is then stretched by `FRAME_MS`, so a bake's count is at least `COUNT * FRAME_MS`
## (480 ms) of wall time, about four of its threads. Started all at once, the pool ran them three
## at a time and, landing one a frame, the later ones were still queued or baking when their frame
## came, which held that frame for the rest; with no more in flight than the pool runs, each has a
## thread from its start. The places are the pool's width where that is under the game's 3 (a
## machine under 10 threads, `rebake.md`'s limit).

const ASKED := 36
const PER_FRAME := 12
const COUNT := 60
const FRAME_MS := 8
## The pool's share of its threads for normal-priority tasks (the project's default).
const POOL_SHARE := 0.3


func describe() -> Dictionary:
	return {
		"name": "A burst of district bakes lands none late",
		"description": "Thirty-six district avoid maps asked in three frames: every one lands, "
			+ "and no frame waited for a bake's thread.",
		"tags": ["navigation", "bake", "avoid", "district"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.district(7)
	s.switch(&"nav.rebake", false)
	s.set_static(NavBakeConfig, &"avoid_frames", COUNT)
	var width := clampi(int(OS.get_processor_count() * POOL_SHARE), 1, 3)
	s.set_static(NavBakeConfig, &"at_once", width)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var region := NavBuilder.planning_region(NavWorld.map_of(t.world))
	if not t.require(region != null, "the planning region is found from the world's map"):
		return
	var late_before := NavBake.late_total
	var maps: Array[RID] = []
	var at := (t.rooms[0]["rect"] as Rect2).get_center()
	for _frame in COUNT * (ceili(ASKED / 3.0) + 3):
		for _i in PER_FRAME:
			if maps.size() == ASKED:
				break
			var corner := at + Vector2(maps.size() * 12, 0)
			var hole := PackedVector2Array([
				corner, corner + Vector2(8, 0), corner + Vector2(8, 8), corner + Vector2(0, 8),
			])
			maps.append(NavBuilder.avoid_map(region, "crowd%d" % maps.size(), [hole]))
		OS.delay_msec(FRAME_MS)
		await t.frames(1)
		if maps.size() == ASKED and maps.all(func(m: RID) -> bool: return NavBuilder.ready(m)):
			break
	t.check(
		maps.all(func(m: RID) -> bool: return NavBuilder.ready(m)),
		"every one of the %d maps landed and answers" % ASKED,
	)
	t.expect_eq(NavBake.late_total - late_before, 0, "bakes whose frame waited for the thread")
