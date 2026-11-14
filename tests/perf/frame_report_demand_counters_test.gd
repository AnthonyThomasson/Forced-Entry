extends GameTest
## The worst-frames report's lazy-build counters (`tests/_perf/frame_report.gd`, `perf.md`) on a
## live NPC: a decision's snapshot builds its option groups, a hostile's grenade throws and the
## `lead_outside` and `grenade_ready` facts when the walk first reads them (`SnapshotDemand`), and
## the frame that read them counts each by name (`demand:leads`, `demand:entries`,
## `demand:search_rooms`, `demand:target_throws`, `demand:lead_outside`,
## `demand:grenade_ready`), once: reading it again builds nothing and counts nothing.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const NPC := Vector2(150, 250)
const HOSTILE := Vector2(400, 100)
## The measured frame the builds are read in, and the one that reads them again.
const READ_AT := 4
const AGAIN_AT := 7
## What the frame reads, by the name the report counts it under.
const BUILDS := [
	"demand:leads", "demand:entries", "demand:search_rooms", "demand:target_throws",
	"demand:lead_outside", "demand:grenade_ready",
]


func describe() -> Dictionary:
	return {
		"name": "The worst-frames report counts the lazy groups a decision builds",
		"description": "A snapshot's leads, entries and search_rooms groups, a hostile's throws "
			+ "and the lead_outside and grenade_ready facts read in one measured frame are "
			+ "counted by name in it, once; reading them again counts nothing.",
		"tags": ["ai", "snapshot", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 400))
	s.von_script([])
	s.switch(&"ai.callouts", false)
	s.actor(&"d", &"defender", NPC, { "movement:speed": 0.0, "facing": Vector2.RIGHT })
	s.actor(&"h", &"puppet", HOSTILE, { "faction": &"invader", "max_health": 1_000_000.0 })


func run(t: TestContext) -> void:
	var brain := t.controller(&"d", &"debug_state")
	var seen := func() -> bool: return (
		(brain.debug_state().get("contacts", []) as Array).any(
			func(c): return c.get("hostile", false)
		)
	)
	if not t.require(await t.until(seen, 3.0), "set-up: the defender sees the hostile"):
		return
	var id: int = t.actor(&"h").get_instance_id()
	var perception: Node = brain.get("_perception")
	var demand: RefCounted = perception.sense(brain.get("goal"), "", id)["demand"]
	if not t.require(
		(demand.built as Array).is_empty() and demand.targets.has(id),
		"premise: nothing is built yet and the hostile is analysed",
	):
		return
	var logging := GameLog.enabled
	GameLog.enabled = true
	var stats := await Perf.frame_stats(
		t, 10, func(i: int) -> void:
			if i == READ_AT or i == AGAIN_AT:
				_read(demand, id)
	)
	GameLog.enabled = logging
	# The NPC's own decisions build groups too (of other snapshots): the frames of the reads here
	# are checked, a call at the start of frame `i` being in the rise read before it, `ran[i - 1]`.
	var ran: Array = stats["ran"]
	for key: String in BUILDS:
		t.expect_eq(
			(ran[READ_AT - 1] as Dictionary).get(key, 0), 1,
			"%s: one build, counted in the frame it was built in" % key,
		)
		t.expect_eq(
			(ran[AGAIN_AT - 1] as Dictionary).get(key, 0), 0,
			"%s: reading it again builds and counts nothing" % key,
		)


## Read the groups and facts the counters name.
func _read(demand: RefCounted, target: int) -> void:
	demand.group("leads")
	demand.group("entries")
	demand.group("search_rooms")
	demand.target_group("grenade_throws", target)
	demand.fact("lead_outside")
	demand.fact("grenade_ready")
