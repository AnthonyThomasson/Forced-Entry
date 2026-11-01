extends GameTest
## V1 (`docs/player-vision.md`): the cone is complete however many blockers lie in its reach. An
## arena holds more solid shapes within the view distance than any fixed query cap would carry
## (the premise counts them): 21 wardrobes (tall) laid on an arc 1800 px in front of the eye, and
## hundreds more behind the eye, to its sides and in the shadow of the arc. Beside each wardrobe's
## corners, samples behind the corner must be outside the polygon and samples the eye sees must be
## inside it, so no wardrobe is left without its corner rays.
##
## It reads (tests/_vision/vision_probe.gd) the `PlayerView` of the world: `sees(point)`.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const EYE_AT := Vector2.ZERO
## The wardrobes in view: this many, a step (degrees) apart round the facing, on an arc this far
## from the eye (px), each turned (45 wide, 90 across) to face the eye.
const ARC_COUNT := 21
const ARC_STEP := 4.5
const ARC_RADIUS := 1800.0
const PIECE_HALF := Vector2(22.5, 45.0)
## Hidden pieces: this many in the shadow of each wardrobe, this far (px) apart from the arc
## outward; a grid behind the eye; two grids to its north and south, outside the cone.
const SHADOW_COUNT := 6
const SHADOW_FROM := 150.0
const SHADOW_STEP := 70.0
## At least this many solid shapes must lie in the eye's reach, or the test proves nothing.
const MIN_IN_REACH := 700
## Samples near a corner: angles (degrees) either side of its direction, distances (px) past it.
const SAMPLE_ANGLES := [-1.0, -0.3, 0.3, 1.0]
const SAMPLE_DISTANCES := [40.0, 120.0, 300.0, 600.0]
const SOLID_MARGIN := 4.0
const SIDE_MARGIN := 2.5
const BEHIND_MARGIN := 3.0
const MIN_BEHIND := 300
const MIN_SEEN := 300

var _t: TestContext
var _view: PlayerView
var _exclude: Array = []
var _leaks := 0
var _missed := 0
var _behind := 0
var _seen := 0


func describe() -> Dictionary:
	return {
		"name": "The view's cone is exact with more blockers in reach than a query cap carries",
		"description": "Over 700 solid shapes within the view distance, and beside the corners of "
			+ "21 wardrobes in view no point behind a corner is in the polygon and every point "
			+ "the eye sees is.",
		"tags": ["vision"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(-100, -100, 200, 200), { "walls": false })
	s.switch(&"nav.rebake", false)
	s.switch(&"vision.enabled", true)
	s.actor(&"eye", &"puppet", EYE_AT)
	s.view(&"eye")
	_grid(s, &"behind", Rect2(-2000, -1000, 1700, 2000), Vector2(100, 120))
	_grid(s, &"north", Rect2(-800, -2200, 1600, 900), Vector2(100, 100))
	_grid(s, &"south", Rect2(-800, 1300, 1600, 900), Vector2(100, 100))
	for i in ARC_COUNT:
		var angle := _arc_angle(i)
		for k in SHADOW_COUNT:
			var at := _arc_at(angle, ARC_RADIUS + SHADOW_FROM + float(k) * SHADOW_STEP)
			s.object(&"shadow%d_%d" % [i, k], "wardrobe", at, { "rotated": true })
	# The wardrobes in view are declared last, so they are the last bodies the physics space holds
	# (a capped query drops the last it finds).
	for i in ARC_COUNT:
		var at := _arc_at(_arc_angle(i), ARC_RADIUS)
		s.object(&"arc%d" % i, "wardrobe", at, { "rotated": true })


func run(t: TestContext) -> void:
	_t = t
	var eye := t.actor(&"eye")
	_view = Probe.view(t)
	if not t.require(_view != null, "the world has a view"):
		return
	await t.frames(2)
	if not t.require(await Probe.place(t, eye, EYE_AT, Vector2.RIGHT), "the eye faces east"):
		return
	_exclude = [eye.get_rid()]
	var in_reach := _shapes_in_reach()
	t.check(
		in_reach >= MIN_IN_REACH,
		"premise: %d solid shapes in the eye's reach (%d needed)" % [in_reach, MIN_IN_REACH],
	)
	for i in ARC_COUNT:
		_check_piece(_arc_at(_arc_angle(i), ARC_RADIUS))
	t.check(_leaks == 0, "%d of %d points behind a corner are inside the cone" % [_leaks, _behind])
	t.check(_missed == 0, "%d of %d seen points are outside the cone" % [_missed, _seen])
	t.check(_behind >= MIN_BEHIND, "premise: %d points behind corners checked" % _behind)
	t.check(_seen >= MIN_SEEN, "premise: %d seen points checked" % _seen)


func _arc_angle(index: int) -> float:
	return deg_to_rad((float(index) - float(ARC_COUNT - 1) * 0.5) * ARC_STEP)


func _arc_at(angle: float, radius: float) -> Vector2:
	return EYE_AT + Vector2.from_angle(angle) * radius


## Fill `area` with wardrobes `step` apart, ids `<name>_<n>`.
func _grid(s: TestSetup, name: String, area: Rect2, step: Vector2) -> void:
	var n := 0
	var y := area.position.y
	while y < area.end.y:
		var x := area.position.x
		while x < area.end.x:
			s.object(
				StringName("%s_%d" % [name, n]),
				"wardrobe",
				Vector2(x, y),
				{ "rotated": true },
			)
			n += 1
			x += step.x
		y += step.y


## How many solid shapes the eye's reach holds, asked with a cap far over any count.
func _shapes_in_reach() -> int:
	var circle := CircleShape2D.new()
	circle.radius = Probe.REACH
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, EYE_AT)
	query.collision_mask = PhysicsLayers.SOLID
	query.exclude = _exclude
	return Probe.space(_t).intersect_shape(query, 100_000).size()


## Test the samples beside each corner of the wardrobe centred at `centre`.
func _check_piece(centre: Vector2) -> void:
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner: Vector2 = centre + Vector2(sx * PIECE_HALF.x, sy * PIECE_HALF.y)
			var to := corner - EYE_AT
			for angle: float in SAMPLE_ANGLES:
				var dir := to.normalized().rotated(deg_to_rad(angle))
				for past: float in SAMPLE_DISTANCES:
					_test(EYE_AT + dir * (to.length() + past))


## One sample: behind a corner it must be outside the polygon, seen it must be inside.
func _test(sample: Vector2) -> void:
	if Probe.solid_near(_t, sample, SOLID_MARGIN):
		return
	var hit := Probe.blocker(_t, EYE_AT, sample, _exclude)
	if hit.is_empty():
		_test_seen(sample)
	elif EYE_AT.distance_to(hit["position"]) < EYE_AT.distance_to(sample) - BEHIND_MARGIN:
		_test_behind(sample)


func _test_seen(sample: Vector2) -> void:
	if not _clear_either_side(sample):
		return
	_seen += 1
	if not _view.sees(sample):
		_missed += 1
		if _missed <= 5:
			_t.trace("missed sample %s" % sample, 1.0)


func _test_behind(sample: Vector2) -> void:
	if not _blocked_either_side(sample):
		return
	_behind += 1
	if _view.sees(sample):
		_leaks += 1
		if _leaks <= 5:
			_t.trace("leak sample %s" % sample, 1.0)


func _side(sample: Vector2) -> Vector2:
	return (sample - EYE_AT).orthogonal().normalized() * SIDE_MARGIN


func _clear_either_side(sample: Vector2) -> bool:
	var side := _side(sample)
	return (
		Probe.blocker(_t, EYE_AT, sample + side, _exclude).is_empty()
		and Probe.blocker(_t, EYE_AT, sample - side, _exclude).is_empty()
	)


func _blocked_either_side(sample: Vector2) -> bool:
	var side := _side(sample)
	return (
		not Probe.blocker(_t, EYE_AT, sample + side, _exclude).is_empty()
		and not Probe.blocker(_t, EYE_AT, sample - side, _exclude).is_empty()
	)
