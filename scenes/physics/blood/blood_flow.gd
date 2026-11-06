class_name BloodFlow
extends RefCounted
## Physics System, blood: a liquid flood-fill for a dead body's bleed-out: blood claims grid cells
## outward from where it leaves the body, cheapest-first, so the puddle is one continuous shape.
## Noise makes some directions cheap and others dear (fingers and bays instead of a disc), and cells
## overlapping a wall or furniture collider are never filled, so the blood wraps around them and
## creeps into gaps. Positions are local to the owning pool. The draw layer reads `cells` and
## `fill()`.

## The eight grid neighbours a cell flows into.
const NEIGHBORS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

## Claimed cells: Vector2i -> the flow cost at which blood arrives there. They are all claimed up
## front (a few per frame); a front then sweeps through cost-space over time, so each cell's fill
## level rises continuously and the pool's edge moves smoothly instead of cells popping in.
var cells: Dictionary = {}
## Blood dragged out of the pool (BloodSmear): cell -> fill 0..1, for cells the flood-fill never
## claimed. Drawn with the pool, so a smear grows out of the pool's own outline.
var trail: Dictionary = {}
## Where the front has reached, in cost units.
var front := 0.0
## How far the sweep has run, 0..1 of the duration.
var _progress := 0.0
## The highest flow cost claimed so far; the front sweeps up to it.
var _last_cost := 0.0
## Side (px) of a grid cell.
var _size: float
## Unit direction the flow leans toward.
var _aim: Vector2
## Collider RIDs the blocked-cell queries ignore (the body the blood leaves).
var _exclude: Array
## Roughens the per-cell flow cost into lobes.
var _noise := FastNoiseLite.new()
## The retained square shape and query parameters for blocked-cell tests.
var _collision := Collision.new()
## Cells known to be blocked (true) or open (false), so each is queried once.
var _blocked: Dictionary = {}
## Floor-texture flow multiplier per cell, looked up once each.
var _resist: Dictionary = {}
## Soak progress 0..1 of each claimed cell lying on a porous surface (carpet, a rug): 0 = fresh, 1 =
## sunk in.
var _soak: Dictionary = {}
## Frontier cells and their costs, with the cheapest-first heap and insertion-order tie break.
var _frontier := Frontier.new()
## The box of cells claimed or dragged to so far, starting as the cell blood leaves the body at
## (the pool's origin, cell zero).
var _extent := Rect2i(Vector2i.ZERO, Vector2i.ONE)


func _init(aim: Vector2, exclude: Array) -> void:
	_size = BloodPoolConfig.flow_cell_size
	_aim = aim
	_exclude = exclude
	_noise.seed = randi()
	_noise.frequency = BloodPoolConfig.flow_noise_frequency
	_collision.prepare(_size, exclude)
	_frontier.set_cost(Vector2i.ZERO, 0.0)
	_blocked[Vector2i.ZERO] = false


## The box of cells the pool covers so far, trail included: what its draw spans.
func extent() -> Rect2i:
	return _extent


## True once nothing is left to flow into.
func done() -> bool:
	return _frontier.is_empty()


## Sweep the front outward: `delta` seconds of a `duration`-second spread, easing out like a
## liquid slowing as it thins. Call once all cells are claimed.
func advance(delta: float, duration: float) -> void:
	# Blood creeps slower over porous surface, in proportion to how much of the pool lies on it.
	var slow := 1.0
	if not _soak.is_empty() and not cells.is_empty():
		slow = lerpf(
			1.0,
			maxf(BloodSurfaceConfig.porous_spread_slowdown, 1.0),
			float(_soak.size()) / cells.size(),
		)
	_progress = minf(_progress + delta / (maxf(duration, 0.001) * slow), 1.0)
	var eased := 1.0 - (1.0 - _progress) * (1.0 - _progress)
	front = (_last_cost + BloodPoolConfig.flow_soft_edge) * eased


## True once the front has covered every cell.
func settled() -> bool:
	return _progress >= 1.0


## Fill level (0..1) of a cell: the flood-fill at the current front, or the dragged-out trail if
## more. Soaking into a porous surface changes how the blood looks and how wet it is, never how much
## of the floor it covers.
func fill(c: Vector2i) -> float:
	return maxf(_flood(c), trail.get(c, 0.0))


## How wet (0..1) the blood on cell `c` still is: its fill, less what has soaked into the surface.
func wetness(c: Vector2i) -> float:
	return fill(c) * (1.0 - _soak[c]) if _soak.has(c) else fill(c)


## How far (0..1) the blood on cell `c` has sunk in; 0 off a porous surface.
func soak_level(c: Vector2i) -> float:
	return _soak.get(c, 0.0)


## Whether any claimed cell lies on a porous surface.
func has_porous() -> bool:
	return not _soak.is_empty()


## Whether any blood on a porous surface has yet to finish sinking in.
func soaking() -> bool:
	for c in _soak:
		if _soak[c] < 1.0:
			return true
	return false


## Soak `delta` seconds further into every porous cell the flood has mostly reached.
func tick(delta: float) -> void:
	for c in _soak:
		if _soak[c] < 1.0 and _flood(c) >= 0.5:
			_soak[c] = minf(_soak[c] + delta / maxf(BloodSurfaceConfig.soak_time, 0.001), 1.0)


## The flood-fill level (0..1) of cell `c` at the current front, before anything soaks in.
func _flood(c: Vector2i) -> float:
	if not cells.has(c):
		return 0.0
	var t := clampf((front - cells[c]) / maxf(BloodPoolConfig.flow_soft_edge, 0.001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Whether blood of any kind (flooded or dragged out) lies on cell `c`.
func covers(c: Vector2i) -> bool:
	return cells.has(c) or trail.has(c)


## Drag blood out onto cell `c` and the ring around it: raise them to `level` (the centre) and a
## little less (the ring), never lowering one. The level tapers linearly to nothing at
## `BloodTrailConfig.pool_trail_length` px from the flooded cells, and stops growing at
## `BloodTrailConfig.pool_trail_max` trail cells.
func add_trail(c: Vector2i, level: float) -> void:
	level *= 1.0 - clampf(
		_rim_distance(c) / maxf(BloodTrailConfig.pool_trail_length, 0.001),
		0.0,
		1.0,
	)
	if level <= 0.0:
		return
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var n := c + Vector2i(dx, dy)
			if not trail.has(n) and trail.size() >= BloodTrailConfig.pool_trail_max:
				continue
			var l := level if dx == 0 and dy == 0 else level * 0.75
			trail[n] = maxf(trail.get(n, 0.0), clampf(l, 0.0, 1.0))
			_extent = _extent.merge(Rect2i(n, Vector2i.ONE))


## Distance (px) from cell `c` to the nearest flooded cell (0 inside the pool), searched no farther
## than `BloodTrailConfig.pool_trail_length`; beyond that it returns the limit.
func _rim_distance(c: Vector2i) -> float:
	if cells.has(c):
		return 0.0
	var reach := ceili(BloodTrailConfig.pool_trail_length / _size)
	var best := float(reach)
	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			if cells.has(c + Vector2i(dx, dy)):
				best = minf(best, Vector2(dx, dy).length())
	return best * _size


## Local centre of a cell.
func _cell_center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * _size


## How much of the bleed-out cell budget the claimed cells have used: a cell on porous surface costs
## `BloodSurfaceConfig.porous_cell_weight`, so a pool on carpet covers less ground.
func budget_used() -> float:
	return cells.size() + _soak.size() * (maxf(BloodSurfaceConfig.porous_cell_weight, 1.0) - 1.0)


## Claim up to `count` more cells, cheapest first, stopping once `budget` is used (see
## `budget_used`). `origin_global` is the pool's world position.
func step(
	count: int,
	space: PhysicsDirectSpaceState2D,
	origin_global: Vector2,
	budget := INF,
) -> void:
	for i in count:
		if _frontier.is_empty() or budget_used() >= budget:
			return
		var c := _pop_cheapest()
		var cost: float = _frontier.costs[c]
		_frontier.erase(c)
		cells[c] = cost
		_extent = _extent.merge(Rect2i(c, Vector2i.ONE))
		if BloodSurface.is_porous(origin_global + _cell_center(c)):
			_soak[c] = 0.0
		_last_cost = maxf(_last_cost, cost)
		for d in NEIGHBORS:
			var n: Vector2i = c + d
			if cells.has(n) or _is_blocked(n, space, origin_global):
				continue
			var dir := Vector2(d).normalized()
			var rough := 1.0 + _noise.get_noise_2d(n.x, n.y) * BloodPoolConfig.flow_noise_strength
			var lean := 1.0 - BloodPoolConfig.flow_aim_bias * dir.dot(_aim)
			var next := cost + Vector2(d).length() * maxf(rough, 0.15) * maxf(lean, 0.2) \
					* _surface_resist(n, origin_global)
			if not _frontier.costs.has(n) or next < _frontier.costs[n]:
				_frontier.set_cost(n, next)


## The frontier cell cheapest to reach (the caller removes it); ties keep insertion order.
func _pop_cheapest() -> Vector2i:
	return _frontier.pop()


## Floor-texture flow multiplier for cell `c` (cached per cell; see BloodSurface).
func _surface_resist(c: Vector2i, origin_global: Vector2) -> float:
	if not _resist.has(c):
		_resist[c] = BloodSurface.resistance(origin_global + _cell_center(c))
	return _resist[c]


## Whether a wall or furniture collider overlaps cell `c` (cached per cell).
func _is_blocked(c: Vector2i, space: PhysicsDirectSpaceState2D, origin_global: Vector2) -> bool:
	if _blocked.has(c):
		return _blocked[c]
	var blocked := _collision.blocked(space, origin_global + _cell_center(c))
	_blocked[c] = blocked
	return blocked


## The live frontier. A binary heap orders entries by cost and then the cell's first insertion
## sequence, exactly as the old strict-< scan over the insertion-ordered cost dictionary did. A cost
## decrease pushes another entry with that same sequence; `pop` discards stale and removed entries.
class Frontier extends RefCounted:
	## Live cells and their current accumulated costs.
	var costs: Dictionary = {}
	## Heap entries: [cost, insertion sequence, cell], with possible stale entries.
	var _heap: Array = []
	## Each live cell's first insertion sequence; a cost decrease does not change it.
	var _sequence: Dictionary = {}
	## Sequence to give the next new cell.
	var _next := 0


	## Add a cell or lower its cost, retaining its first insertion sequence.
	func set_cost(c: Vector2i, cost: float) -> void:
		if not costs.has(c):
			_sequence[c] = _next
			_next += 1
		costs[c] = cost
		_heap.append([cost, _sequence[c], c])
		_sift_up(_heap.size() - 1)


	## Remove the cheapest heap entry and return its live cell. The caller erases it from `costs`.
	func pop() -> Vector2i:
		while not _heap.is_empty():
			var top: Array = _heap[0]
			_heap[0] = _heap.back()
			_heap.pop_back()
			if not _heap.is_empty():
				_sift_down(0)
			var c: Vector2i = top[2]
			if costs.has(c) and costs[c] == top[0]:
				return c
		return Vector2i.ZERO


	## Forget a claimed cell; any heap entries still naming it become stale.
	func erase(c: Vector2i) -> void:
		costs.erase(c)
		_sequence.erase(c)


	## Whether no live cells remain.
	func is_empty() -> bool:
		return costs.is_empty()


	## Move the entry at `i` toward the root until its parent precedes it.
	func _sift_up(i: int) -> void:
		while i > 0:
			var parent := floori((i - 1) / 2.0)
			if not _less(_heap[i], _heap[parent]):
				return
			_swap(i, parent)
			i = parent


	## Move the root entry at `i` down until both children follow it.
	func _sift_down(i: int) -> void:
		while i * 2 + 1 < _heap.size():
			var child := i * 2 + 1
			if child + 1 < _heap.size() and _less(_heap[child + 1], _heap[child]):
				child += 1
			if not _less(_heap[child], _heap[i]):
				return
			_swap(i, child)
			i = child


	## Heap order: lower cost, then earlier insertion.
	func _less(a: Array, b: Array) -> bool:
		return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])


	## Exchange two heap entries.
	func _swap(a: int, b: int) -> void:
		var held: Array = _heap[a]
		_heap[a] = _heap[b]
		_heap[b] = held


## One square and one query-parameter object per flow, mutated for each uncached cell instead of
## allocating both on every query. Exclusions and query flags are fixed when the flow is built.
class Collision extends RefCounted:
	## The retained blocked-cell query.
	var params := PhysicsShapeQueryParameters2D.new()
	## The square tested at a cell's centre.
	var _probe := RectangleShape2D.new()


	## Prepare the square and the constant parts of the query.
	func prepare(cell_size: float, exclude: Array) -> void:
		_probe.size = Vector2.ONE * cell_size * 0.8
		params.shape = _probe
		params.collision_mask = PhysicsConfig.wall_mask
		params.exclude = exclude
		params.collide_with_bodies = true


	## Whether a wall or furniture collider overlaps the square at `at`.
	func blocked(space: PhysicsDirectSpaceState2D, at: Vector2) -> bool:
		params.transform = Transform2D(0.0, at)
		return not space.intersect_shape(params, 1).is_empty()
