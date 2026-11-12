extends RefCounted
## Vision domain: the exact polygon of what an eye sees (`docs/player-vision.md` V1). A point is
## seen when it is within the view distance, either inside the near bubble or inside the cone round
## the facing, and the line to it is clear by General's `SightRay`: walls and tall pieces break it,
## low ones are looked over.
##
## The polygon is a fan from the eye over ray ends sorted by angle. The rays are an even fan
## (`VisionConfig.cone_rays` across the cone, `bubble_rays` round the bubble) plus, exactly at
## corners, three rays for each corner of each blocking shape the eye can see (at the corner's own
## angle and `corner_offset` either side), so the fan's chords never cut across the shadow behind a
## corner. The shapes and their corners come from `ViewShapes`.
##
## Every ray is cast leaving out the low pieces in reach (the eye looks over them whatever their
## place), so it meets its first blocker in one cast, and a fixed coverage is read once, not on each
## ray (`ViewShapes`): the polygon is the one the plain rule draws, vertex for vertex.
##
## A ray that ends on a blocker runs on to where it leaves it (at most `far_depth`): the farthest
## exit over the blocking shapes that hold a point 0.1 px along the ray, so a wall or a wardrobe
## that is seen shows its top and is not left as a black hole.
##
## A rebuild is a job in stages: `begin` takes the eye, facing and sight, and `step(units)` runs it
## on until `units` of engine work are spent (one for each ray cast, region shape query and far-face
## probe), cutting only between rays or corners, so the polygon does not depend on how the work is
## cut. The stages in order: the corners (one piece), the even fan, which corners the eye sees, the
## bubble's rays, the cone's rays. The job builds its result in a back buffer and swaps `cone`,
## `bubble`, `eye` and the counts in together when it completes: nothing a reader sees changes
## in between. `rebuild` is `begin` plus `step` to the end.

const Shapes := preload("res://scenes/vision/view_shapes.gd")
const Job := preload("res://scenes/vision/view_cone_job.gd")
const Buffer := preload("res://scenes/vision/view_cone_buffer.gd")
## The region of a rebuild (`_region`): the sides of the polygon round the bubble, the chords the
## cone's arc is cut into, and the margin (px) it is grown by.
const REGION_SIDES := 16
const REGION_ARC := 16
const REGION_MARGIN := 2.0
## A corner closer than this (px, at the corner's own distance) to a fan ray is never called hidden
## by the fan: the engine's hit positions are off a shape by up to about 0.02 px, and a hit that
## far off a face makes the chord between two hits leave the shape the line to a grazing corner
## passes. The corner's own dedupe cell is 0.5 px, so this is half of it.
const FAN_HIDE_MARGIN := 0.25

## The cone: the eye, then one corner per ray from the left edge to the right (empty with no
## facing). A triangle fan from the first point.
var cone := PackedVector2Array()
## The near bubble: one corner per ray round the eye, a closed fan from the eye.
var bubble := PackedVector2Array()
## The eye the polygons were built from.
var eye := Vector2.ZERO
## How many rays the last finished job cast to ask whether a corner is seen (a test's read of the
## cost).
var corner_rays := 0
## How many corners the last finished job read from the shapes about the eye (a test's read of the
## cost).
var corners_read := 0
## The job in flight reads these for every ray or corner, so they are held here, not in the job: the
## world it casts in, the eye, the view distance, the bubble's radius, the cone's width (rad) and
## the per-interval hide reaches of the even fan's rays (`_run_fan`).
var _space: PhysicsDirectSpaceState2D
var _from := Vector2.ZERO
var _reach := 0.0
var _near := 0.0
var _fov := 0.0
var _fan_hide := PackedFloat64Array()
var _shapes := Shapes.new()
## The sight rule (`SightRay`), asked with the coverage the shapes already know and with the low
## pieces in reach left out.
var _ray := SightRay.new()
## The job in flight (inputs and progress) and what it holds and builds (the back buffer).
var _job := Job.new()
var _build := Buffer.new()


func _init() -> void:
	_ray.rated = _shapes.rated()


## Rebuild both polygons for an eye at `from` facing `facing`, casting in `space`, leaving `exclude`
## (rids) out and seeing by `sight` (`Character.sight()`), all at once: `begin` and `step` to the
## end.
func rebuild(
	space: PhysicsDirectSpaceState2D,
	from: Vector2,
	facing: Vector2,
	exclude: Array,
	sight: Dictionary,
) -> void:
	begin(space, from, facing, exclude, sight)
	step(1 << 60)


## Start a rebuild (the arguments of `rebuild`) and drop any job in flight. Nothing a reader sees
## changes until `step` says the job is done. The job casts in `space` (the world's own direct
## state, which stays valid between physics frames) and must be stepped in the physics tick.
func begin(
	space: PhysicsDirectSpaceState2D,
	from: Vector2,
	facing: Vector2,
	exclude: Array,
	sight: Dictionary,
) -> void:
	_space = space
	_from = from
	_reach = float(sight["view_distance"])
	_near = float(sight["awareness_radius"])
	_fov = deg_to_rad(float(sight["fov_degrees"]))
	_job.start(facing, exclude, float(sight["see_over_coverage"]))
	_build.clear()
	_fan_hide = PackedFloat64Array()
	_shapes.see_over = _job.see_over
	_ray.looks_over = _job.see_over
	_shapes.reset()


## Whether a job is in flight (`begin` has run and `step` has not yet said done).
func running() -> bool:
	return _job.stage != Job.Stage.DONE


## The engine work (units) the job in flight, or the last one, has spent.
func work_units() -> int:
	return _job.work


## Run the job on until `units` of engine work are spent (a ray, a corner or the corners' query is
## never cut, so a step may spend a little over, and always does at least one piece of work), and
## swap the result in when the last stage is done. True when the job is done (or none is in flight).
func step(units: int) -> bool:
	if _job.stage == Job.Stage.DONE:
		return true
	var until := _job.work + maxi(units, 1)
	while _job.stage != Job.Stage.DONE and _job.work < until:
		match _job.stage:
			Job.Stage.CORNERS:
				_read_corners()
			Job.Stage.FAN:
				_run_fan(until)
			Job.Stage.VISIBLE:
				_run_visible(until)
			Job.Stage.BUBBLE:
				_run_bubble(until)
			Job.Stage.CONE:
				_run_cone(until)
	return _job.stage == Job.Stage.DONE


## Stage 1: the shapes about the eye, in one piece (a shape query, asked again while it is full).
func _read_corners() -> void:
	var asked := _shapes.queries
	_build.found = _shapes.corners(_space, _from, _reach, _job.exclude, _region(_from, _job.facing))
	_job.work += (_shapes.queries - asked) * VisionSliceConfig.cost_shape
	_build.corners_read = _build.found.size()
	# Every low collider in reach is left out of the rays from here on: each meets the first blocker
	# in one cast, where it would otherwise cast again past each low piece on its way.
	_ray.leave_out(_job.exclude + _shapes.lows())
	_job.index = 0
	_job.stage = Job.Stage.FAN if _job.facing != Vector2.ZERO else Job.Stage.VISIBLE


## Stage 2: the even fan's rays, each with its end and the hide reach of the interval from the one
## before, until the work reaches `until` or the fan is done.
func _run_fan(until: int) -> void:
	var work := _job.work
	var index := _job.index
	var last := VisionConfig.cone_rays
	var previous := _build.previous
	var previous_distance := _build.previous_distance
	while index <= last and work < until:
		var dir := _job.facing.rotated(_fan_angle(index))
		var to := _from + dir * _reach
		work += VisionSliceConfig.cost_cast
		var hit := _ray.cast(_space, _from, to)
		var distance := 0.0
		if hit.is_empty():
			_build.fan_ends.append(to)
		else:
			distance = _from.distance_to(hit["position"])
			work += VisionSliceConfig.cost_probe
			_build.fan_ends.append(_far_face(hit, dir))
		if index > 0:
			_fan_hide.append(_hide_reach(previous, previous_distance, hit, distance))
		previous = hit
		previous_distance = distance
		index += 1
	_job.work = work
	_job.index = index
	_build.previous = previous
	_build.previous_distance = previous_distance
	if index > last:
		_build.previous = {}
		_job.index = 0
		_job.stage = Job.Stage.VISIBLE


## Stage 3: each corner, kept when the eye sees it: within the view range, inside the cone or the
## bubble, and with no blocker in the way (a corner behind a wall needs no rays: the wall's own ray
## decides there; one the fan hides needs none either). After the last, the bubble's rays are made.
func _run_visible(until: int) -> void:
	var found := _build.found
	var index := _job.index
	var facing := _job.facing
	var work := _job.work
	var cast_cost := VisionSliceConfig.cost_cast
	while index < found.size() and work < until:
		var corner: Vector2 = found[index]
		index += 1
		var to := corner - _from
		var dist := to.length()
		if dist < 1.0 or dist > _reach:  # a corner beyond the view distance adds no ray
			continue
		var in_cone := facing != Vector2.ZERO and absf(facing.angle_to(to)) <= _fov * 0.5
		if not (in_cone or dist <= _near):
			continue
		# A point 1 px short of the corner: the corner's own shape is not in the way of itself.
		if in_cone and _fan_hides(facing.angle_to(to), dist - 1.0):
			continue
		_build.corner_rays += 1
		work += cast_cost
		if _ray.cast(_space, _from, _from + to * ((dist - 1.0) / dist)).is_empty():
			_build.visible.append(corner)
	_job.work = work
	_job.index = index
	if index >= found.size():
		_build.rays = _bubble_angles(_from, _build.visible)
		_job.index = 0
		_job.stage = Job.Stage.BUBBLE


## Stage 4: the bubble's rays (each `[angle, direction, -1]`). After the last, the cone's rays are
## made (none with no facing: the job is done).
func _run_bubble(until: int) -> void:
	var rays := _build.rays
	var out := _build.bubble
	_build.bubble = PackedVector2Array()
	var work := _job.work
	var index := _job.index
	var cast_cost := VisionSliceConfig.cost_cast
	while index < rays.size() and work < until:
		var dir: Vector2 = rays[index][1]
		var to := _from + dir * _near
		work += cast_cost
		var hit := _ray.cast(_space, _from, to)
		if hit.is_empty():
			out.append(to)
		else:
			work += VisionSliceConfig.cost_probe
			out.append(_far_face(hit, dir))
		index += 1
	_job.work = work
	_job.index = index
	_build.bubble = out
	if index < rays.size():
		return
	_job.index = 0
	if _job.facing == Vector2.ZERO:
		_finish()
		return
	_build.rays = _cone_angles(_from, _job.facing, _build.visible)
	_build.cone = PackedVector2Array([_from])
	_job.stage = Job.Stage.CONE


## Stage 5: the cone's rays (each `[angle, direction, fan index]`): one with a fan index takes its
## end from the fan's casts, uncast. After the last, done.
func _run_cone(until: int) -> void:
	var rays := _build.rays
	var out := _build.cone
	_build.cone = PackedVector2Array()
	var work := _job.work
	var index := _job.index
	var cast_cost := VisionSliceConfig.cost_cast
	while index < rays.size() and work < until:
		var fan_index: int = rays[index][2]
		if fan_index >= 0 and fan_index < _build.fan_ends.size():
			out.append(_build.fan_ends[fan_index])
		else:
			var dir: Vector2 = rays[index][1]
			var to := _from + dir * _reach
			work += cast_cost
			var hit := _ray.cast(_space, _from, to)
			if hit.is_empty():
				out.append(to)
			else:
				work += VisionSliceConfig.cost_probe
				out.append(_far_face(hit, dir))
		index += 1
	_job.work = work
	_job.index = index
	_build.cone = out
	if index >= rays.size():
		_finish()


## The job is done: the back buffer becomes what readers see, all together.
func _finish() -> void:
	eye = _from
	corner_rays = _build.corner_rays
	corners_read = _build.corners_read
	bubble = _build.bubble
	cone = _build.cone
	_build.bubble = PackedVector2Array()
	_build.cone = PackedVector2Array()
	_job.stage = Job.Stage.DONE


## The hull of everything a ray of this rebuild passes through, grown by `REGION_MARGIN`: the
## sector of the cone (its arc cut into chords that lie outside it) and the bubble round the eye.
## A shape that does not touch it is in no ray, and has no corner within half a pixel of one that
## is (`ViewShapes.corners` joins those), so it need not be read.
func _region(from: Vector2, facing: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	var round_bubble := _near / cos(PI / float(REGION_SIDES))
	for i in REGION_SIDES:
		points.append(from + Vector2.from_angle(float(i) / REGION_SIDES * TAU) * round_bubble)
	if facing != Vector2.ZERO:
		var half := _fov * 0.5
		var round_arc := _reach / cos(_fov / float(REGION_ARC) * 0.5)
		for i in REGION_ARC + 1:
			var angle := -half + float(i) / float(REGION_ARC) * _fov
			points.append(from + facing.rotated(angle) * round_arc)
	var grown := Geometry2D.offset_polygon(Geometry2D.convex_hull(points), REGION_MARGIN)
	return PackedVector2Array() if grown.is_empty() else grown[0]


## Whether `point` is inside the cone or the bubble polygon.
func contains(point: Vector2) -> bool:
	return SeenArea.contains(cone, point) or SeenArea.contains(bubble, point)


## How far the fan's interval between the rays that hit `a` and `b` (`a_distance`, `b_distance` from
## the eye) hides a corner: the farther of the two hits when they are on one convex shape, else -1.
## A convex shape holds the chord between its two hits, so a line between the two rays that is
## shorter than both hits crosses the chord and meets the shape.
func _hide_reach(a: Dictionary, a_distance: float, b: Dictionary, b_distance: float) -> float:
	if a.is_empty() or b.is_empty():
		return -1.0
	if a["collider_id"] != b["collider_id"] or a["shape"] != b["shape"]:
		return -1.0
	if _shapes.polygon_of(a["collider"], a["shape"]).is_empty():
		return -1.0
	return maxf(a_distance, b_distance)


## The angle from the facing of ray `i` of the even fan across the cone, `i` from 0 (the left edge)
## to `VisionConfig.cone_rays` (the right).
func _fan_angle(i: int) -> float:
	return -_fov * 0.5 + float(i) / float(VisionConfig.cone_rays) * _fov


## Whether the line from the eye to the point `reach` px along `angle` (from the facing, inside the
## cone) is blocked before it is, by what the fan found: the two rays either side of it met the
## same convex shape, both nearer than `reach` (`_hide_reach`). Not when the line is within
## `FAN_HIDE_MARGIN` px, at the corner's distance, of either ray: the engine's hit positions are not
## exact enough to say a grazing line crosses the chord.
func _fan_hides(angle: float, reach: float) -> bool:
	var rays := VisionConfig.cone_rays
	var i := clampi(int((angle + _fov * 0.5) / _fov * float(rays)), 0, rays - 1)
	var low := _fan_angle(i)
	var high := _fan_angle(i + 1)
	if angle <= low or angle >= high:
		return false
	var limit: float = _fan_hide[i]
	if limit < 0.0 or limit >= reach:
		return false
	var margin := FAN_HIDE_MARGIN / (reach + 1.0)
	return angle - low > margin and high - angle > margin


## The cone's rays as `[angle from the facing, direction, fan index]`, sorted by angle: the even
## fan, which holds the two edge rays (its index `i` is the ray's place in the buffer's `fan_ends`),
## and three rays at each visible corner inside the cone (index -1: cast on their own; one clamped
## onto an edge of the cone takes that edge ray's index).
func _cone_angles(from: Vector2, facing: Vector2, corners: Array) -> Array:
	var half := _fov * 0.5
	var offset := VisionConfig.corner_offset
	var rays: Array = []
	for i in VisionConfig.cone_rays + 1:
		rays.append([_fan_angle(i), i])
	for corner in corners:
		var angle := facing.angle_to(corner - from)
		if absf(angle) > half:
			continue
		for shift in [-offset, 0.0, offset]:
			var shifted := clampf(angle + shift, -half, half)
			# A ray clamped onto an edge of the cone is the fan's edge ray: its end is known.
			var edge := 0 if shifted <= -half else VisionConfig.cone_rays if shifted >= half else -1
			rays.append([shifted, edge])
	rays.sort_custom(_angle_before)
	var out: Array = []
	for ray: Array in rays:
		out.append([ray[0], facing.rotated(ray[0]), ray[1]])
	return out


## Whether ray `a` precedes ray `b` by its angle.
static func _angle_before(a: Array, b: Array) -> bool:
	return a[0] < b[0]


## The bubble's rays as `[angle, direction, -1]`, sorted: the even fan and three rays at each
## visible corner inside the bubble.
func _bubble_angles(from: Vector2, corners: Array) -> Array:
	var rays := VisionConfig.bubble_rays
	var offset := VisionConfig.corner_offset
	var angles: Array = []
	for i in rays:
		angles.append(float(i) / float(rays) * TAU)
	for corner in corners:
		var to: Vector2 = corner - from
		if to.length() > _near:
			continue
		for shift in [-offset, 0.0, offset]:
			angles.append(fposmod(to.angle() + shift, TAU))
	angles.sort()
	var out: Array = []
	for angle: float in angles:
		out.append([angle, Vector2.from_angle(angle), -1])
	return out


## The far end of the blocker `hit` along `dir`: where the ray leaves the solid it met (the
## farthest face of the blocking shapes it runs into at the hit, so the engine's pick among
## overlapping shapes does not matter), at most `far_depth` in, else `far_bleed` px in.
func _far_face(hit: Dictionary, dir: Vector2) -> Vector2:
	var near: Vector2 = hit["position"]
	var depth := _shapes.far_exit(_space, hit, dir)
	if depth < 0.0:
		return near + dir * VisionConfig.far_bleed
	return near + dir * minf(depth, VisionConfig.far_depth)
