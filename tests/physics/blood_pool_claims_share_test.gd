extends GameTest
## The bleed-out pools that still have cells to claim share FLOW_CLAIMS_PER_FRAME a physics
## frame (#194 perf-spike): one pool claims at most 16 a frame and has all 225 within ~16 frames;
## k pools together claim at most max(16, k) a frame, the remainder to the first in list order, and
## all finish; a pool freed mid-claim raises the others' share; the claimer list empties with its
## world; and a pool shows blood within a few frames however many die together.

const BloodPool = preload("res://scenes/physics/blood/blood_pool.gd")
const AT := Vector2(200, 150)
const CELLS := 225


func describe() -> Dictionary:
	return {
		"name": "Bleed-out pools share the per-frame flow claims, and show at once",
		"description": "One pool claims at most 16 cells a frame and all 225 in about 16 frames; "
			+ "four share 16 (their shares sum to no more) and all finish; freeing one raises the "
			+ "others' share; no claimer outlives its world; eight pools dying together each "
			+ "show blood within three frames.",
		"tags": ["blood", "pool", "perf"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", true)


func run(t: TestContext) -> void:
	await t.frames(2)
	t.expect_eq(BloodPool.claimer_count(), 0, "premise: no pool is claiming")
	await _one_pool(t)
	await _four_pools(t)
	await _one_freed(t)
	_no_claimer_outlives_the_world(t)
	await _eight_show_at_once(t)


func _pools(t: TestContext, count: int, parent: Node = null) -> Array:
	var anchor := Node2D.new()
	t.world.add_child(anchor)
	anchor.global_position = AT
	var out: Array = []
	for i in count:
		out.append(BloodSpawner.bleed(parent if parent != null else t.world, anchor, []))
	anchor.queue_free()
	return out


## Claims each pool made over the next physics frame.
func _step(t: TestContext, pools: Array) -> Array[int]:
	var before: Array[int] = []
	for p in pools:
		before.append(p.flow.cells.size())
	await t.frames(1)
	var made: Array[int] = []
	for i in pools.size():
		made.append(pools[i].flow.cells.size() - before[i])
	return made


func _one_pool(t: TestContext) -> void:
	var pool: Node = _pools(t, 1)[0]
	var frames := 0
	while pool.flow.cells.size() < CELLS and frames < 40:
		var made := await _step(t, [pool])
		frames += 1
		t.check(made[0] <= BloodPool.FLOW_CLAIMS_PER_FRAME, "one pool claimed %d" % made[0])
	t.expect_eq(pool.flow.cells.size(), CELLS, "one pool claims all its cells")
	t.check(frames <= 17, "in about 16 frames (%d)" % frames)
	pool.free()
	await t.frames(1)


func _four_pools(t: TestContext) -> void:
	var pools := _pools(t, 4)
	var frames := 0
	var worst := 0
	var shares_fit := true
	while frames < 200 and pools.any(func(p): return p.flow.cells.size() < CELLS):
		var made := await _step(t, pools)
		frames += 1
		worst = maxi(worst, made.reduce(func(a, b): return a + b, 0))
		shares_fit = shares_fit and made.all(func(m): return m <= 4)
	t.check(worst <= BloodPool.FLOW_CLAIMS_PER_FRAME, "four pools claimed %d in a frame" % worst)
	t.check(shares_fit, "each of four pools claimed at most its share (4)")
	t.check(
		pools.all(func(p): return p.flow.cells.size() == CELLS),
		"all four pools claim every cell (%d frames)" % frames,
	)
	for p in pools:
		p.free()
	await t.frames(2)
	t.expect_eq(BloodPool.claimer_count(), 0, "the finished and freed pools are not claiming")


func _one_freed(t: TestContext) -> void:
	var pools := _pools(t, 4)
	await t.frames(6)
	var made := await _step(t, pools)
	t.check(made.max() <= 4 and made.min() >= 1, "four pools claim 4 each (%s)" % str(made))
	pools[3].free()
	var rest: Array = pools.slice(0, 3)
	await t.frames(1)
	made = await _step(t, rest)
	t.check(made.max() >= 5, "three pools claim 5 or 6 (%s)" % str(made))
	t.expect_eq(
		made.reduce(func(a, b): return a + b, 0),
		BloodPool.FLOW_CLAIMS_PER_FRAME,
		"the three take the whole 16, the first in list order the remainder",
	)
	t.check(made[0] >= made[2], "the first pool in list order has the remainder (%s)" % str(made))
	for p in rest:
		p.free()
	await t.frames(2)


func _no_claimer_outlives_the_world(t: TestContext) -> void:
	var holder := Node2D.new()
	t.world.add_child(holder)
	var before := BloodPool.claimer_count()
	_pools(t, 3, holder)
	t.expect_eq(BloodPool.claimer_count(), before + 3, "three pools claim under the holder")
	holder.free()
	t.expect_eq(BloodPool.claimer_count(), before, "freeing the world leaves no claimer behind")


func _eight_show_at_once(t: TestContext) -> void:
	var pools := _pools(t, 8)
	await t.frames(3)
	var showing := pools.filter(func(p): return p.flow.fill(Vector2i.ZERO) > 0.0).size()
	t.expect_eq(showing, 8, "eight pools dying together all show blood within 3 frames")
	for p in pools:
		p.free()
	await t.frames(2)
