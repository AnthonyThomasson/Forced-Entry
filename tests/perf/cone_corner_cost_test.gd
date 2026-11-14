extends GameTest
## Measures what the cone's corners cost against what a unit of ray work costs (#195 cone-start;
## `docs/player-vision.md` "Measured cost", the vision skill's `cone-job.md`), the figure
## `VisionSliceConfig.cost_shape` is priced from. In the match guards' district
## (`Perf.configure_match`, the 10v10 at its spawn) a bare `ViewCone` is begun from a grid of
## eyes and facings, and for each the corners' step (`begin` and `step(1)`: the region shape query,
## its polygons, the dedupe and the lows' leave-out) is timed apart from the rest of the job
## (`step` to the end: the rays, the far-face probes, the visibility casts, the sort). The unit
## the rest costs is its time over the work it counted; the corners' price is their time over that
## unit. Each eye is taken `REPEATS` times and the median kept, so a hiccup of the machine falls
## out. The test logs the medians (`PERF cone corners: ...`) and holds the price to the measured
## ratio within `PRICE_SLACK`, so a retune of the cone that makes the corners much cheaper or
## dearer than their price fails here, where the price is made again. Timing: run it on a quiet
## machine (`--quiet`), a loaded run says nothing (`perf.md`).

const Perf := preload("res://tests/_perf/perf_probe.gd")
const Probe := preload("res://tests/_vision/vision_probe.gd")
const Cone := preload("res://scenes/vision/view_cone.gd")
const PER_SIDE := 10
const GRID := 9
const FACINGS := 3
const REPEATS := 5
const SOLID_CLEAR := 20.0
const INSET := 80.0
## The price may differ from the measured ratio by this factor either way.
const PRICE_SLACK := 2.0
## Fewest eyes the premise needs.
const MIN_EYES := 20
## Health of the viewer, so it lives through the read.
const HEALTH := 1_000_000.0


func describe() -> Dictionary:
	return {
		"name": "The cone's corners are priced at what they cost",
		"description": "In the match district, the corners of a cone job (the region shape query) "
			+ "timed against a unit of the rest of the job: VisionSliceConfig.cost_shape is within "
			+ "a factor of the measured ratio.",
		"tags": ["vision", "scripted"],
		"timeout": 120.0,
		"allowed_logs": Perf.MATCH_LOGS,
	}


func configure(s: TestSetup) -> void:
	Perf.configure_match(s, PER_SIDE)
	s.actor(&"viewed", &"puppet", Vector2.ZERO, { "max_health": HEALTH, "health": HEALTH })


func run(t: TestContext) -> void:
	Perf.warm_sounds()
	var bounds := WorldGen.district_bounds(t.world.district).grow(-INSET)
	if not t.require(bounds.has_area(), "premise: a district"):
		return
	await t.seconds(2.0)
	var reads := _read_grid(t, bounds, (t.actor(&"viewed") as Node2D).sight())
	t.check(
		reads["ratio"].size() >= MIN_EYES * FACINGS,
		"premise: %d eyes read" % reads["ratio"].size(),
	)
	var ratio := _median(reads["ratio"])
	GameLog.say(
		(
			"PERF cone corners: %d reads, corners median %.0f us, unit median %.2f us, corners = "
			+ "%.0f units (median of ratios; p25 %.0f, p75 %.0f), corner units median %.0f, the "
			+ "rest median %.0f units, cost_shape now %d, job ticks: median %.0f, max %.0f, "
			+ "over three %.0f %% (corners priced 1: median %.0f, max %.0f, over three %.0f %%)"
		)
		% [
			reads["ratio"].size(), _median(reads["corners_us"]), _median(reads["unit_us"]), ratio,
			_quantile(reads["ratio"], 0.25), _quantile(reads["ratio"], 0.75),
			_median(reads["corner_units"]), _median(reads["rest_units"]),
			VisionSliceConfig.cost_shape,
			_median(reads["ticks"]), _quantile(reads["ticks"], 1.0), _over_three(reads["ticks"]),
			_median(reads["ticks_unpriced"]), _quantile(reads["ticks_unpriced"], 1.0),
			_over_three(reads["ticks_unpriced"]),
		]
	)
	t.trace("cone corners in units", ratio)
	var price := float(VisionSliceConfig.cost_shape)
	t.check(
		price * PRICE_SLACK >= ratio and price <= ratio * PRICE_SLACK,
		"cost_shape %d is not within %.0fx of the corners' measured %.0f units"
		% [VisionSliceConfig.cost_shape, PRICE_SLACK, ratio],
	)


## Every clear eye of a grid over `bounds` with `FACINGS` facings, read by `_measure`: the
## arrays `corners_us`, `unit_us`, `ratio`, `corner_units` and `rest_units`, one entry a read.
func _read_grid(t: TestContext, bounds: Rect2, sight: Dictionary) -> Dictionary:
	var space := Probe.space(t)
	var reads := {
		"corners_us": [],
		"unit_us": [],
		"ratio": [],
		"corner_units": [],
		"rest_units": [],
		"ticks": [],
		"ticks_unpriced": [],
	}
	for i in GRID:
		for j in GRID:
			var at := bounds.position + bounds.size * Vector2(i, j) / float(GRID - 1)
			if Probe.solid_near(t, at, SOLID_CLEAR):
				continue
			for k in FACINGS:
				var facing := Vector2.RIGHT.rotated(TAU * float(k) / float(FACINGS) + 0.3)
				var read := _measure(space, at, facing, sight)
				for key: String in reads:
					reads[key].append(read[key])
	return reads


## Begin a bare job from `at` and time the corners and then the rest, the median of `REPEATS`.
func _measure(
	space: PhysicsDirectSpaceState2D,
	at: Vector2,
	facing: Vector2,
	sight: Dictionary,
) -> Dictionary:
	var corners: Array[float] = []
	var rest: Array[float] = []
	var corner_units := 0
	var rest_units := 0
	for _r in REPEATS:
		var cone := Cone.new()
		var t0 := Time.get_ticks_usec()
		cone.begin(space, at, facing, [], sight)
		cone.step(1)
		var t1 := Time.get_ticks_usec()
		corner_units = cone.work_units()
		cone.step(1 << 60)
		var t2 := Time.get_ticks_usec()
		corners.append(float(t1 - t0))
		rest.append(float(t2 - t1))
		rest_units = cone.work_units() - corner_units
	var unit := _median(rest) / maxf(float(rest_units), 1.0)
	return {
		"corners_us": _median(corners),
		"unit_us": unit,
		"ratio": _median(corners) / maxf(unit, 0.001),
		"corner_units": corner_units,
		"rest_units": rest_units,
		"ticks": _ticks(space, at, facing, sight),
		"ticks_unpriced": _ticks(space, at, facing, sight, 1),
	}


## The physics ticks a job from `at` takes at the default slice and prices, or with the corners at
## `corners_price` when given (the pipeline's: the first tick starts it and steps it, each next
## steps it on): the cone shown is up to twice this less one frames old (`docs/player-vision.md` V1:
## 2 to 4 frames old is three ticks).
func _ticks(
	space: PhysicsDirectSpaceState2D,
	at: Vector2,
	facing: Vector2,
	sight: Dictionary,
	corners_price := 0,
) -> int:
	var kept := VisionSliceConfig.cost_shape
	if corners_price > 0:
		VisionSliceConfig.cost_shape = corners_price
	var cone := Cone.new()
	cone.begin(space, at, facing, [], sight)
	var ticks := 1
	while not cone.step(VisionSliceConfig.slice_units) and ticks < 100:
		ticks += 1
	VisionSliceConfig.cost_shape = kept
	return ticks


## The share (percent) of `ticks` over three.
func _over_three(ticks: Array) -> float:
	var over := ticks.filter(func(n: int) -> bool: return n > 3)
	return 100.0 * float(over.size()) / float(ticks.size())


func _median(values: Array) -> float:
	return _quantile(values, 0.5)


func _quantile(values: Array, q: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[clampi(int(float(sorted.size()) * q), 0, sorted.size() - 1)])
