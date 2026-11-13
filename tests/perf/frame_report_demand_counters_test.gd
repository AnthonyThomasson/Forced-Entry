extends GameTest
## The worst-frames report's lazy-build counters (`tests/_perf/frame_report.gd`, `perf.md`) on a
## live NPC: a decision's snapshot builds its option groups and the `grenade_ready` search when the
## walk first reads them (`SnapshotDemand`), and the frame that read them counts each by name
## (`demand:leads`, `demand:entries`, `demand:grenade_ready`), once: reading it again builds
## nothing and counts nothing.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const NPC := Vector2(900, 190)
## The measured frame the groups are read in.
const READ_AT := 4


func describe() -> Dictionary:
	return {
		"name": "The worst-frames report counts the lazy groups a decision builds",
		"description": "A snapshot's leads, entries and grenade_ready fact read in one measured "
			+ "frame are counted by name in it, once; reading them again counts nothing.",
		"tags": ["ai", "snapshot", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([])
	s.switch(&"ai.callouts", false)
	s.actor(&"npc", &"invader", NPC, { "movement:speed": 0.0, "facing": Vector2.LEFT })


func run(t: TestContext) -> void:
	await t.frames(3)
	var brain := t.controller(&"npc", &"debug_state")
	var perception: Node = brain.get("_perception")
	var snap: Dictionary = perception.sense(brain.get("goal"), "", 0)
	var demand: RefCounted = snap["demand"]
	if not t.require((demand.built as Array).is_empty(), "premise: nothing is built yet"):
		return
	var logging := GameLog.enabled
	GameLog.enabled = true
	var stats := await Perf.frame_stats(
		t, 10, func(i: int) -> void:
			if i == READ_AT:
				demand.group("leads")
				demand.group("entries")
				demand.fact("grenade_ready")
			if i == READ_AT + 3:
				demand.group("leads")  # built: no new build
				demand.fact("grenade_ready")
	)
	GameLog.enabled = logging
	# The NPC's own decisions build groups too (of other snapshots): the frames of the reads here
	# are checked, a call at the start of frame `i` being in the rise read before it, `ran[i - 1]`.
	var ran: Array = stats["ran"]
	for key in ["demand:leads", "demand:entries", "demand:grenade_ready"]:
		t.expect_eq(
			(ran[READ_AT - 1] as Dictionary).get(key, 0), 1,
			"%s: one build, counted in the frame it was built in" % key,
		)
		t.expect_eq(
			(ran[READ_AT + 2] as Dictionary).get(key, 0), 0,
			"%s: reading it again builds and counts nothing" % key,
		)
	t.check(
		(demand.built as Array).has("leads") and (demand.built as Array).has("entries"),
		"premise: the snapshot built the groups it was asked for (%s)" % str(demand.built),
	)
