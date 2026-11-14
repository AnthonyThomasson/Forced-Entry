extends GameTest
## The worst-frames report's counters for the player's view (`tests/_perf/frame_report.gd`,
## `perf.md`) on a live world: each cone counter is seen in a frame where its work ran, from
## `PlayerView`'s read (interface 25). A view built mid-window builds its first cone whole
## (`cone_first`); an eye that jumps builds whole too (`cone_jump`); a solid that joins the world in
## each of several frames restarts a job in flight (`cone_restarts`) and then, past the restart cap,
## builds whole (`cone_cap`); every frame that started or built a cone spent engine work
## (`cone_units`) and a frame that did none spent none. The spec's numbers are kept here: a restart
## cap of two, a jump past 48 px.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const Probe := preload("res://tests/_vision/vision_probe.gd")
const EYE_AT := Vector2(200, 300)
## A job of this slice (units) takes a few frames, so there is a job to restart.
const SLICE := 90
## Where the second viewer stands (its view is the one built mid-window), and where the eye jumps.
const SECOND_AT := Vector2(500, 420)
const JUMPS_TO := Vector2(330, 420)
const SIZE := Vector2(30.0, 60.0)
## Frames of the windows, and the frame each acts in.
const FIRST_FRAMES := 12
const ACT_AT := 3
const JOIN_FRAMES := 14
const CAP := 2


func describe() -> Dictionary:
	return {
		"name": "The worst-frames report counts the cone's restarts, whole builds and work",
		"description": "A view built mid-window, an eye that jumps and solids that join in "
			+ "every frame: the first, jump and cap whole builds and the restarts are each "
			+ "counted in a frame the work ran in, with the cone's engine work.",
		"tags": ["vision", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Probe.building(s, EYE_AT)
	s.switch(&"vision.enabled", true)
	s.set_static(VisionSliceConfig, &"slice_units", SLICE)
	s.actor(&"second", &"puppet", SECOND_AT)
	s.view(&"eye")


func run(t: TestContext) -> void:
	var view := Probe.view(t)
	if not t.require(view != null, "the world has a view"):
		return
	var eye: Node2D = t.actor(&"eye")
	if not t.require(await Probe.place(t, eye, EYE_AT, Vector2.RIGHT), "the viewer is settled"):
		return
	var logging := GameLog.enabled
	GameLog.enabled = true
	# 1. A view built mid-window: its first cone is built whole.
	var first := await Perf.frame_stats(
		t, FIRST_FRAMES, func(i: int) -> void:
			if i == ACT_AT:
				PlayerView.watch(t.world, t.actor(&"second"))
	)
	_seen(t, first["ran"], "cone_first", "a view's first cone")
	_seen_with_units(t, first["ran"], "cone_first")
	t.check(_total(first["ran"], "cone_restarts") == 0, "a calm window restarts nothing")
	# 2. An eye past the jump distance: its cone is built whole at once.
	var jumped := await Perf.frame_stats(
		t, FIRST_FRAMES, func(i: int) -> void:
			if i == ACT_AT:
				eye.global_position = JUMPS_TO
	)
	_seen(t, jumped["ran"], "cone_jump", "an eye that jumped")
	_seen_with_units(t, jumped["ran"], "cone_jump")
	# 3. A solid joining in each frame: restarts, then a whole build past the cap.
	await Probe.place(t, eye, EYE_AT, Vector2.RIGHT)
	var joined := await Perf.frame_stats(
		t, JOIN_FRAMES, func(i: int) -> void: _join(t, i)
	)
	GameLog.enabled = logging
	_seen(t, joined["ran"], "cone_restarts", "a world that changed under a job")
	_seen(t, joined["ran"], "cone_cap", "past the restart cap")
	t.check(
		_total(joined["ran"], "cone_restarts") >= CAP,
		"a world that changes in every frame restarts a job at least %d times (%d)"
			% [CAP, _total(joined["ran"], "cone_restarts")],
	)


## A solid joins the world in the cone, in a place of its own each time.
func _join(t: TestContext, i: int) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = PhysicsLayers.SOLID
	body.position = Vector2(450.0 + 12.0 * i, 280.0)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = SIZE
	shape.shape = rect
	body.add_child(shape)
	t.world.add_child(body)


## The counter `key` rose in some frame of `ran`.
func _seen(t: TestContext, ran: Array, key: String, what: String) -> void:
	t.check(_total(ran, key) > 0, "%s is counted (%s)" % [what, key])


## A frame that counted a `key` build counted engine work in the same frame.
func _seen_with_units(t: TestContext, ran: Array, key: String) -> void:
	var both := ran.filter(
		func(frame: Dictionary) -> bool:
			return frame.get(key, 0) > 0 and frame.get("cone_units", 0) > 0
	)
	t.check(not both.is_empty(), "a %s frame spent engine work (cone_units)" % key)


func _total(ran: Array, key: String) -> int:
	var sum := 0
	for frame: Dictionary in ran:
		sum += frame.get(key, 0)
	return sum
