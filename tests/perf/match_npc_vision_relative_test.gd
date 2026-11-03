extends GameTest
## Performance guard for what the player's view costs, as a difference (`docs/player-vision.md`,
## Perf): the 10v10 of `perf/match_npc_vision` (a generated downtown district whose centre house is
## the largest plan, `Perf.MATCH_PLAN`, built as Main builds one) is played once with the view drawn
## of a puppet placed in the largest room and facing a doorway (the same long look on every run, as
## a fighting viewer would see more or less of the house), and after the warm-up its frames are
## measured in blocks of `BLOCK_FRAMES`, the view working in one block and switched off in the next,
## in the order on, off, off, on, so a steady drift of the machine falls on both. The test asserts
## that the view adds at most `BUDGET_MS` to a frame.
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
## The most of the frames the view worked in that may rebuild the cone, or it skipped none to speak
## of.
const REBUILT_MAX := 0.95
## The most the live cone's cost a frame may be of the reference cone's, from the same eye (see the
## header).
const RATIO_MAX := 0.75
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
var _rebuilt := 0
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
		float(_rebuilt) < float(_timed) * REBUILT_MAX,
		"premise: the view skipped rebuilds in the blocks it worked (%d rebuilds in %d frames)"
		% [_rebuilt, _timed],
	)
	var ratio := _median(_ratios)
	GameLog.say(
		"PERF 10v10 live cone / reference cone: median of %d rounds %.2f, rounds %s"
		% [ROUNDS, ratio, _ratios],
	)
	Perf.within(t, "10v10 match, live cone cost / reference cone cost", ratio, RATIO_MAX)


## One round: the blocks of `BLOCKS` (the view's cost against the match without it), then a block of
## the reference cone from the same eye, which adds nothing to those.
func _round_of_blocks(t: TestContext, view: PlayerView) -> void:
	var with_view := 0.0
	var without := 0.0
	_watch.reset()
	for on: bool in BLOCKS:
		_switch(view, on)
		var before := view.rebuilds()
		var stats := await Perf.frame_stats(t, BLOCK_FRAMES)
		if on:
			with_view += stats["avg_ms"] / float(BLOCKS.count(true))
			_rebuilt += view.rebuilds() - before
			_timed += BLOCK_FRAMES
		else:
			without += stats["avg_ms"] / float(BLOCKS.count(false))
	_costs.append(with_view - without)
	_switch(view, false)
	_watch.measure_reference = true
	await Perf.frame_stats(t, BLOCK_FRAMES)
	_watch.measure_reference = false
	_ratios.append(_watch.live_average() / maxf(_watch.reference_average(), 0.001))
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


## Put the viewed puppet at the centre of the house's largest room, facing out through that room's
## first doorway: the same long look through a doorway on every run, where a viewer that fought
## would see more or less of the house as it moved. Whether it faces that way in the end.
func _place_viewer(t: TestContext, viewed: Node2D) -> bool:
	var rooms: Array = t.rooms.duplicate()
	rooms.sort_custom(func(a, b): return a["rect"].get_area() > b["rect"].get_area())
	var room: Dictionary = rooms[0]
	var centre: Vector2 = (room["rect"] as Rect2).get_center()
	var door: Dictionary = {}
	for opening: Dictionary in t.world.openings:
		if door.is_empty() and (opening["rooms"] as Array).has(room["key"]):
			door = opening
	if not t.require(not door.is_empty(), "premise: the largest room has a doorway"):
		return false
	viewed.global_position = centre
	t.puppet(&"viewed").aim_at(door["pos"])
	await t.frames(3)
	var look: Vector2 = ((door["pos"] as Vector2) - viewed.global_position).normalized()
	return t.require(
		(viewed.get("facing") as Vector2).distance_to(look) < 0.01,
		"premise: the viewer faces through the doorway (from %s, facing %s, toward %s)"
		% [viewed.global_position.round(), viewed.get("facing"), look],
	)


## The median of `values`.
func _median(values: Array[float]) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	var middle := floori(sorted.size() * 0.5)
	if sorted.size() % 2 == 1:
		return sorted[middle]
	return (sorted[middle - 1] + sorted[middle]) * 0.5
