extends GameTest
## An NPC with no engaged contact analyses ONE hostile, the nearest (#194 perf-decide2, "cheaper
## decisions"): the second analysed hostile is for the NPC that is fighting one (its engaged
## contact keeps its slot and the nearest other takes the second, `analyses_engaged_and_nearest`).
## The one slot goes to the nearest hostile IN SIGHT: a remembered one that is nearer by its last
## known spot but out of sight does not take it from a farther one the NPC sees now.
## Four hostiles are in sight and none engaged: the build runs a start, one run of pieces for the
## nearest, the retreat spots and the finish; all four are still listed with their line.

const NPC := Vector2(150, 250)
## Nearest first, left to right.
const SPOTS := [Vector2(300, 100), Vector2(400, 100), Vector2(500, 100), Vector2(600, 100)]
## Behind the NPC, outside its cone.
const BEHIND := Vector2(20, 250)
const Piece := preload("res://scenes/ai/perception/snapshot/snapshot_build.gd").Piece


func describe() -> Dictionary:
	return {
		"name": "An NPC that is not engaged analyses one hostile",
		"description": "With four hostiles known and none engaged, the build runs one hostile's "
			+ "pieces (the nearest's); all four are listed with their line; the snapshot equals "
			+ "the one-shot build's.",
		"tags": ["ai", "decision", "snapshot", "scripted"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 400))
	s.von_script([{ "pick": "combat" }, { "pick": "engage" }, { "pick": "fire_here" }])
	s.switch(&"ai.callouts", false)
	s.actor(&"d", &"defender", NPC, { "movement:speed": 0.0, "facing": Vector2.RIGHT })
	for i in SPOTS.size():
		s.actor(
			StringName("h%d" % i), &"puppet", SPOTS[i],
			{ "faction": &"invader", "max_health": 1_000_000.0 },
		)


func run(t: TestContext) -> void:
	var brain := t.controller(&"d", &"debug_state")
	var seen := func() -> bool: return (
		(brain.debug_state().get("contacts", []) as Array).filter(
			func(c): return c.get("hostile", false)
		).size() == SPOTS.size()
	)
	if not t.require(await t.until(seen, 3.0), "set-up: the defender sees all four hostiles"):
		return
	var ids: Array = []
	for i in SPOTS.size():
		ids.append(t.actor(StringName("h%d" % i)).get_instance_id())
	var perception: Node = brain.get("_perception")
	var whole: Dictionary = perception.sense(brain.get("goal"), "", 0)
	var staged = perception.begin_sense(brain.get("goal"), "", 0)
	var kinds: Array = []
	while not staged.done():
		kinds.append(staged.next_piece())
		staged.step()
	var hostile := [Piece.HOSTILE, Piece.SPOTS, Piece.FLANKS, Piece.FLANKS, Piece.REST]
	t.expect_eq(
		kinds, [Piece.START] + hostile + [Piece.RETREAT, Piece.FINISH],
		"one run of pieces: the nearest hostile's",
	)
	for snap in [whole, staged.result()]:
		var who: Array = (snap["sections_per_target"] as Dictionary).keys()
		t.expect_eq(who, [ids[0]], "only the nearest hostile is analysed")
		var listed: Array = []
		for o in snap["options"]["hostiles"]["options"]:
			listed.append(o["bind"]["target_id"])
		t.expect_eq(listed, ids, "all four hostiles are listed, nearest first")
	_engaged_after_the_start(t, brain, ids)
	await _nearest_out_of_sight(t, brain, ids)


## The build's start fixes who is analysed: the NPC engaging another hostile after it (the
## behaviour's engaged contact) does not move the build's pieces or its snapshot.
func _engaged_after_the_start(t: TestContext, brain: Node, ids: Array) -> void:
	var perception: Node = brain.get("_perception")
	var staged = perception.begin_sense(brain.get("goal"), "", 0)
	staged.step()  # the START
	brain.get("_behavior").fight.engage_id = ids[3]
	while not staged.done():
		staged.step()
	brain.get("_behavior").fight.engage_id = 0
	t.expect_eq(
		(staged.result()["sections_per_target"] as Dictionary).keys(), [ids[0]],
		"engaging the farthest hostile after the start leaves the build as it began",
	)


## The nearest steps behind the NPC, out of its sight: it stays known at its last spot, still the
## nearest by it. The slot goes to the nearest one that is in sight now.
func _nearest_out_of_sight(t: TestContext, brain: Node, ids: Array) -> void:
	t.actor(&"h0").global_position = BEHIND
	var perception: Node = brain.get("_perception")
	var pos: Vector2 = t.actor(&"d").global_position
	var hostiles := func() -> Array:
		return perception.contacts.known(pos).filter(func(c): return c["hostile"])
	var hidden := func() -> bool:
		for c in hostiles.call():
			if c["id"] == ids[0]:
				return not c["visible"]
		return false
	if not t.require(await t.until(hidden, 3.0), "set-up: the nearest hostile is out of sight"):
		return
	var known: Array = hostiles.call()
	t.require(
		known.size() == SPOTS.size() and known[0]["id"] == ids[0],
		"set-up: it is still known, and still the nearest by its last known spot",
	)
	var later: Dictionary = perception.sense(brain.get("goal"), "", 0)
	t.expect_eq(
		(later["sections_per_target"] as Dictionary).keys(), [ids[1]],
		"the nearest hostile in sight is the one analysed, not the nearer remembered one",
	)
