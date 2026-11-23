extends GameTest
## A district's planning ring (`NavRing`, a small map of the match building, 14 ms of thread) is
## not queued behind the district's big bakes: it is a high-priority task, so a pool whose normal
## threads are all busy (a match's avoid bakes and planning bake, 100 to 140 ms each, run three
## at once, the pool's share of threads for normal tasks) still runs it, and it is on its thread
## done by its landing frame. Queued, it was 46 ms late in the grenade match guard and the frame
## that landed it was held for the wait (67 ms against a budget of 37).

## Sleepers: more than a pool has threads for normal tasks, so none is free for a queued bake.
const SLEEPERS := 24
const SLEEP_MS := 700
const RING_FRAMES := 30


func describe() -> Dictionary:
	return {
		"name": "A planning ring bake is not queued behind a busy pool",
		"description": "With every normal-priority pool thread asleep, the ring's bake still runs: "
			+ "it lands on its frame without waiting for its thread.",
		"tags": ["navigation", "bake", "ring", "district"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.district(7)
	s.switch(&"nav.rebake", false)
	s.set_static(NavBakeConfig, &"district_frames", 60)
	s.set_static(NavBakeConfig, &"ring_frames", RING_FRAMES)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var district: Node2D = t.world.district
	var rooms := WorldGen.district_rooms(district)
	var region: NavigationRegion2D = t.world.find_children(
		"NavRegion", "NavigationRegion2D", true, false,
	)[0]
	var sleepers: Array[int] = []
	for _i in SLEEPERS:
		sleepers.append(WorkerThreadPool.add_task(func() -> void: OS.delay_msec(SLEEP_MS)))
	var bakes := NavBuilder.rebake_async(region, district, rooms, NavBuilder.AGENT_RADIUS)
	if not t.require(
		bakes.size() == 2,
		"the district re-bakes with its ring (%d bakes)" % bakes.size(),
	):
		return
	var landed_before := NavBake.landed_total
	var started := Time.get_ticks_msec()
	for _frame in RING_FRAMES + 2:
		await t.frames(1)
	var waited := Time.get_ticks_msec() - started
	t.expect_eq(
		NavBake.landed_total - landed_before,
		1,
		"the ring's bake landed, the district's not yet",
	)
	t.check(not bakes[1].was_late, "the ring's thread ran past a pool of sleepers, in time")
	t.check(waited < SLEEP_MS * 0.5, "no frame waited for a sleeper (%d ms)" % waited)
	for task in sleepers:
		WorkerThreadPool.wait_for_task_completion(task)
