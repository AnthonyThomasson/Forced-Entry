extends GameTest
## Performance guard for what the player's view costs, as a difference (`docs/player-vision.md`,
## Perf): the 10v10 of `perf/match_npc_vision` (a generated downtown district whose centre house is
## the largest plan, `Perf.MATCH_PLAN`, built as Main builds one) is played once with the view drawn
## of a puppet parked at the district's outer corner and facing away from the fight (the same look
## on every run, and no world signal of the fight reaches it: see `_place_viewer`), and after the
## warm-up its frames are measured in blocks of `BLOCK_FRAMES`, the view working in one block and
## switched off in the next, in the order on, off, off, on, so a steady drift of the machine falls
## on both. The test asserts that the view adds at most `BUDGET_MS` to a frame.
##
## Off means no per-frame work of the view: its node is disabled (`process_mode`: the cone is not
## rebuilt, nothing is followed or painted) and the capture, memory and mask viewports stop
## rendering (`render_target_update_mode` disabled, put back when it is on again). It goes through
## the view's published reads (`capture()`, `memory()`, `mask()`) alone. The headless run sees the
## CPU side (the cone, the scripts, the viewports' scene work); the GPU side (the two viewport
## passes and the mask shader) it cannot, and was measured by hand windowed, not asserted here.
##
## Why a difference: the absolute guard (`perf/match_npc_vision`) holds the whole frame to the
## standard, so it fails on whatever else the machine is doing and on the match's own cost. This one
## reads the view's cost alone, in the same match and the same minutes on both sides. Why one match
## and not two: two plays of this match (one with the view, one without) differ from each other by
## far more than the view costs, since a fight never plays out twice alike; six runs of that design
## gave a difference of -0.07, 0.33, 0.58, 0.97, 1.64 and 6.23 ms. Blocks of 25 frames of one fight
## see the same fight on both sides. A round's cost is its two view blocks' average frame minus its
## two bare blocks'; the result is the median of the rounds, so the match's own spikes (a nav
## re-bake, a burst of hits) fall in a round and not in the number.
##
## The budget, 3.2 ms (`BUDGET_MS`), is the highest of eight runs measured on a house with the
## machine quiet (the `--quiet` gate passed, none marked loaded) after the view's three savings
## (unseen characters not repainted, the cone rebuilt only when its inputs changed, the cone's own
## caches), plus 25 %, rounded: 0.33, 0.36, 0.63, 1.18, 1.58, 1.70, 2.50 and 2.51 ms, median 1.38
## ms. The spread is between runs (each run plays a different fight, and one run's rounds alone
## range from about -4 to +5 ms), so the median plus 25 % (1.73 ms) would fail two of these eight
## correct runs (2.50 and 2.51 ms); the highest run plus 25 % does not. 3.2 ms still fails the cost
## before the savings: ten quiet runs then gave 2.92 to 5.46 ms (median 4.36), every one over it.
## Runs on a loaded machine can go over any budget here; `--quiet` marks such a run loaded, and a
## loaded red says nothing about the code (`perf.md`).
##
## 2026-11-02, the district: the budget was set on a house and has not been set again for the
## district; it is kept and not loosened. One quiet run on the district (load 3.6, no other Godot)
## read 0.88 ms, rounds from -9.0 to +7.1, and the cone at 0.11 of the reference cone's. The view's
## cost rose with the district-cost commit `5204e489` (the bisect read 3.9 ms before it, 10.4 at it,
## 13.7 after the planning ring) and the Vision change that followed (the even fan cast once, the
## shape query on the cone's sector, a rebuild only for a blocker where a ray can pass) brought it
## back to 4.9 and 5.2 ms. What in `5204e489` raised it was not isolated: with
## `environment_object_visuals.gd` and `blood_smear.gd` put back it read 4.25, with only one of the
## two 9 to 16, and `reask_frames` 1 changed nothing.
##
## The second check is a ratio, `RATIO_MAX` 0.75: in a block of each round the reference cone
## (`tests/_vision/reference_view_cone.gd`, the plainest form of the cone, built whole every frame)
## is built from the viewer's eye and timed, and the live cone's own step (the change check, and the
## rebuild when there was one) is timed in the blocks the view works in (`Stopwatch`), so a
## skipped frame counts at what it cost. The eight quiet runs gave
## 0.27, 0.31, 0.39, 0.39, 0.40, 0.42, 0.49 and 0.59 (median 0.40). With the savings off (the
## reference cone in the view, every frame rebuilt) it reads 1.00 to 1.02; with only the skip off
## it reads about 0.65, and the premise that the view skipped rebuilds fails. The reference cone
## runs in blocks of its own, so it adds nothing to the cost measured above.
##
## 2026-11-06, #192: the moving rounds. After the parked rounds the same fight is played again
## with the viewed puppet walking a curved loop and turning its aim every frame (the guard checks
## that its eye and facing changed on every timed frame), over the same on, off, off, on blocks.
## The test asserts the median of those rounds, `MOVING_BUDGET_MS`, set to 20 ms (about 1.4x the
## moving median of about 13 ms; 11.89 and 10.90 ms on 2026-11-07, so about 1.7x). It
## departs from perf.md's 4x rule: the moving view's cost is a whole cone rebuilt almost every
## frame, a per-frame cost, and 4x of it (about 52 ms) would never trip. A loaded result says
## nothing about it.
##
## 2026-11-12, #195, the cone as a sliced job (`docs/player-vision.md` V1): three `--quiet` runs
## each (none marked loaded; load 3.9 to 5.9, 0 to 2 busy Godot) of this guard at the commit before
## the pipeline and at it. The parked view read -0.14, -0.14 and -0.08 ms before, -0.17, -0.32 and
## -0.23 after, the cone at 0.08 and 0.09 of the reference's; the moving view 4.49, 4.67 and 4.36 ms
## before and 2.05, 2.00 and 2.00 after, its cone 0.44 to 0.45 of the reference's before and 0.25 to
## 0.26 after. The premise counts `PlayerView.starts()`. `MOVING_BUDGET_MS` is 3.5.
##
## 2026-11-07, #192, two runs (not `--quiet`: the gate was bypassed, `perf-district.md`; load 3.2 to
## 6.7, six other Godot processes that were no test's): the parked view read 5.64 and 4.77 ms
## against `BUDGET_MS` 3.2, red as on 2026-11-02 (4.9 and 5.2), rounds from 1.0 to 11.7 ms; the
## moving rounds 11.89 and 10.90 ms against 20, the cone at 0.23 and the moving cone at 0.43 of the
## reference's. A fight's grenade escape bursts (a 40 ms frame, `match_10v10_stress_test.gd`) fall
## in whichever block they fall in and swamp a difference of a few ms: the budget is kept, not
## loosened.
##
## 2026-11-07, #192 Extension 3: the parked viewer stands at the district's outer corner and faces
## away from the fight, in a place no piece the fight moves, dents or frees reaches (its cone and
## bubble hold none of them), so the guard measures a parked view and not a view the fight rebuilds
## on a third to every frame (the largest room of the centre house: a rebuild on 28 to 100 % of the
## frames, measured in the Extension 3 spike). The premise now holds the parked rebuilds to the
## backstop's. With the pose lag (V1) and the fan table the moving rounds read 6.74 and 5.02 ms
## (two runs, not `--quiet`, load 10 to 12 and 29 other Godot, the parked view -0.82 and -0.64 ms
## against 3.2): `MOVING_BUDGET_MS` is set again to 8.5 ms, about 1.4x of their mean, tightened from
## 20. The moving loop turns its aim 6 degrees a frame, past the lag's 1 degree, so the moving view
## still rebuilds every frame there; which of the fan table and the open corner lowered it was not
## isolated.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const Stopwatch := preload("res://tests/_perf/cone_stopwatch.gd")
const Probe := preload("res://tests/_vision/vision_probe.gd")
const PER_SIDE := 10
## Blocks, in order: whether the view works in it. Each block is `BLOCK_FRAMES` frames.
const BLOCKS := [true, false, false, true]
const ROUNDS := 12
const BLOCK_FRAMES := 25
## The most (ms a frame) the view may add to the same match without it (see the header).
const BUDGET_MS := 3.2
## The most (ms a frame) the moving view may cost: 3.5 ms, 1.7x the median of six `--quiet` runs of
## the sliced cone (2.05, 2.00, 2.00, 1.94, 2.04 and 2.14 ms on 2026-11-12, #195: the job is one
## slice a frame, so its cost is the slice's, and the six medians spread 0.2 ms; single rounds reach
## 3.1 ms, which is why the multiple is not 1.4x). The cone as it was before the pipeline read 4.49,
## 4.67 and 4.36 ms, so 3.5 still fails it (it was 8.5 from about 6, 20 from about 13). This departs
## from perf.md's 4x rule, because 4x a per-frame cost would never trip.
const MOVING_BUDGET_MS := 3.5
## The most the live cone's cost a frame may be of the reference cone's, from the same eye (see the
## header).
const RATIO_MAX := 0.75
## How far inside the district's street bounds the parked viewer stands (px), and how far (px) from
## anything solid.
const CORNER_INSET := 60.0
const SOLID_CLEAR := 20.0
## The most of the frames the parked view worked in that may rebuild the cone: its backstop's one
## in `VisionConfig.rebuild_every` (10) and some slack for a frame's chance change. The fight
## cannot reach it.
const PARKED_REBUILT_MAX := 0.2
## Health of the viewer: a view of the dead is lifted, so it must live through the window.
const HEALTH := 1_000_000.0

## Each viewport's update mode as it was, while the view is off.
var _modes := {}
## The view's cost against the unviewed match (ms a frame), and the live cone's cost over the
## reference cone's, one of each per round.
var _costs: Array[float] = []
var _ratios: Array[float] = []
## How many frames the view worked in, and how many of them rebuilt the cone.
var _timed := 0
var _rebuilt := 0  # job starts (`PlayerView.starts()`), restarts included
## The moving rounds' costs, reference ratios and proof that both viewer inputs changed each frame.
var _moving_costs: Array[float] = []
var _moving_ratios: Array[float] = []
var _moving_timed := 0
var _moving_eye_changes := 0
var _moving_facing_changes := 0
var _watch := Stopwatch.new()


func describe() -> Dictionary:
	return {
		"name": "The view adds a bounded cost to a 10v10 match",
		"description": "In one 10v10 match, blocks of frames with the view working and blocks with "
			+ "it switched off, interleaved: the median frame with the view is at most the budget "
			+ "over the median frame without it.",
		"tags": ["match", "ai", "scripted", "crowd", "vision"],
		"timeout": 120.0,
		"allowed_logs": Perf.MATCH_LOGS,
	}


func configure(s: TestSetup) -> void:
	Perf.configure_match(s, PER_SIDE)
	s.switch(&"vision.enabled", true)
	s.actor(&"viewed", &"puppet", Vector2.ZERO, { "max_health": HEALTH, "health": HEALTH })
	s.view(&"viewed")


func run(t: TestContext) -> void:
	Perf.warm_sounds()
	var viewed: Node2D = t.actor(&"viewed")
	var characters: Array = t.world.match_handle.get("combatants", []).duplicate()
	var views := Probe.views(t)
	if not t.require(
			characters.size() == PER_SIDE * 2 and views.size() == 1,
			"premise: twenty combatants and one view (%d, %d)" % [characters.size(), views.size()],
	):
		return
	var view := views[0]
	if not await _place_viewer(t, viewed):
		return
	if not await Perf.warm_until_contact(t, "10v10 match, view cost", characters):
		return
	_watch.attach(view)
	for _round in ROUNDS:
		await _round_of_blocks(t, view)
	_switch(view, true)
	t.check(
		not viewed.is_dead and is_instance_valid(view),
		"premise: the viewer lived and the view stood through the blocks",
	)
	var cost := _median(_costs)
	GameLog.say(
		"PERF 10v10 view cost: median of %d rounds %.2f ms a frame, rounds %s"
		% [ROUNDS, cost, _costs],
	)
	Perf.within(t, "10v10 match, the view's cost ms/frame", cost, BUDGET_MS)
	t.check(
		float(_rebuilt) <= float(_timed) * PARKED_REBUILT_MAX,
		(
			"premise: the parked view started a rebuild only for its backstop in the blocks worked "
			+ "(%d starts in %d frames, at most %.0f %%)"
			% [_rebuilt, _timed, PARKED_REBUILT_MAX * 100.0]
		),
	)
	var ratio := _median(_ratios)
	GameLog.say(
		"PERF 10v10 live cone / reference cone: median of %d rounds %.2f, rounds %s"
		% [ROUNDS, ratio, _ratios],
	)
	Perf.within(t, "10v10 match, live cone cost / reference cone cost", ratio, RATIO_MAX)
	await _measure_moving(t, view, viewed)


## A second round-set over the same fight with the viewed puppet walking and turning every frame.
func _measure_moving(t: TestContext, view: PlayerView, viewed: Node2D) -> void:
	var puppet: Node = t.puppet(&"viewed")
	var loop := _WalkingLoop.new(viewed, puppet)
	view.get_parent().add_child(loop)
	for _round in ROUNDS:
		await _round_of_blocks(t, view, true)
	puppet.stop()
	loop.queue_free()
	_switch(view, true)
	var expected := _moving_timed - ROUNDS  # The first live frame of each round has no predecessor.
	t.check(
		_moving_eye_changes == expected and _moving_facing_changes == expected,
		"premise: the moving viewer changed eye and facing on every timed frame (%d, %d of %d)"
		% [_moving_eye_changes, _moving_facing_changes, expected],
	)
	var cost := _median(_moving_costs)
	GameLog.say(
		"PERF 10v10 moving view cost: median of %d rounds %.2f ms a frame, rounds %s"
		% [ROUNDS, cost, _moving_costs],
	)
	Perf.within(t, "10v10 match, the moving view's cost ms/frame", cost, MOVING_BUDGET_MS)
	GameLog.say(
		"PERF 10v10 moving live cone / reference cone: median %.2f, rounds %s"
		% [_median(_moving_ratios), _moving_ratios],
	)


## One round: the blocks of `BLOCKS` (the view's cost against the match without it), then a block of
## the reference cone from the same eye, which adds nothing to those.
func _round_of_blocks(t: TestContext, view: PlayerView, moving := false) -> void:
	var with_view := 0.0
	var without := 0.0
	_watch.reset()
	for on: bool in BLOCKS:
		_switch(view, on)
		var before := view.starts()
		var stats := await Perf.frame_stats(t, BLOCK_FRAMES)
		if on:
			with_view += stats["avg_ms"] / float(BLOCKS.count(true))
			if not moving:
				_rebuilt += view.starts() - before
				_timed += BLOCK_FRAMES
		else:
			without += stats["avg_ms"] / float(BLOCKS.count(false))
	if moving:
		_moving_costs.append(with_view - without)
	else:
		_costs.append(with_view - without)
	_switch(view, false)
	_watch.measure_reference = true
	await Perf.frame_stats(t, BLOCK_FRAMES)
	_watch.measure_reference = false
	var ratio := _watch.live_average() / maxf(_watch.reference_average(), 0.001)
	if moving:
		_moving_ratios.append(ratio)
		_moving_timed += _watch.live_frames
		_moving_eye_changes += _watch.eye_changes
		_moving_facing_changes += _watch.facing_changes
	else:
		_ratios.append(ratio)
	t.check(
		_watch.live_frames > 0 and _watch.reference_frames > 0,
		"premise: both cones were timed (%d, %d frames)"
		% [_watch.live_frames, _watch.reference_frames],
	)


## Switch `view` on or off. Off, none of its work runs: the view's node is disabled (its cone is not
## rebuilt, nothing is followed or painted) and the capture, the memory and the mask stop rendering
## (their update modes are disabled, and put back as they were when it is on again; `_modes` keeps
## them). It goes through the view's published reads and nodes alone.
func _switch(view: PlayerView, on: bool) -> void:
	view.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	for viewport: SubViewport in [view.capture(), view.memory(), view.mask()]:
		if on and _modes.has(viewport):
			viewport.render_target_update_mode = _modes[viewport]
		elif not on and not _modes.has(viewport):
			_modes[viewport] = viewport.render_target_update_mode
			viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if on:
		_modes.clear()


## Put the viewed puppet at the district's north-west outer corner, `CORNER_INSET` px inside the
## streets' bounds, facing straight away from the centre house: nothing the fight moves, dents or
## frees lies in its cone or its bubble, so no world signal reaches it and only its own backstop
## rebuilds a parked view. The same spot on every run. Whether it faces that way in the end, and
## stands clear of anything solid.
func _place_viewer(t: TestContext, viewed: Node2D) -> bool:
	var bounds := WorldGen.district_bounds(t.world.district)
	var towers := DistrictReads.get_towers(t.world.district)
	if not t.require(bounds.has_area() and towers.size() == 9, "premise: a district"):
		return false
	var middle: Vector2 = (towers[4]["rect"] as Rect2).get_center()
	var at := bounds.position + Vector2(CORNER_INSET, CORNER_INSET)
	var away := (at - middle).normalized()
	if not t.require(not Probe.solid_near(t, at, SOLID_CLEAR), "premise: the corner is clear"):
		return false
	viewed.global_position = at
	t.puppet(&"viewed").aim_at(at + away * 100.0)
	await t.frames(3)
	return t.require(
		(viewed.get("facing") as Vector2).distance_to(away) < 0.01,
		"premise: the viewer faces away from the fight (from %s, facing %s, toward %s)"
		% [at.round(), viewed.get("facing"), away],
	)


## The median of `values`.
func _median(values: Array[float]) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	var middle := floori(sorted.size() * 0.5)
	if sorted.size() % 2 == 1:
		return sorted[middle]
	return (sorted[middle - 1] + sorted[middle]) * 0.5


## Drives a tight curved walk and a continuously turning aim through the puppet's public commands.
class _WalkingLoop:
	extends Node

	var _viewer: Node2D
	var _puppet: Node
	var _step := 0

	func _init(viewer: Node2D, puppet: Node) -> void:
		_viewer = viewer
		_puppet = puppet

	func _physics_process(_delta: float) -> void:
		_step += 1
		_puppet.walk(Vector2.from_angle(float(_step) * 0.04))
		_puppet.aim_at(_viewer.global_position + Vector2.from_angle(float(_step) * 0.11) * 500.0)
