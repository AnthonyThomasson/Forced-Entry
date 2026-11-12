extends GameTest
## V1 cost (`docs/player-vision.md`): the work a sliced cone rebuild counts is the work it did, and
## a job can be dropped and started over. `ViewCone` counts engine work in units priced in
## `VisionSliceConfig`: a ray cast (`SightRay.cast`), a region shape query (each ask of `corners`,
## re-asks while it comes back full included) and a far-face probe (`ViewShapes.far_exit`). Here the
## cone's ray and shapes are counting subclasses (the subclass works the queries a read must
## have asked out from the shapes it found, so the count is not the cone's), and for every step
## size, at the default prices and at
## others, in a house and in an arena whose region holds more shapes than the first query asks for:
## - `work_units()` is casts * cost_cast + queries * cost_shape + probes * cost_probe;
## - it is the same at every step size and for `rebuild`;
## - other prices change `work_units()`, never the polygon.
## And `begin` in the middle of a job drops it: the readers keep the last finished job's until the
## new one completes, which is the fresh whole rebuild's; a sliced job with no facing builds only
## the bubble, as the whole one does; `running()` is true exactly while a job is in flight.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const Cone := preload("res://scenes/vision/view_cone.gd")
const Shapes := preload("res://scenes/vision/view_shapes.gd")
const HOUSE := ["garage_home", 7]
const GRID := 3
const EDGE_MARGIN := 40.0
const FACINGS := [20.0, 140.0, 260.0]
const SOLID_MARGIN := 10.0
## The dense arena: anchored wardrobes this far apart (px) over this area, so the region of an eye
## at the origin facing east holds more shapes than the first query's cap, and the eyes tried.
const DENSE_AREA := Rect2(300, -500, 1400, 1000)
const DENSE_STEP := 45.0
const ARENA_EYES := [Vector2(0, 0), Vector2(0, 100), Vector2(-200, -100)]
const ARENA_FACINGS := [0.0, 20.0]
## The prices tried besides the defaults: distinct, so each kind of work is told apart.
const PRICES := [3, 5, 7]
const SIZES := [1, 7, 64, 0]
const MIN_REASKS := 1

var _sight := {
	"fov_degrees": Probe.FOV,
	"view_distance": Probe.REACH,
	"awareness_radius": Probe.BUBBLE,
	"see_over_coverage": Probe.SEE_OVER,
}
var _t: TestContext
var _compared := 0
var _reasked := 0
var _failures: Array[String] = []


func describe() -> Dictionary:
	return {
		"name": "A sliced cone counts the work it did and restarts clean",
		"description": "Casts, shape queries and far-face probes counted by subclasses equal the "
			+ "cone's work units at every step size and price, prices change the count and not "
			+ "the polygon, begin mid-job gives the fresh cone, a sliced job with no facing "
			+ "builds the bubble only, and running() says whether a job is in flight.",
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
		var rect: Rect2 = room["rect"]
		for i in GRID:
			for j in GRID:
				var at := rect.position + Vector2(
					lerpf(EDGE_MARGIN, rect.size.x - EDGE_MARGIN, float(i) / float(GRID - 1)),
					lerpf(EDGE_MARGIN, rect.size.y - EDGE_MARGIN, float(j) / float(GRID - 1)),
				)
				if not Probe.solid_near(t, at, SOLID_MARGIN):
					_compare_all(at, Vector2.RIGHT.rotated(deg_to_rad(FACINGS[(i + j) % 3])))
	_restart_and_bubble(world.rooms[0]["rect"].get_center())
	await Probe.drop_world(t, world)
	await _arena(t)
	t.check(_compared > 0, "premise: %d rebuilds counted" % _compared)
	t.check(
		_reasked >= MIN_REASKS,
		"premise: %d rebuilds asked the region's shapes more than once" % _reasked,
	)
	t.check(
		_failures.is_empty(),
		"%d counts or cones are wrong: %s" % [_failures.size(), "; ".join(_failures.slice(0, 4))],
	)


## The dense arena: the counts, then a restart in the middle of a job.
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
		for degrees: float in ARENA_FACINGS:
			_compare_all(at, Vector2.RIGHT.rotated(deg_to_rad(degrees)))
	_restart_and_bubble(Vector2.ZERO)
	await Probe.drop_world(t, world)


## A counting cone: a ray and shapes that count what they are asked.
func _counting_cone() -> Cone:
	var cone := Cone.new()
	var shapes := CountingShapes.new()
	var ray := CountingRay.new()
	ray.rated = shapes.rated()
	cone.set("_shapes", shapes)
	cone.set("_ray", ray)
	return cone


## Rebuild from `at` whole and at every step size, at the default prices and at `PRICES`, and hold
## the work counted to the work counted by the subclasses and the polygons to the default's.
func _compare_all(at: Vector2, facing: Vector2) -> void:
	var space := Probe.space(_t)
	var whole := _counting_cone()
	whole.rebuild(space, at, facing, [], _sight)
	var default_work := whole.work_units()
	var shapes := whole.get("_shapes") as CountingShapes
	_reasked += int(shapes.asked > 1)
	_check_counts(whole, "whole", at)
	for size: int in SIZES:
		var cone := _counting_cone()
		_run_sliced(cone, space, at, facing, size)
		_check_counts(cone, "size %d" % size, at)
		if (cone.work_units() != default_work
				or cone.cone != whole.cone
				or cone.bubble != whole.bubble):
			_failures.append("size %d at %s: not the whole rebuild's work or polygon" % [size, at])
	var gamble := [
		VisionSliceConfig.cost_cast, VisionSliceConfig.cost_shape, VisionSliceConfig.cost_probe,
	]
	VisionSliceConfig.cost_cast = PRICES[0]
	VisionSliceConfig.cost_shape = PRICES[1]
	VisionSliceConfig.cost_probe = PRICES[2]
	for size: int in SIZES:
		var cone := _counting_cone()
		_run_sliced(cone, space, at, facing, size)
		_check_counts(cone, "priced, size %d" % size, at)
		if cone.cone != whole.cone or cone.bubble != whole.bubble:
			_failures.append("priced, size %d at %s: other prices changed the polygon" % [size, at])
		if cone.work_units() <= default_work:
			_failures.append("priced, size %d at %s: dearer work did not count more" % [size, at])
	VisionSliceConfig.cost_cast = gamble[0]
	VisionSliceConfig.cost_shape = gamble[1]
	VisionSliceConfig.cost_probe = gamble[2]
	_compared += 1


## Step `cone`'s job from `at` to its end by `size` units (0: the default slice).
func _run_sliced(
	cone: Cone,
	space: PhysicsDirectSpaceState2D,
	at: Vector2,
	facing: Vector2,
	size: int,
) -> void:
	var units := size if size > 0 else VisionSliceConfig.slice_units
	cone.begin(space, at, facing, [], _sight)
	var steps := 0
	while not cone.step(units) and steps < 1_000_000:
		steps += 1


## `cone`'s work units against the counts of its subclasses, priced as `VisionSliceConfig` now is.
func _check_counts(cone: Cone, what: String, at: Vector2) -> void:
	var ray := cone.get("_ray") as CountingRay
	var shapes := cone.get("_shapes") as CountingShapes
	var want := (
		ray.casts * VisionSliceConfig.cost_cast
		+ shapes.asked * VisionSliceConfig.cost_shape
		+ shapes.probes * VisionSliceConfig.cost_probe
	)
	if cone.work_units() != want:
		_failures.append(
			"%s at %s: %d units, counted %d (%d casts, %d queries, %d probes)"
			% [what, at, cone.work_units(), want, ray.casts, shapes.asked, shapes.probes]
		)


## `begin` in the middle of a job, a sliced job with no facing, and `running()`.
func _restart_and_bubble(at: Vector2) -> void:
	var space := Probe.space(_t)
	var first := at + Vector2(30.0, 10.0)
	var second := at + Vector2(-20.0, 15.0)
	var whole := Cone.new()
	whole.rebuild(space, second, Vector2.UP, [], _sight)
	var cone := Cone.new()
	if cone.running():
		_failures.append("running() before any begin")
	cone.rebuild(space, first, Vector2.RIGHT, [], _sight)
	var held := [cone.cone, cone.bubble, cone.eye]
	cone.begin(space, first + Vector2(5.0, 0.0), Vector2.RIGHT, [], _sight)
	var in_flight := not cone.step(7) and cone.running()
	cone.step(7)
	cone.begin(space, second, Vector2.UP, [], _sight)
	if not (in_flight and cone.running()):
		_failures.append("running() false while a job is in flight")
	if [cone.cone, cone.bubble, cone.eye] != held:
		_failures.append("a restarted job changed what a reader sees before it completed")
	var steps := 0
	while not cone.step(7) and steps < 1_000_000:
		steps += 1
		if [cone.cone, cone.bubble, cone.eye] != held:
			_failures.append("a job changed what a reader sees before it completed")
			break
	if (cone.running()
			or cone.eye != second
			or cone.cone != whole.cone
			or cone.bubble != whole.bubble):
		_failures.append("a restarted job is not the fresh whole rebuild")
	var bubble_only := Cone.new()
	bubble_only.rebuild(space, second, Vector2.ZERO, [], _sight)
	cone.begin(space, second, Vector2.ZERO, [], _sight)
	steps = 0
	while not cone.step(1) and steps < 1_000_000:
		steps += 1
	if not cone.cone.is_empty() or cone.bubble != bubble_only.bubble or cone.bubble.is_empty():
		_failures.append("a sliced job with no facing is not the bubble alone")
	if cone.running() or not cone.step(1):
		_failures.append("running() true after the job completed")


## `ViewShapes` that counts the shape queries a read must have asked, worked out from how many
## shapes
## the region holds (a query asks for `FIRST_RESULTS`, and again for `GROWTH` times as many while
## it comes back full), and the far-face probes.
class CountingShapes:
	extends Shapes

	var asked := 0
	var probes := 0

	func _shapes_in_reach(space: PhysicsDirectSpaceState2D) -> Array[Dictionary]:
		var hits := super(space)
		var cap := FIRST_RESULTS
		asked += 1
		while hits.size() >= cap:
			cap *= GROWTH
			asked += 1
		return hits

	func far_exit(space: PhysicsDirectSpaceState2D, hit: Dictionary, dir: Vector2) -> float:
		probes += 1
		return super(space, hit, dir)


## A `SightRay` that counts the rays cast through `cast`.
class CountingRay:
	extends SightRay

	var casts := 0

	func cast(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> Dictionary:
		casts += 1
		return super(space, from, to)
