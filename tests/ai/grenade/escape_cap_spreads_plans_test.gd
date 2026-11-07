extends GameTest
## G16, an evade wave under the per-frame escape cap (#192 rule 31): at most `ESCAPE_CAP` (3)
## escape searches (`AgentThrow.escape`) run on one physics frame across every NPC, so ten
## defenders caught by one frag on one frame have their plans over the next frames, three at a
## time, each at most 3 frames after it first could, and every one of them is clear of the burst.
## Ten defenders stand in the open warehouse in two rows either side of the frag's flight, all
## facing the thrower and inside the frag's zone as it leaves its hand, so they see it and need a
## plan on the same frame (the premise: it is known to all ten on one frame). Each frame, after
## every NPC has processed, each one's evade plan (the
## grenade perception's `_plans`: `at` is the frame it was made) is read: a plan new to an NPC is
## a fresh plan, one that changed a replan. The reservation of rule 31 is asserted as worded: a
## replan never takes the last search of a frame (at most CAP - 1 a frame), and none runs on a
## frame after a fresh plan was refused. A replan earlier in the NPC order may still run on the
## frame a fresh plan is first refused, so that frame is not held to it.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
## The spec's numbers: searches on one frame, and frames to a plan (`docs/grenades.md` G16).
const CAP := 3
const WITHIN_FRAMES := 3
const LANDING := Vector2(470, 350)
const THROWER_AT := Vector2(700, 350)
const NPC_COUNT := 10
## Four more are blinded for `LATE_BLIND` s as the frag leaves the hand: they hear it come down and
## need a plan then, the frame the ten's first replans fall due (a replan must not hold a fresh plan
## up).
const LATE_COUNT := 4
const LATE_BLIND := 1.0


func describe() -> Dictionary:
	return {
		"name": "The escape cap spreads ten NPCs' plans over three frames",
		"description": "Ten defenders caught by one frag on one frame: no frame runs more than "
			+ "three escape searches, each has its plan within 3 frames of first knowing the "
			+ "grenade, and every one is clear when it goes off.",
		"tags": ["ai", "grenade", "evade", "perf"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.warehouse(s, false)
	s.von_script([])
	s.switch(&"ai.hostile_on_trespass", false)
	for i in NPC_COUNT:
		var at := Vector2(380 + (i % 5) * 45, 270.0 if i < 5 else 430.0)
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
	var record := { "frames": {}, "prev": {}, "first_known": {}, "planned": {} }
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
	var wave: int = starts.values().max() if not starts.is_empty() else 0
	t.require(
		wave == NPC_COUNT,
		"set-up: all ten know the frag on one frame (the most on one frame: %d, %s; knew it: %s)"
			% [wave, starts, first],
	)
	var frames: Dictionary = record["frames"]
	var busiest := 0
	for frame: int in frames:
		var row: Dictionary = frames[frame]
		busiest = maxi(busiest, int(row["fresh"]) + int(row["replan"]))
	t.check(busiest <= CAP, "no frame ran more than %d searches (the most: %d)" % [CAP, busiest])
	var late: Array = []
	for id in first:
		var planned: int = record["planned"].get(id, 1_000_000)
		if planned - int(first[id]) > WITHIN_FRAMES:
			late.append("%s %d" % [id, planned - int(first[id])])
	t.check(late.is_empty(), "every NPC has its plan within 3 frames of first knowing: %s" % [late])
	t.check(
		record["planned"].size() == NPC_COUNT + LATE_COUNT,
		"all %d planned (%d)" % [NPC_COUNT + LATE_COUNT, record["planned"].size()],
	)
	_check_fresh_first(t, frames)


## A replan fell due on a frame a fresh plan waited (the late four, hearing the frag land as the
## ten's replans are due): the fresh plan still had a search that frame, and while one waited no
## replan took a search the next.
func _check_fresh_first(t: TestContext, frames: Dictionary) -> void:
	var clash := -1
	for frame: int in frames:
		if int(frames[frame]["replan"]) > 0 and int(frames[frame]["waiting"]) > 0:
			clash = frame
	if not t.require(clash != -1, "set-up: a replan fell due on a frame a fresh plan waited"):
		return
	var row: Dictionary = frames[clash]
	t.check(
		int(row["fresh"]) >= 1 and int(row["replan"]) < CAP,
		"on that frame a fresh plan still had a search (%s)" % [row],
	)
	var greedy: Array = []
	for frame: int in frames:
		if int(frames[frame]["replan"]) > CAP - 1:
			greedy.append(frame)
	t.check(greedy.is_empty(), "no frame gave replans all %d searches: %s" % [CAP, greedy])
	var held_up: Array = []
	for frame: int in frames:
		if frames.has(frame - 1) and int(frames[frame - 1]["waiting"]) > 0:
			if int(frames[frame]["replan"]) > 0:
				held_up.append(frame)
	t.check(held_up.is_empty(), "no replan took a search while a fresh plan waited: %s" % [held_up])


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
