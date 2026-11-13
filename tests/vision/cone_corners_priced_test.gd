extends GameTest
## V1 cost (`docs/player-vision.md`): the cone's corners are priced at what they cost, so the frame
## a job starts in holds the corners and no full slice of rays. The corners (one region shape query
## and its polygons) cost about as much as a slice of rays (`perf/cone_corner_cost` measures it),
## so `VisionSliceConfig.cost_shape` fills a slice: the start step ends after the corners and the
## rays begin the next frame.
## - `cone`: `begin` and one default step spend the corners' units and cast no ray, over a grid of
##   eyes in a house and in an arena whose region holds more shapes than the first query asks for
##   (a re-ask is priced as a query), and the job then finishes at the whole rebuild's work;
## - `pipeline`: a `ViewPipeline` tick that starts a job (the cone is held, the eye moved) casts no
##   ray and publishes nothing, and the job publishes within `MAX_TICKS` ticks of its start.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const Cone := preload("res://scenes/vision/view_cone.gd")
const Shapes := preload("res://scenes/vision/view_shapes.gd")
const Pipeline :=preload("res://scenes/vision/view_pipeline.gd")
const Watch := preload("res://scenes/vision/view_watch.gd")
const HOUSE := ["garage_home", 7]
const GRID := 3
const EDGE_MARGIN := 40.0
const FACINGS := [20.0, 140.0, 260.0]
const SOLID_MARGIN := 10.0
const DENSE_AREA := Rect2(300, -500, 1400, 1000)
const DENSE_STEP := 45.0
const ARENA_EYES := [Vector2(0, 0), Vector2(0, 100), Vector2(-200, -100)]
## How far the eye moves (px) to make the held cone stale, and the most ticks a job may take.
const MOVE := 30.0
const MAX_TICKS := 6
const MIN_READS := 20

var _sight := {
	"fov_degrees": Probe.FOV,
	"view_distance": Probe.REACH,
	"awareness_radius": Probe.BUBBLE,
	"see_over_coverage": Probe.SEE_OVER,
}
var _t: TestContext
var _reads := 0
var _failures: Array[String] = []


func describe() -> Dictionary:
	return {
		"name": "A job's start frame holds the corners and no full ray slice",
		"description": "The first default step of a cone job spends the corners' units and no "
			+ "ray is cast, in a house and in an arena where the region query is asked again, and "
			+ "a pipeline tick that starts a job casts none and publishes nothing.",
		"tags": ["vision"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(80_000, 80_000, 100, 100), { "walls": false })
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	_t = t
	var setup := TestSetup.new()
	setup.house(HOUSE[1], HOUSE[0])
	setup.switch(&"nav.rebake", false)
	var world: Node2D = await Probe.build_world(t, setup)
	for room: Dictionary in world.rooms:
		_read_room(room["rect"])
	await Probe.drop_world(t, world)
	await _arena(t)
	t.check(_reads >= MIN_READS, "premise: %d starts read (%d needed)" % [_reads, MIN_READS])
	t.check(
		_failures.is_empty(),
		"%d start frames are wrong: %s" % [_failures.size(), "; ".join(_failures.slice(0, 4))],
	)


func _read_room(rect: Rect2) -> void:
	for i in GRID:
		for j in GRID:
			var at := rect.position + Vector2(
				lerpf(EDGE_MARGIN, rect.size.x - EDGE_MARGIN, float(i) / float(GRID - 1)),
				lerpf(EDGE_MARGIN, rect.size.y - EDGE_MARGIN, float(j) / float(GRID - 1)),
			)
			if not Probe.solid_near(_t, at, SOLID_MARGIN):
				_read(at, Vector2.RIGHT.rotated(deg_to_rad(FACINGS[(i + j) % 3])))


func _arena(t: TestContext) -> void:
	var setup := TestSetup.new()
	setup.arena(Rect2(-100, -100, 200, 200), { "walls": false })
	setup.switch(&"nav.rebake", false)
	var definition: Dictionary = WorldGen.object_definition("wardrobe").duplicate()
	definition["anchored"] = true
	var n := 0
	var y := DENSE_AREA.position.y
	while y < DENSE_AREA.end.y:
		var x := DENSE_AREA.position.x
		while x < DENSE_AREA.end.x:
			setup.object(StringName("w%d" % n), definition, Vector2(x, y), { "rotated": true })
			n += 1
			x += DENSE_STEP
		y += DENSE_STEP
	var world: Node2D = await Probe.build_world(t, setup)
	await t.frames(2)
	for at: Vector2 in ARENA_EYES:
		_read(at, Vector2.RIGHT)
	await Probe.drop_world(t, world)


## The start of a job from `at`, as a cone and as a pipeline's.
func _read(at: Vector2, facing: Vector2) -> void:
	_start_of_a_cone(at, facing)
	_start_of_a_pipeline(at, facing)
	_reads += 1


## One default step from `begin`: the corners' units, no cast, the job still in flight; the rest
## brings the work to the whole rebuild's.
func _start_of_a_cone(at: Vector2, facing: Vector2) -> void:
	var space := Probe.space(_t)
	var whole := Cone.new()
	whole.rebuild(space, at, facing, [], _sight)
	var cone := _counting_cone()
	cone.begin(space, at, facing, [], _sight)
	var done := cone.step(VisionSliceConfig.slice_units)
	var ray := cone.get("_ray") as CountingRay
	var shapes := cone.get("_shapes") as CountingShapes
	var corners := shapes.asked * VisionSliceConfig.cost_shape
	if ray.casts > 0 or done or cone.work_units() != corners:
		_failures.append(
			"cone at %s: %d casts, %d units for %d queries, done %s"
			% [at, ray.casts, cone.work_units(), shapes.asked, done]
		)
	if corners < VisionSliceConfig.slice_units:
		_failures.append("cone at %s: the corners (%d units) do not fill a slice" % [at, corners])
	var steps := 0
	while not cone.step(VisionSliceConfig.slice_units) and steps < 1_000_000:
		steps += 1
	if cone.work_units() != whole.work_units() or cone.cone != whole.cone:
		_failures.append("cone at %s: the rest of the job is not the whole rebuild" % at)


## A pipeline holding a cone of `at`, the eye then moved: the tick that starts the job casts
## nothing and publishes nothing, and the job publishes soon.
func _start_of_a_pipeline(at: Vector2, facing: Vector2) -> void:
	var space := Probe.space(_t)
	var cone := _counting_cone()
	var watch := Watch.new()
	watch.attach(_t.world.get_tree(), [])
	var pipeline := Pipeline.new(cone, watch)
	pipeline.tick(space, at, facing, [], _sight)
	var ray := cone.get("_ray") as CountingRay
	ray.casts = 0
	var moved := at + Vector2(MOVE, 0.0)
	var published := pipeline.published
	var started := pipeline.started
	pipeline.tick(space, moved, facing, [], _sight)
	if pipeline.started != started + 1 or pipeline.published != published or ray.casts > 0:
		_failures.append(
			"pipeline at %s: %d starts, %d publishes, %d casts in the start tick"
			% [at, pipeline.started - started, pipeline.published - published, ray.casts]
		)
	var ticks := 1
	while pipeline.published == published and ticks < MAX_TICKS:
		pipeline.tick(space, moved, facing, [], _sight)
		ticks += 1
	if pipeline.published == published:
		_failures.append("pipeline at %s: not published in %d ticks" % [at, MAX_TICKS])
	watch.detach()


## A cone whose ray and shapes count what they are asked.
func _counting_cone() -> Cone:
	var cone := Cone.new()
	var shapes := CountingShapes.new()
	var ray := CountingRay.new()
	ray.rated = shapes.rated()
	cone.set("_shapes", shapes)
	cone.set("_ray", ray)
	return cone


## `ViewShapes` that counts the shape queries a read must have asked (a query asks for
## `FIRST_RESULTS`, and again for `GROWTH` times as many while it comes back full).
class CountingShapes:
	extends Shapes

	var asked := 0

	func _shapes_in_reach(space: PhysicsDirectSpaceState2D) -> Array[Dictionary]:
		var hits := super(space)
		var cap := FIRST_RESULTS
		asked += 1
		while hits.size() >= cap:
			cap *= GROWTH
			asked += 1
		return hits


## A `SightRay` that counts the rays cast through `cast`.
class CountingRay:
	extends SightRay

	var casts := 0

	func cast(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> Dictionary:
		casts += 1
		return super(space, from, to)
