extends GameTest
## G16, an evade wave under the escape pool (`EscapePool`): the escape searches of every NPC fleeing
## one grenade share `per_frame` units a physics frame, so thirty defenders caught by one frag on
## one frame have their plans over the next frames, the one nearest the burst first, no frame spends
## more than the pool and one candidate's work (7 units), every plan lands well inside the fuse and
## every one of them is clear of the burst. Thirty defenders stand in the open warehouse in six rows
## either side of the frag's flight, all facing the thrower and inside the frag's zone as it
## leaves its hand, so they see it and need a plan on the same frame (the premise: it is known to
## all thirty on one frame). Each frame, after every NPC has processed, each one's evade plan (the
## grenade perception's `_plans`: `at` is the frame it was made) is read. Four more are blinded as
## the frag leaves the hand, and hear it come down: new plans among the replans of the thirty. The
## order rule itself (a plan with none yet before a replan, the grenade that goes off first, the
## runner nearest, the search begun first) is pinned on its keys.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
const AgentThrow := preload("res://scenes/ai/perception/agent_throw.gd")
## The spec's numbers: the most a frame serves over the pool and its urgent extra (one candidate: a
## snap, a verdict and a route), the frames from knowing the frag to its plan (the most measured is
## 15, with the thirty and four, 16 for the half that sees the frag a beat later (`beat.md`: an NPC
## off its beat sees a new grenade on its next, one frame on); 19 without the urgent extra, when one
## of them was caught), and the
## frames before the burst the plan must beat by `ARRIVE_MARGIN` (`docs/grenades.md` G16). The
## candidates round a burst are paid when a search begins, whatever the pool has left, and are not
## served (`peak_served`).
const OVER := 7
const WITHIN_FRAMES := 16
const LANDING := Vector2(470, 350)
const THROWER_AT := Vector2(700, 350)
const NPC_COUNT := 30
## Four more are blinded for `LATE_BLIND` s as the frag leaves the hand: they hear it come down and
## need a plan then, the frame the thirty's first replans fall due (a replan must not hold a fresh
## plan up).
const LATE_COUNT := 4
const LATE_BLIND := 1.0


func describe() -> Dictionary:
	return {
		"name": "The escape pool spreads thirty NPCs' plans over frames, nearest the burst first",
		"description": "Thirty defenders caught by one frag on one frame: no frame spends more "
			+ "escape units than the pool, the nearest the burst plan first, each has its plan "
			+ "within the bound of first knowing the grenade, and every one is clear when it "
			+ "goes off.",
		"tags": ["ai", "grenade", "evade", "perf"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.warehouse(s, false)
	EscapePool.reset()
	s.von_script([])
	s.switch(&"ai.hostile_on_trespass", false)
	for i in NPC_COUNT:
		var row := floori(i / 5.0)
		var at := Vector2(380 + (i % 5) * 45, 170.0 + row * 60 if row < 3 else 230.0 + row * 60)
		s.actor(_id(i), &"defender", at, { "facing": Vector2.RIGHT })
	for i in LATE_COUNT:
		var at := Vector2(250 + (i % 2) * 45, 310.0 + floorf(i / 2.0) * 60.0)
		s.actor(_id(NPC_COUNT + i), &"defender", at, { "facing": Vector2.RIGHT })
	s.actor(
		&"thrower",
		&"puppet",
		THROWER_AT,
		{ "faction": &"defender", "max_health": 1_000_000.0, "movement:aim_point": LANDING },
	)


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	Probe.arm(thrower, 0, 1)
	if not t.require(Probe.count(thrower, Probe.FRAG) == 1, "the thrower carries a frag"):
		return
	await t.seconds(0.6)
	var record := { "frames": {}, "prev": {}, "first_known": {}, "planned": {}, "away": {} }
	var late := LateProbe.new()
	late.process_physics_priority = 1000
	late.each = func() -> void: _sample(t, record)
	t.world.add_child(late)
	var puppet := t.puppet(&"thrower")
	puppet.select_slot(Probe.FRAG)
	puppet.aim_at(LANDING)
	await t.seconds(0.4)
	puppet.aim_at(LANDING)
	await t.frames(3)
	puppet.shoot()
	for i in LATE_COUNT:
		Probe.stun(t.actor(_id(NPC_COUNT + i)), LATE_BLIND, 0.0)
	if not t.require(await Probe.wait_boom(t, &"frag", 6.0), "the frag went off"):
		return
	record["boom"] = Engine.get_physics_frames()
	_check_wave(t, record)
	_check_clear(t)


func _id(i: int) -> StringName:
	return StringName("d%d" % i)


## One physics frame's reading, after every NPC has processed: who knows the grenade, whose plan
## is new (fresh) or changed (replan), and who still waits for one.
func _sample(t: TestContext, record: Dictionary) -> void:
	var frame := Engine.get_physics_frames()
	var row := { "fresh": 0, "replan": 0, "waiting": 0 }
	var prev: Dictionary = record["prev"]
	for i in NPC_COUNT + LATE_COUNT:
		var id := _id(i)
		var brain := t.controller(id, &"debug_grenades")
		var known: bool = not (brain.call("debug_grenades")["known"] as Array).is_empty()
		var plans: Dictionary = brain.get("_perception").grenades.live.get("_plans")
		var at := -1
		for plan: Dictionary in plans.values():
			at = int(plan["at"])
		if known and not (record["first_known"] as Dictionary).has(id):
			record["first_known"][id] = frame
			# How far it stood from the grenade where it knew it: the order's distance.
			var point: Vector2 = (brain.call("debug_grenades")["known"] as Array)[0]["point"]
			record["away"][id] = (t.actor(id) as Node2D).global_position.distance_to(point)
		if at != -1 and not (record["planned"] as Dictionary).has(id):
			record["planned"][id] = frame
		if at != int(prev.get(id, -1)):
			row["fresh" if int(prev.get(id, -1)) == -1 else "replan"] += 1
		elif known and at == -1:
			row["waiting"] += 1
		prev[id] = at
	if row["fresh"] + row["replan"] + row["waiting"] > 0:
		record["frames"][frame] = row


func _check_wave(t: TestContext, record: Dictionary) -> void:
	var first: Dictionary = record["first_known"]
	var starts := {}
	for id in first:
		if int(String(id).trim_prefix("d")) < NPC_COUNT:
			starts[first[id]] = int(starts.get(first[id], 0)) + 1
	# The NPCs sense on a beat (`npc_pace.gd`): the half off its turn on the frame the frag comes
	# sees it on its next, one frame on, so all thirty know it within two frames, each half on one.
	var wave: int = 0
	for n in starts.values():
		wave += int(n)
	t.require(
		wave == NPC_COUNT and starts.size() <= 2,
		"set-up: all thirty know the frag within a beat, each half on one frame (%s; knew it: %s)"
			% [starts, first],
	)
	t.check(
		EscapePool.peak_spent >= EscapePool.per_frame,
		"premise: the wave used the whole pool (%d of %d units)"
			% [EscapePool.peak_spent, EscapePool.per_frame],
	)
	t.check(
		EscapePool.peak_served <= EscapePool.per_frame + EscapePool.urgent_extra + OVER,
		"no frame served more than the pool and one candidate (the most: %d, pool %d)"
			% [EscapePool.peak_served, EscapePool.per_frame],
	)
	var late: Array = []
	var waits: Array = []
	for id in first:
		var planned: int = record["planned"].get(id, 1_000_000)
		waits.append(planned - int(first[id]))
		if planned - int(first[id]) > WITHIN_FRAMES:
			late.append("%s %d" % [id, planned - int(first[id])])
	waits.sort()
	t.check(late.is_empty(), "every NPC has its plan within %d frames of knowing: %s"
			% [WITHIN_FRAMES, late])
	var margin := ceili(AgentThrow.ARRIVE_MARGIN * Engine.physics_ticks_per_second)
	var past_margin: Array = []
	for id in record["planned"]:
		if int(record["planned"][id]) > int(record["boom"]) - margin:
			past_margin.append("%s %d" % [id, int(record["boom"]) - int(record["planned"][id])])
	t.check(past_margin.is_empty(), "every plan lands %d frames (the margin) before the burst: %s"
			% [margin, past_margin])
	t.check(
		record["planned"].size() == NPC_COUNT + LATE_COUNT,
		"all %d planned (%d)" % [NPC_COUNT + LATE_COUNT, record["planned"].size()],
	)
	_check_nearest_first(t, record)
	_check_order_rule(t)


## The NPCs that knew the frag on one frame were served nearest the burst first: none planned
## before one nearer the burst that knew it on the same frame.
func _check_nearest_first(t: TestContext, record: Dictionary) -> void:
	var rows: Array = []
	for i in NPC_COUNT:
		rows.append({
			"id": _id(i),
			"d": float(record["away"].get(_id(i), 0.0)),
			"known": int(record["first_known"].get(_id(i), 0)),
			"at": int(record["planned"].get(_id(i), 1_000_000)),
		})
	var inverted: Array = []
	for a: Dictionary in rows:
		for b: Dictionary in rows:
			if (float(a["d"]) + 1.0 < float(b["d"]) and int(a["at"]) > int(b["at"])
					and int(a["known"]) == int(b["known"])):
				inverted.append("%s (%d px) after %s (%d px)" % [a["id"], a["d"], b["id"], b["d"]])
	t.check(inverted.is_empty(), "no NPC planned after one farther from the burst: %s" % [inverted])


## The pool's order on its keys `[replan, deadline, distance, seq, began, urgent]` (the urgent
## ones are pinned by `escape_pool_bounds_wait`).
func _check_order_rule(t: TestContext) -> void:
	var keys := [[true, 100, 5.0, 1, 0, false], [false, 200, 90.0, 2, 0, false],
			[false, 100, 90.0, 3, 0, false], [false, 100, 20.0, 4, 0, false],
			[false, 100, 20.0, 5, 0, false]]
	var searches: Array[EscapeSearch] = []
	for key: Array in keys:
		var search := EscapeSearch.new(RID(), Vector2.ZERO, [], 0.0, Callable())
		search.key = key
		searches.append(search)
	searches.sort_custom(EscapePool._before)
	t.expect_eq(
		searches.map(func(s: EscapeSearch) -> int: return s.key[3]),
		[4, 5, 3, 2, 1],
		"fresh before replan, the soonest fuse, the nearest runner, the first begun",
	)


func _check_clear(t: TestContext) -> void:
	var hurt: Array = []
	for i in NPC_COUNT:
		var c := t.actor(_id(i))
		if c.is_dead or not Probe.blast_hits(t, c).is_empty():
			hurt.append(String(_id(i)))
	t.check(hurt.is_empty(), "every defender is alive and clear of the blast (hit: %s)" % [hurt])


## Runs after every other node on each physics frame, before the physics step.
class LateProbe extends Node:
	var each: Callable

	func _physics_process(_delta: float) -> void:
		each.call()
