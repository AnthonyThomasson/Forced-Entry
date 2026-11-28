extends GameTest
## A heard lead's remembered walk (`SnapshotLeadMemo`) is dropped when the planning ring is
## re-baked, as it is when the district's own map is: the walk may have been answered by the ring,
## so either map moving on starts the memo afresh. The ring's region is handed its polygon again
## (the ring map's iteration moves, the district map's does not), and the memo kept for the old
## iteration answers nothing.

const SnapshotLeadMemo = preload("res://scenes/ai/perception/snapshot/snapshot_lead_memo.gd")
const WINDOW_S := 60.0
## How long (sim s) the ring map may take to take the polygon in.
const WAIT := 12.0
const FROM := Vector2(100, 100)
const TO := Vector2(200, 200)


func describe() -> Dictionary:
	return {
		"name": "The lead-walk memo follows a ring re-bake",
		"description": "A walk kept by the lead memo is gone once the planning ring's map "
			+ "has a new iteration, though the district map's is the same.",
		"tags": ["ai", "perception", "snapshot", "navigation", "district"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.district(7)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var region: NavigationRegion3D = t.world.find_children(
		"NavRegion", "NavigationRegion3D", true, false,
	)[0]
	var map := region.get_navigation_map()
	var ring_region := NavRing.region_of(region)
	if not t.require(ring_region != null and NavBuilder.ready(map), "premise: the ring is baked"):
		return
	var memo := SnapshotLeadMemo.new()
	memo.open(map, 0, WINDOW_S)
	memo.keep(FROM, TO, { "len": 5.0, "snap": TO })
	memo.open(map, 0, WINDOW_S)
	if not t.require(
		memo.recall(FROM, TO) != null,
		"premise: the walk is kept while nothing moves",
	):
		return
	var district := NavPlan.iteration(map)
	var ring_map := NavRing.map_of(map)
	var ring := NavPlan.iteration(ring_map)
	NavPlan.assign(ring_region, NavPlan.polygon_of(ring_region).duplicate())
	if not t.require(
		await t.until(
			func() -> bool: return NavPlan.iteration(ring_map) != ring, WAIT,
		),
		"premise: the ring map took the polygon in",
	):
		return
	t.require(
		NavPlan.iteration(map) == district,
		"premise: the district map did not move",
	)
	memo.open(map, 0, WINDOW_S)
	t.check(memo.recall(FROM, TO) == null, "the ring's re-bake dropped the kept walk")
