extends GameTest
## V1 cost (`docs/player-vision.md`): a cone built in slices is the cone built whole. `ViewCone`
## runs a rebuild as stages stepped by work units (`begin`, then `step(units)` until it says done,
## one unit a ray cast, region shape query or far-face probe, cut only between rays), and `rebuild`
## is `begin` plus `step` to the end. A persistent cone stepped by 1, 7, 64 units and by the
## default slice (`VisionSliceConfig.slice_units`) is held, exactly (not within a tolerance: the
## same
## operations on the same numbers), to a persistent cone rebuilt whole, over
## - a grid of eyes and facings in generated houses (a few floorplans and seeds);
## - rooms whose walls and pieces are dented again and again (the colliders re-cut into slivers);
## - an arena with hundreds of tall blockers in reach, so a job runs over many slices.
## While a job is in flight nothing a reader sees (`cone`, `bubble`, `eye`, `corner_rays`,
## `corners_read`) changes: they are swapped in together when it completes.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const Cone := preload("res://scenes/vision/view_cone.gd")
## The houses: floorplan and seed.
const HOUSES := [
	["garage_home", 7],
	["bungalow", 5],
]
## The eyes of a room: this many columns and rows inside it, each this far (px) from its walls at
## least, and the facings (degrees) each looks along (off the axes, as `cone_same_after_savings`).
const GRID := 3
const EDGE_MARGIN := 40.0
const FACINGS := [20.0, 140.0, 260.0]
const SOLID_MARGIN := 10.0
## The dents: this many volleys of this many hits each, and the eyes tried after each.
const VOLLEYS := 4
const HITS_PER_VOLLEY := 50
const SCATTERED := 40
const NEAR := 220.0
const REST_SPEED := 0.5
const REST_SPIN := 0.01
const SETTLE_WAIT := 3.0
## The blockers' arena: wardrobes on a grid this far apart (px) over this area, and the eyes
## (px, degrees) that look into them.
const GRID_AREA := Rect2(-1800, -1200, 3600, 2400)
const GRID_STEP := Vector2(130, 130)
const ARENA_EYES := [
	Vector2(0, 0), Vector2(-300, 200), Vector2(250, -400), Vector2(500, 300), Vector2(-700, -100),
	Vector2(100, 650),
]
const ARENA_FACINGS := [0.0, 75.0, 200.0, 310.0]
## The slice sizes tried besides the default (`0`): units a `step`.
const SIZES := [1, 7, 64, 0]
## At least this many rebuilds must be compared, or the test proves nothing, and at least this
## many of them must have taken more than one step at the default slice.
const MIN_PAIRS := 400
const MIN_SLICED := 20

var _sight := {
	"fov_degrees": Probe.FOV,
	"view_distance": Probe.REACH,
	"awareness_radius": Probe.BUBBLE,
	"see_over_coverage": Probe.SEE_OVER,
}
var _t: TestContext
var _pairs := 0
var _sliced := 0
var _exclude: Array = []
var _mismatches: Array[String] = []
## One whole cone and one stepped cone for each size: each persists, so what a cone keeps from one
## rebuild to the next is in play.
var _whole := Cone.new()
var _stepped: Dictionary = {}


func describe() -> Dictionary:
	return {
		"name": "A cone built in slices is the cone built whole",
		"description": "Stepped by 1, 7, 64 and the default slice's units, a rebuild's cone, "
			+ "bubble, eye and ray counts equal a whole rebuild's exactly, over generated "
			+ "houses, dented rooms and an arena of hundreds of blockers, and nothing a reader "
			+ "sees changes before the job completes.",
		"tags": ["vision"],
		"timeout": 240.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(80_000, 80_000, 100, 100), { "walls": false })
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	_t = t
	for size: int in SIZES:
		_stepped[size] = Cone.new()
	for entry in HOUSES:
		var setup := TestSetup.new()
		setup.house(entry[1], entry[0])
		setup.switch(&"nav.rebake", false)
		var world: Node2D = await Probe.build_world(t, setup)
		_compare_rooms(world)
		await Probe.drop_world(t, world)
	await _compare_dents(t)
	await _compare_arena(t)
	t.check(_pairs >= MIN_PAIRS, "premise: %d rebuilds compared (%d needed)" % [_pairs, MIN_PAIRS])
	t.check(
		_sliced >= MIN_SLICED,
		"premise: %d rebuilds took more than one default slice (%d needed)" % [_sliced, MIN_SLICED],
	)
	t.check(
		_mismatches.is_empty(),
		"%d sliced cones differ from the whole one: %s"
		% [_mismatches.size(), "; ".join(_mismatches.slice(0, 4))],
	)


func _compare_rooms(world: Node2D) -> void:
	for room: Dictionary in world.rooms:
		var rect: Rect2 = room["rect"]
		for i in GRID:
			for j in GRID:
				var at := rect.position + Vector2(
					lerpf(EDGE_MARGIN, rect.size.x - EDGE_MARGIN, float(i) / float(GRID - 1)),
					lerpf(EDGE_MARGIN, rect.size.y - EDGE_MARGIN, float(j) / float(GRID - 1)),
				)
				if Probe.solid_near(_t, at, SOLID_MARGIN):
					continue
				for degrees: float in FACINGS:
					_compare(at, Vector2.RIGHT.rotated(deg_to_rad(degrees)))


## Walls and pieces struck again and again, the cones compared after each volley.
func _compare_dents(t: TestContext) -> void:
	var setup := TestSetup.new()
	setup.layout(Probe.ROOMS, [Probe.DOOR])
	setup.switch(&"nav.rebake", false)
	setup.switch(&"physics.debris", false)
	setup.object(&"wardrobe", "wardrobe", Probe.WARDROBE_AT, { "rotated": true })
	setup.object(&"bookcase", "bookshelf", Vector2(300, 60))
	var world: Node2D = await Probe.build_world(t, setup)
	var targets: Array[Node2D] = []
	for node in world.find_children("*", "StaticBody2D", true, false):
		if node.has_method("wall_segments"):
			targets.append(node)
	targets.append(world.objects[&"wardrobe"])
	targets.append(world.objects[&"bookcase"])
	var shapes_before := Probe.collision_shapes(targets)
	var rng := RandomNumberGenerator.new()
	rng.seed = Probe.HIT_SEED
	_compare_rooms(world)
	for volley in VOLLEYS:
		var target := targets[volley % targets.size()]
		var place := rng.randf()
		var struck := Vector2.ZERO
		for _k in HITS_PER_VOLLEY:
			struck = _strike(target, rng, place)
		await t.frames(3)
		if not t.require(
			await t.until(func() -> bool: return _at_rest(targets), SETTLE_WAIT),
			"premise: the struck pieces came to rest",
		):
			return
		_compare_rooms(world)
		for _i in SCATTERED:
			var at := struck + Vector2.from_angle(rng.randf() * TAU) * rng.randf() * NEAR
			if not Probe.solid_near(t, at, SOLID_MARGIN):
				_compare(at, Vector2.from_angle(rng.randf() * TAU))
	t.check(
		Probe.collision_shapes(targets) > shapes_before,
		"premise: the dents cut the colliders into more shapes",
	)
	await Probe.drop_world(t, world)


## Hundreds of tall blockers in the eyes' reach.
func _compare_arena(t: TestContext) -> void:
	var setup := TestSetup.new()
	setup.arena(Rect2(-100, -100, 200, 200), { "walls": false })
	setup.switch(&"nav.rebake", false)
	var n := 0
	var y := GRID_AREA.position.y
	while y < GRID_AREA.end.y:
		var x := GRID_AREA.position.x
		while x < GRID_AREA.end.x:
			if absf(x) > 160.0 or absf(y) > 160.0:
				setup.object(StringName("w%d" % n), "wardrobe", Vector2(x, y), { "rotated": true })
				n += 1
			x += GRID_STEP.x
		y += GRID_STEP.y
	var world: Node2D = await Probe.build_world(t, setup)
	await t.frames(2)
	for at: Vector2 in ARENA_EYES:
		for degrees: float in ARENA_FACINGS:
			_compare(at, Vector2.RIGHT.rotated(deg_to_rad(degrees)))
	await Probe.drop_world(t, world)


## Rebuild `_whole` and each stepped cone from the same place and compare what they hold.
func _compare(at: Vector2, facing: Vector2) -> void:
	var space := Probe.space(_t)
	_whole.rebuild(space, at, facing, _exclude, _sight)
	for size: int in SIZES:
		var units := size if size > 0 else VisionSliceConfig.slice_units
		var cone: Cone = _stepped[size]
		var before := [cone.cone, cone.bubble, cone.eye, cone.corner_rays, cone.corners_read]
		cone.begin(space, at, facing, _exclude, _sight)
		var steps := 1
		while not cone.step(units):
			steps += 1
			if [cone.cone, cone.bubble, cone.eye, cone.corner_rays, cone.corners_read] != before:
				_mismatches.append("size %d: a reader's view changed mid-job at %s" % [size, at])
				return
			if steps > 1_000_000:
				_mismatches.append("size %d: the job at %s never finished" % [size, at])
				return
		if size == 0 and steps > 1:
			_sliced += 1
		_pairs += 1
		var reason := _difference(cone)
		if reason != "":
			_mismatches.append("size %d eye %s facing %s: %s" % [size, at, facing, reason])


## Why a stepped cone differs from `_whole`, or "" when it is the same, exactly.
func _difference(cone: Cone) -> String:
	if cone.eye != _whole.eye:
		return "eye"
	if cone.cone != _whole.cone:
		return "cone"
	if cone.bubble != _whole.bubble:
		return "bubble"
	if cone.corner_rays != _whole.corner_rays or cone.corners_read != _whole.corners_read:
		return "ray counts"
	return ""


func _at_rest(targets: Array[Node2D]) -> bool:
	for target in targets:
		var body := target as RigidBody2D
		if body != null and not body.sleeping and (
			body.linear_velocity.length() > REST_SPEED or absf(body.angular_velocity) > REST_SPIN
		):
			return false
	return true


func _strike(target: Node2D, rng: RandomNumberGenerator, place: float) -> Vector2:
	var at: Vector2
	var normal: Vector2
	if target.has_method("wall_segments"):
		var segments: Array = target.wall_segments()
		var segment: PackedVector2Array = segments[int(place * float(segments.size() - 1))]
		var along: Vector2 = segment[1] - segment[0]
		var along_at := clampf(fposmod(place * 7.0, 1.0) + rng.randf_range(-0.05, 0.05), 0.0, 1.0)
		at = target.to_global(segment[0] + along * along_at)
		normal = along.orthogonal().normalized()
	else:
		var around := Vector2.from_angle(place * TAU + rng.randf_range(-0.4, 0.4))
		at = target.global_position + around * 12.0
		normal = around
	target.take_hit(Probe.hit(at, normal, rng.randf_range(10.0, 40.0)))
	return at
