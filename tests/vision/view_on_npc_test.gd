extends GameTest
## V8 (`docs/player-vision.md`): in a test world any one character can be the viewer, an NPC
## included (`TestSetup.view`), and viewing it changes nothing in its AI. A defender is sent by
## scripted Von to gunfire heard in the kitchen, from the hall: the world has one view, of the
## defender; its polygon is drawn from the defender's eye along the way it faces as it turns round
## the doorways; and the defender decides and walks as it would with no view: it is sent to the
## gunfire, walks the navigated route there (the nav map's own, which no view touches) and gets
## there.
##
## It reads (tests/_vision/vision_probe.gd) the `PlayerView`: `cone()`, `viewer()`. The
## defender is read through its controller's `current_act()`.

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

var _route := PackedVector2Array()


func describe() -> Dictionary:
	return {
		"name": "A viewed NPC decides and walks as it would unviewed",
		"description": "A defender sent to gunfire with a view drawn of it: one view, from its eye "
			+ "along its facing as it turns, and it goes to the gunfire by the navigated route.",
		"tags": ["vision", "ai", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Hall.world(s, &"defender")
	s.switch(&"vision.enabled", true)
	s.view(&"npc")
	s.von_script([{ "pick": "investigate" }])


func run(t: TestContext) -> void:
	var npc := t.actor(&"npc")
	var brain := t.controller(&"npc", &"current_act")
	var found := Probe.views(t)
	if not t.require(found.size() == 1, "one view in the world (%d found)" % found.size()):
		return
	var view := found[0]
	t.check(view.viewer() == npc, "the view is of the NPC")
	await t.seconds(0.5)
	_route = NavBuilder.route(t.world.get_world_2d().navigation_map, npc.global_position, LEAD)
	t.require(
		_route.size() >= 3,
		"premise: the way to the kitchen turns a corner (%d points)" % _route.size(),
	)
	Hall.gunfire(LEAD)
	var walk := await _walk(t, npc, view, brain)
	t.check(
		walk["sent"],
		"the defender answers the gunfire in the kitchen (%s)" % brain.current_act(),
	)
	t.check(walk["arrived"], "it walks to the gunfire (at %s)" % npc.global_position.round())
	t.check(
		walk["stray"] <= ROUTE_SLACK,
		"it keeps to the navigated route (strayed %.0f px)" % walk["stray"],
	)
	t.check(
		walk["eye_off"] <= 10.0,
		"the polygon is drawn from its eye (%.1f px off)" % walk["eye_off"],
	)
	t.check(
		walk["facing_off"] <= FACING_SLACK,
		"the polygon follows its facing (%.1f degrees off)" % walk["facing_off"],
	)
	t.check(
		walk["turned"] >= MIN_TURN,
		"premise: it turned %.0f degrees on the way" % walk["turned"],
	)


## Follow the defender to the gunfire, sampling the view each frame: how far it strayed from the
## route, how far the polygon's eye and middle ray were from its position and facing, how far
## its facing turned in all.
func _walk(t: TestContext, npc: Node2D, view: PlayerView, brain: Node) -> Dictionary:
	var out := {
		"sent": false,
		"arrived": false,
		"stray": 0.0,
		"eye_off": 0.0,
		"facing_off": 0.0,
		"turned": 0.0,
	}
	var last_facing: Vector2 = npc.get("facing")
	var elapsed := 0.0
	while elapsed < 20.0 and not out["arrived"]:
		await t.frames(1)
		elapsed += 1.0 / 60.0
		var act := String(brain.current_act())
		out["sent"] = out["sent"] or act.contains("lead_gunfire") or act.contains("kitchen")
		var cone := view.cone()
		if cone.size() < 3:
			continue
		var facing: Vector2 = npc.get("facing")
		out["stray"] = maxf(out["stray"], _distance_to_route(npc.global_position))
		out["eye_off"] = maxf(out["eye_off"], cone[0].distance_to(npc.global_position))
		var middle := ((cone[1] - cone[0]).normalized() + (cone[-1] - cone[0]).normalized())
		out["facing_off"] = maxf(out["facing_off"], absf(rad_to_deg(middle.angle_to(facing))))
		out["turned"] += rad_to_deg(absf(last_facing.angle_to(facing)))
		last_facing = facing
		out["arrived"] = npc.global_position.distance_to(LEAD) < 60.0
	return out


## How far `p` is from the line of the navigated route.
func _distance_to_route(p: Vector2) -> float:
	var best := INF
	for i in range(1, _route.size()):
		best = minf(
			best,
			p.distance_to(Geometry2D.get_closest_point_to_segment(p, _route[i - 1], _route[i])),
		)
	return best
