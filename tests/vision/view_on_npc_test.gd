extends GameTest
## V8 (`docs/player-vision.md`): in a test world any one character can be the viewer, an NPC
## included (`TestSetup.view`), and viewing it changes nothing in its AI. The same scripted world
## and seed run twice, one world after the other, and each time a defender is sent by scripted Von
## to gunfire heard in the kitchen, from the hall: once with the view on the defender and once
## without. The viewed world has one view, of the defender; its polygon is drawn from the
## defender's eye along the way it faces as it turns round the doorways; and the two runs agree:
## the defender goes through the same decisions in the same order and is at the same places on
## the same ticks (within `PATH_TOLERANCE`), reaching the gunfire on the same tick. The viewed run
## also keeps to the navigated route (the nav map's own, which no view touches).
##
## The session's own world is a bare arena out of the way; the two runs are worlds the test builds
## itself, one at a time, from the same declaration. It reads (tests/_vision/vision_probe.gd) the
## `PlayerView`: `cone()`, `viewer()`. The defender is read through its controller's
## `current_act()`.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const Hall := preload("res://tests/_ai/investigate_probe.gd")
## The heard gunfire: the middle of the kitchen, the way in the hall, a living room and two
## doorways apart.
const LEAD := Vector2(660, 190)
## The walk may stray this far from the navigated route's line, px (the steering rounds corners).
const ROUTE_SLACK := 70.0
## The cone's middle ray may differ from the defender's facing by this much, degrees.
const FACING_SLACK := 3.0
## The defender must turn by at least this much over the walk, degrees, or the test proves nothing.
const MIN_TURN := 45.0
## The two runs' defenders may be this far apart (px) at the same tick, and may reach the gunfire
## this many ticks apart. Two unviewed runs of the same world already differ by up to 2.5 px (a
## tick of the walk, about 2.5 px, off), so this is twice that: a view that nudged the defender's
## walk would show beyond it.
const PATH_TOLERANCE := 5.0
const ARRIVAL_SLACK_TICKS := 2
## A run is cut off after this many seconds.
const RUN_LIMIT_S := 20.0
## The run's samples: the first tick of the run is 0.
const ACT := "act"
const AT := "at"

var _route := PackedVector2Array()


func describe() -> Dictionary:
	return {
		"name": "A viewed NPC decides and walks as it would unviewed",
		"description": "The same defender sent to gunfire twice, with a view drawn of it and "
			+ "without: one view, from its eye along its facing as it turns; and the same "
			+ "decisions in the same order, at the same places on the same ticks.",
		"tags": ["vision", "ai", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	# Out of the way of the worlds the test builds.
	s.arena(Rect2(3000, 3000, 200, 200))


func run(t: TestContext) -> void:
	var plain := await _twin(t, false)
	var viewed := await _twin(t, true)
	if not t.require(plain["arrived"] and viewed["arrived"], "both defenders reach the gunfire"):
		return
	_check_view(t, viewed)
	_check_twins(t, plain, viewed)


## Build the world once (the view on the defender or not), send the defender to the gunfire and
## record the run, then free the world.
func _twin(t: TestContext, viewed: bool) -> Dictionary:
	var s := TestSetup.new()
	Hall.world(s, &"defender")
	s.switch(&"vision.enabled", viewed)
	if viewed:
		s.view(&"npc")
	s.von_script([{ "pick": "investigate" }])
	var world: Node2D = await Probe.build_world(t, s)
	var out := await _walk(t, world, viewed)
	await Probe.drop_world(t, world)
	return out


## Send the world's defender to the gunfire and record every tick: its act and its place, and for a
## viewed world how the view followed it.
func _walk(t: TestContext, world: Node2D, viewed: bool) -> Dictionary:
	var npc: Node2D = world.actors[&"npc"]
	var views := Probe.views_under(world)
	var out := {
		"views": views,
		"viewer_ok": viewed and views.size() == 1 and views[0].viewer() == npc,
		"samples": [],
		"arrived": false,
		"arrival": -1,
		"stray": 0.0,
		"eye_off": 0.0,
		"facing_off": 0.0,
		"turned": 0.0,
		"sent": false,
	}
	await t.seconds(0.5)
	_route = NavBuilder.route(world.get_world_2d().navigation_map, npc.global_position, LEAD)
	out["route_points"] = _route.size()
	Hall.gunfire(LEAD)
	var last_facing: Vector2 = npc.get("facing")
	var tick := 0
	while float(tick) / 60.0 < RUN_LIMIT_S and not out["arrived"]:
		await t.frames(1)
		var brain := TestContext.controller_of(npc, &"current_act")
		var act := String(brain.current_act())
		out["samples"].append({ ACT: "%s %s" % [act, _picks(brain)], AT: npc.global_position })
		out["sent"] = out["sent"] or act.contains("lead_gunfire") or act.contains("kitchen")
		out["arrived"] = npc.global_position.distance_to(LEAD) < 60.0
		out["arrival"] = tick if out["arrived"] else -1
		tick += 1
		if viewed and not views.is_empty():
			_follow(out, npc, views[0], last_facing)
		last_facing = npc.get("facing")
	return out


## How far the view's polygon is from the defender's place and facing, and how far it strayed from
## the navigated route.
func _follow(out: Dictionary, npc: Node2D, view: PlayerView, last_facing: Vector2) -> void:
	var cone := view.cone()
	if cone.size() < 3:
		return
	var facing: Vector2 = npc.get("facing")
	out["stray"] = maxf(out["stray"], _distance_to_route(npc.global_position))
	out["eye_off"] = maxf(out["eye_off"], cone[0].distance_to(npc.global_position))
	var middle := (cone[1] - cone[0]).normalized() + (cone[-1] - cone[0]).normalized()
	out["facing_off"] = maxf(out["facing_off"], absf(rad_to_deg(middle.angle_to(facing))))
	out["turned"] += rad_to_deg(absf(last_facing.angle_to(facing)))


## What the viewed run shows of the view itself.
func _check_view(t: TestContext, viewed: Dictionary) -> void:
	t.check(
		viewed["views"].size() == 1,
		"one view in the viewed world (%d)" % viewed["views"].size(),
	)
	t.check(viewed["viewer_ok"], "the view is of the NPC")
	t.require(
		viewed["route_points"] >= 3,
		"premise: the way to the kitchen turns a corner (%d points)" % viewed["route_points"],
	)
	t.check(viewed["sent"], "the defender answers the gunfire in the kitchen")
	t.check(
		viewed["stray"] <= ROUTE_SLACK,
		"it keeps to the navigated route (strayed %.0f px)" % viewed["stray"],
	)
	t.check(
		viewed["eye_off"] <= 10.0,
		"the polygon is drawn from its eye (%.1f px off)" % viewed["eye_off"],
	)
	t.check(
		viewed["facing_off"] <= FACING_SLACK,
		"the polygon follows its facing (%.1f degrees off)" % viewed["facing_off"],
	)
	t.check(
		viewed["turned"] >= MIN_TURN,
		"premise: it turned %.0f degrees on the way" % viewed["turned"],
	)


## The two runs against each other: the same decisions in the same order, the same places on the
## same ticks, the same arrival.
func _check_twins(t: TestContext, plain: Dictionary, viewed: Dictionary) -> void:
	t.check(plain["views"].is_empty(), "premise: the unviewed world has no view")
	var acts_plain := _decisions(plain["samples"])
	var acts_viewed := _decisions(viewed["samples"])
	t.check(
		not acts_plain.is_empty() and acts_plain[0] != "",
		"premise: the defender decides what to do (%s)" % [acts_plain],
	)
	t.check(
		acts_plain == acts_viewed,
		"the same decisions in the same order: unviewed %s, viewed %s" % [acts_plain, acts_viewed],
	)
	t.check(
		absi(plain["arrival"] - viewed["arrival"]) <= ARRIVAL_SLACK_TICKS,
		"it reaches the gunfire on the same tick (%d unviewed, %d viewed)"
		% [plain["arrival"], viewed["arrival"]],
	)
	var drift := _drift(plain["samples"], viewed["samples"])
	t.check(
		drift <= PATH_TOLERANCE,
		"it is at the same places on the same ticks (%.2f px apart at most)" % drift,
	)


## The options its last decision walk picked at each level, root first.
func _picks(brain: Node) -> Array:
	return Hall.levels(brain).map(func(level: Dictionary) -> Variant: return level.get("pick"))


## The acts of a run in order, each repeat of the one before left out.
func _decisions(samples: Array) -> Array:
	var acts: Array = []
	for sample in samples:
		if acts.is_empty() or acts[-1] != sample[ACT]:
			acts.append(sample[ACT])
	return acts


## The farthest the two runs' defenders are apart on the same tick.
func _drift(a: Array, b: Array) -> float:
	var worst := 0.0
	for i in mini(a.size(), b.size()):
		worst = maxf(worst, (a[i][AT] as Vector2).distance_to(b[i][AT]))
	return worst


## How far `p` is from the line of the navigated route.
func _distance_to_route(p: Vector2) -> float:
	var best := INF
	for i in range(1, _route.size()):
		best = minf(
			best,
			p.distance_to(Geometry2D.get_closest_point_to_segment(p, _route[i - 1], _route[i])),
		)
	return best
