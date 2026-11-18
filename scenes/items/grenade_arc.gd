class_name GrenadeArc
extends RefCounted
## Items domain, the one planner of a grenade's throw, for the player's throw and the AI's
## (interface 6): from the thrower's release height to the aim point, the LOWEST arc that clears
## what is in the way in the twin 3D space (furniture tops, a doorway's lintel, a wall) and lands
## near the aim, as the launch velocity to throw it with (`GrenadeLaunch`). Then `ThrownGrenade`
## flies it as real 3D flight (`ItemFlight`, the same stepper the planner rests an arc with).
##
## **The arcs.** An arc peaks at an `apex` (the centre's height, px): from the release height itself
## (a flat throw) up by `APEX_STEP` to the top (`_top`: `GrenadeConfig.max_apex` in the open, under
## a roof the roof), lowest first.
## Under the arc's gravity its flight time follows from the apex alone, so the throw's reach is what
## the arm's `throw_speed` gives over that time: the lowest apex that reaches the aim is a flat toss
## for a near aim and a high lob for a far one. Where it first touches down is solved so that, with
## the bounces and the skid on a flat floor, it rests at the aim (the analytic `_extra`, no
## queries). Each arc is swept through the twin space, in `SEGMENTS` casts of a cylinder `margin`
## wider than the grenade, and kept when nothing stops it: a strike on the way down within
## `LAND_NEAR` of the aim is a landing (on a table, a sofa), any other is a strike.
##
## **Verifying.** A throw that is made (`GrenadeCourse.verify`) also flies each clear arc over the
## floor, the thrower's own flight to rest (`rest_of`), and keeps the first that rests within
## `FIT_NEAR` of the aim (a rest short of it counted `SHORT_COST` times): a grenade that would touch
## down short of a sofa and skid into it is lobbed farther, over it (`FIT_STEP` further out each, as
## many as `FIT_TRIES` flights in all). One that nothing rests near is thrown on the arc that rests
## nearest; one with no clear arc at all on the highest, and `ok` says it will strike.

## How much higher (px) each arc peaks than the one before.
const APEX_STEP := 6.0
## Above the walls' height (`HIGH_FROM`, where only the open sky leaves room for an arc) the steps
## are this much (px): the search's sweeps are spent over the low arcs and their longer lobs first.
const HIGH_FROM := 96.0
const HIGH_STEP := 18.0
## Casts one arc is swept in, and the steps of the solve of where it first touches down.
const SEGMENTS := 5
const SOLVE_STEPS := 18
## What `_lands` takes for a surface: the structure, the furniture and the vehicles; a body struck
## near the aim (the hostile's own) is a landing on it.
const SURFACES := PhysicsLayers.TWIN_WORLD | PhysicsLayers.TWIN_VEHICLE
## How far (px) past the cylinder's width a ray from where an arc stops feels for the surface it
## struck (`_lands`).
const FEEL := 4.0
## A strike on the way down this near (px) the aim is a landing on top of something.
const LAND_NEAR := 24.0
## A flown arc that rests within this many px of the aim is kept; one that does not is lobbed
## farther, `FIT_STEP` px at a time, up to `FIT_TRIES` flights in all.
const FIT_NEAR := 24.0
const FIT_STEP := 12.0
## The AI's question lobs farther in steps this many times as long (`_lob_step`): it only asks
## whether some touchdown clears, so it samples them coarser.
const ASKED_STEP := 2.0
## How far (px) past the aim an arc may first touch down when it is lobbed farther: it rolls on from
## there, but not back.
const LOB_BEYOND := 40.0
const FIT_TRIES := 30
## A rest short of the aim counts this many times its distance when arcs are compared: a grenade
## that comes down short is the one the cover stopped, and one that rolls on past is the lesser
## miss.
const SHORT_COST := 2.0
## The casts that find a wall across the line (`_walled`): how high (px) the low one flies (the high
## one flies at the highest arc's apex), and how near (px) their two stops must be to be one wall.
const WALL_LOW := 40.0
const WALL_SLACK := 2.0
## The share of its reach out to which a strike is early: a jamb, a lintel or a wall near the hand,
## which a longer lob of the same arc meets just the same (`Fit.early`).
const EARLY_SHARE := 0.5
## How near (px) the strikes of the lowest and the highest arc are to be one face (`_faced`).
const FACE_SLACK := 3.0
## And how high (px) both strikes are, for it to be a wall and not a low piece's edge, which arcs
## that descend steeply strike at the same place (`_faced`).
const FACE_HEIGHT := 45.0
## How much a hand's overlap must face the way it is thrown to be a throw into the body (cosine).
const START_INTO := 0.05
## How far (px) past where a grenade is reckoned to rest the floor is checked for what it would run
## into (`_skid_clear`).
const SKID_SLACK := 12.0
## What a lob keeps clear of a roof above its peak (px) besides the grenade's own radius; the height
## a ray up from a point starts at, and how far it looks for a roof.
const ROOF_SLACK := 3.0
const ROOF_PROBE := 60.0
const ROOF_RANGE := 400.0
## How many arcs one plan sweeps at most (each a few casts): the AI's question is cheap, and a throw
## no swept arc clears is judged blocked.
const SWEEPS := 64
## How far (px) a grenade flies before its thrower's own body can stop it: it leaves the hand beside
## the body, and its first few px pass within a body's width of it.
const THROWER_CLEAR := 40.0
## The physics step the planner flies at (the game's), and the longest it flies (frames).
const PLAN_DELTA := 1.0 / 60.0
const PLAN_FRAMES := 600
## No bodies passed.
const NOBODY: Array[RID] = []

## The sweeps made so far, by width: a shape is made once, not for every question.
static var _sweeps := {}


## The throw to make along `course`: the lowest arc that clears and lands at its aim. The launch's
## `ok` says whether one clears; when none does it is the highest arc (the best a thrower can do),
## which strikes what is in the way. A `course.apex` of 0 or more allows only that arc.
static func plan(course: GrenadeCourse) -> GrenadeLaunch:
	var sweep := _sweep(course)
	if _walled(course, sweep):
		return _blocked(course, _top_arc(course))
	var flat := _flattest(course, sweep)
	if flat != null:
		return flat
	var arcs := _arcs(course)
	if _faced(course, sweep, arcs):
		return _blocked(course, arcs[arcs.size() - 1])
	var fit := Fit.new()
	while fit.step == 0 or (not fit.spent() and fit.step <= _longest(course, arcs)):
		for arc: Arc in arcs:
			var launch := _try(course, sweep, fit, arc)
			if launch != null:
				return launch
		fit.step += 1
	if not fit.best.is_empty():
		return _launch(course, fit.best["arc"], fit.best["reach"], true, fit.best["rest"])
	return _blocked(course, arcs[arcs.size() - 1])


## The throw along the flattest arc when it clears, for a question that does not fly it (the usual
## answer, before the other arcs are worked out); null when it does not, or the course asks more.
static func _flattest(course: GrenadeCourse, sweep: PhysicsShapeQueryParameters3D) -> GrenadeLaunch:
	if course.verify or course.apex >= 0.0:
		return null
	var flat := _arc(course, course.release)
	if flat.capped or not _clear(course, sweep, flat, _reach(course, flat)):
		return null
	return _launch(course, flat, _reach(course, flat), true, course.to)


## One arc of the search `fit` keeps, thrown `fit.step` steps long: its launch when it clears and is
## the answer, else null.
static func _try(
	course: GrenadeCourse,
	sweep: PhysicsShapeQueryParameters3D,
	fit: Fit,
	arc: Arc,
) -> GrenadeLaunch:
	var reach := _reach(course, arc) + fit.step * _lob_step(course)
	if fit.step > 0 and (arc.capped or reach > arc.farthest):
		return null
	if fit.spent() or fit.early.has(arc.apex):
		return null
	fit.swept += 1
	var struck: Variant = _strike(course, sweep, arc, reach)
	if struck != null:
		if _plan_of(struck).distance_to(course.from) < reach * EARLY_SHARE:
			fit.early[arc.apex] = true
		return null
	if not course.verify:
		return _launch(course, arc, reach, true, course.to)
	fit.tries += 1
	var rest := _rest(course, arc, reach)
	fit.offer(arc, reach, rest, _miss(course, rest))
	if rest.distance_to(course.to) <= FIT_NEAR:
		return _launch(course, arc, reach, true, rest)
	if fit.tries >= FIT_TRIES:
		return _launch(course, fit.best["arc"], fit.best["reach"], true, fit.best["rest"])
	return null


## The launch of `arc` when nothing clears: the highest arc, which strikes what is in the way.
static func _blocked(course: GrenadeCourse, arc: Arc) -> GrenadeLaunch:
	return _launch(course, arc, _reach(course, arc), false, course.to)


## The highest the centre of a lob on `course` may peak (px): `GrenadeConfig.max_apex` in the open,
## and under a roof (over the hand, the middle or the aim: the arc must go under it) the roof's
## underside less the grenade's size and `ROOF_SLACK`; never under the release height. The roof is
## the lowest over the hand, the middle of the throw and the aim. Worked out once.
static func _top(course: GrenadeCourse) -> float:
	if course.top < 0.0:
		if course.space != null:
			course.roof = minf(
				_roof_over(course, course.from),
				minf(
					_roof_over(course, course.from.lerp(course.to, 0.5)),
					_roof_over(course, course.to),
				),
			)
		var top := minf(GrenadeConfig.max_apex, course.roof - GrenadeConfig.radius - ROOF_SLACK)
		course.top = maxf(top, course.release)
	return course.top


## How high (px) the roof over plan point `at` is, `INF` in the open: a ray up from `ROOF_PROBE` on
## the roof's layer (a doorway's lintel is no roof).
static func _roof_over(course: GrenadeCourse, at: Vector2) -> float:
	var query := PhysicsRayQueryParameters3D.create(
		PlanSpace.lift(at, ROOF_PROBE),
		PlanSpace.lift(at, ROOF_RANGE),
		PhysicsLayers.TWIN_ROOF,
	)
	var hit := course.space.intersect_ray(query)
	return PlanSpace.height_of(hit["position"]) if not hit.is_empty() else INF


## The highest arc a course allows: its chosen one, else the one peaking at `max_apex`.
static func _top_arc(course: GrenadeCourse) -> Arc:
	return _arc(
		course,
		course.apex if course.apex >= 0.0 else _top(course),
	)


## How far (px) a grenade resting at `rest` is from the aim, short ones weighted by `SHORT_COST`.
static func _miss(course: GrenadeCourse, rest: Vector2) -> float:
	var off := rest.distance_to(course.to)
	return off * SHORT_COST if (rest - course.to).dot(course.to - course.from) < 0.0 else off


## Whether some arc clears everything from the hand to its landing at `course.to`: the question the
## AI asks of a throw it may make. The same arcs, sweeps and rules as `plan` (verifying nothing:
## it does not fly the skid).
static func clear(course: GrenadeCourse) -> bool:
	course.verify = false
	return plan(course).ok


## A flight that flies a grenade of `row` as `ThrownGrenade` does: its size, gravity,
## bounce, skid and what it strikes.
static func flight_for(
	row: Dictionary,
	mask: int = PhysicsLayers.TWIN_ALL | PhysicsLayers.TWIN_ROOF,
	ceiling := INF,
) -> ItemFlight:
	var flight := ItemFlight.new(GrenadeConfig.radius)
	flight.gravity = GrenadeConfig.gravity
	flight.min_hop = GrenadeConfig.min_hop_speed
	flight.floor_restitution = float(row.get("restitution", 0.35))
	flight.wall_restitution = flight.floor_restitution
	flight.friction = float(row.get("friction", 520.0))
	flight.mask = mask
	flight.ceiling = ceiling
	return flight


## The bodies a throw by `thrower` passes just after the release: its own twin (none for a thrower
## with none, or outside a world with a twin space).
static func passed_by(thrower: Node) -> Array[RID]:
	if thrower == null or not thrower.has_method(&"world_root"):
		return NOBODY
	var world: Node = thrower.world_root()
	var twins := world.get_node_or_null(^"Twins") as TwinSpace if world != null else null
	var twin := twins.twin_of(thrower) as CollisionObject3D if twins != null else null
	if twin == null:
		return NOBODY
	var out: Array[RID] = [twin.get_rid()]
	return out


## Where the grenade thrown as `launch` says comes to rest, flown over the floor in the course's
## space (the node's own flight: `ItemFlight`, stepped at the game's rate).
static func rest_of(course: GrenadeCourse, launch: GrenadeLaunch) -> Vector2:
	var flight := flight_for(course.row, course.mask, course.roof)
	flight.place(course.from, course.release)
	flight.velocity = launch.direction * launch.speed
	flight.rise = launch.rise
	var flown := 0.0
	for _frame in PLAN_FRAMES:
		var before := flight.at
		flight.step(course.space, PLAN_DELTA, course.passed if flown < THROWER_CLEAR else NOBODY)
		flown += before.distance_to(flight.at)
		if flight.resting:
			break
	return flight.at


## The arcs to try, lowest first, as `{ apex, rise, time, vdown, reach, cap, farthest, capped }`:
## for a chosen apex only that one; else one per apex step that reaches the aim, and when none does
## the highest, capped (it first touches down as far as the arm reaches and rolls on).
static func _arcs(course: GrenadeCourse) -> Array[Arc]:
	var out: Array[Arc] = []
	if course.apex >= 0.0:
		out.append(_arc(course, course.apex))
		return out
	var apex := course.release
	var top := _top(course)
	while true:
		var arc := _arc(course, minf(apex, top))
		if not arc.capped or apex >= top:
			out.append(arc)
		if apex >= top:
			break
		apex += APEX_STEP if apex < HIGH_FROM else HIGH_STEP
	return out


## The arc peaking at `apex` (at least the release height): its launch rise, flight time and fall
## speed under gravity, how far the arm throws it (`cap`) and where it first touches down so that it
## comes to rest at the aim (`reach`; `capped` when it cannot get there).
static func _arc(course: GrenadeCourse, apex: float) -> Arc:
	var g := GrenadeConfig.gravity
	var floor_y := GrenadeConfig.radius + ItemFlight.GROUND_GAP
	var top := maxf(apex, maxf(course.release, floor_y + 1.0))
	var rise := sqrt(2.0 * g * (top - course.release))
	var fall := sqrt(2.0 * (top - floor_y) / g)
	var time := rise / g + fall
	var cap := minf(
		float(course.row.get("throw_speed", 740.0)) * time,
		float(course.row.get("max_range", 550.0)),
	)
	var aim := course.from.distance_to(course.to)
	var arc := Arc.new()
	arc.apex = top
	arc.rise = rise
	arc.time = time
	arc.vdown = g * fall
	arc.cap = cap
	arc.reach = cap
	arc.capped = true
	arc.farthest = minf(cap, aim + LOB_BEYOND)
	if _comes_to_rest(course.row, arc, cap) >= aim:
		arc.capped = false
		arc.reach = -1.0
	return arc


## Where `arc` first touches down so that it comes to rest at the aim: solved the first time it is
## asked for (a blocked lob never needs it).
static func _reach(course: GrenadeCourse, arc: Arc) -> float:
	if arc.reach < 0.0:
		arc.reach = _solve(course.row, arc, course.from.distance_to(course.to))
	return arc.reach


## Where an arc first touches down so that it comes to rest `aim` px from the hand (bisected).
static func _solve(row: Dictionary, arc: Arc, aim: float) -> float:
	var low := 0.0
	var high := minf(arc.cap, aim)
	for _i in SOLVE_STEPS:
		var mid := (low + high) * 0.5
		if _comes_to_rest(row, arc, mid) < aim:
			low = mid
		else:
			high = mid
	return high


## How far (px) from the hand an arc of `arc` that first touches down `reach` out comes to rest,
## over a flat floor: through the bounces and the skid, with no queries.
static func _comes_to_rest(row: Dictionary, arc: Arc, reach: float) -> float:
	var g := GrenadeConfig.gravity
	var keep := float(row.get("restitution", 0.35))
	var along := reach / arc.time
	var down: float = arc.vdown
	var far := reach
	for _bounce in 8:
		if down > GrenadeConfig.min_hop_speed and down * keep > g * PLAN_DELTA:
			along *= keep
			down *= keep
			far += along * 2.0 * down / g
		else:
			break
	return far + along * along / (2.0 * float(row.get("friction", 520.0)))


## How far (px) each step of lobbing farther goes: `FIT_STEP` for a throw that is made, `ASKED_STEP`
## times that for the AI's question, which only asks whether some touchdown clears.
static func _lob_step(course: GrenadeCourse) -> float:
	return FIT_STEP if course.verify else FIT_STEP * ASKED_STEP


## How many steps (`_lob_step`) the farthest arc can be lobbed beyond where it was solved to touch
## down.
static func _longest(course: GrenadeCourse, arcs: Array[Arc]) -> int:
	var most := 0
	for arc: Arc in arcs:
		if not arc.capped:
			most = maxi(most, int((arc.farthest - _reach(course, arc)) / _lob_step(course)))
	return most


## Whether a body as tall as the walls stands across the line from the hand to the aim, away from
## the aim: the grenade's cylinder cast level at the highest arc's height and at `WALL_LOW` stops at
## the same place (a wall, or a doorway's jamb and its lintel), and no arc gets over a body that
## spans every height between. The cheap answer for the common blocked lob, which would otherwise
## sweep arcs.
static func _walled(course: GrenadeCourse, query: PhysicsShapeQueryParameters3D) -> bool:
	if course.space == null:
		return false
	query.exclude = course.passed
	var high := _level_cast(course, query, _top(course))
	if high == Vector2.INF or high.distance_to(course.to) <= LAND_NEAR + WALL_SLACK:
		return false
	var low := _level_cast(course, query, WALL_LOW)
	return low != Vector2.INF and low.distance_to(high) <= WALL_SLACK


## Where the cylinder `query`, held `height` px up and cast level from the hand toward the aim, is
## first stopped (a plan point), or `Vector2.INF` when nothing stops it before the aim.
static func _level_cast(
	course: GrenadeCourse,
	query: PhysicsShapeQueryParameters3D,
	height: float,
) -> Vector2:
	var start := PlanSpace.lift(course.from, height)
	query.transform = Transform3D(Basis(), start)
	query.motion = PlanSpace.lift(course.to, height) - start
	var res := course.space.cast_motion(query)
	if res.is_empty() or res[0] >= 1.0:
		return Vector2.INF
	return PlanSpace.plan_of(start + query.motion * float(res[0]))


## The cast a sweep of the arc uses: a cylinder as wide as the course's margin (a grenade at least).
static func _sweep(course: GrenadeCourse) -> PhysicsShapeQueryParameters3D:
	var width := maxf(GrenadeConfig.radius, course.margin)
	var query: PhysicsShapeQueryParameters3D = _sweeps.get(width)
	if query == null:
		var shape := CylinderShape3D.new()
		shape.radius = width * RenderConfig.unit
		shape.height = GrenadeConfig.radius * 2.0 * RenderConfig.unit
		query = PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		_sweeps[width] = query
	query.collision_mask = course.mask | PhysicsLayers.TWIN_ROOF
	return query


## Whether `arc`, first touching down `reach` px out, flies clear (`_strike` finds nothing).
static func _clear(
	course: GrenadeCourse,
	query: PhysicsShapeQueryParameters3D,
	arc: Arc,
	reach: float,
) -> bool:
	return _strike(course, query, arc, reach) == null


## Where `arc`, first touching down `reach` px out, strikes something (`Vector3(x, y, height)`: the
## plan point and the centre's height), or null when it flies clear: swept in `SEGMENTS` casts
## through the course's space from the hand to the floor. A strike on the way down within
## `LAND_NEAR` of the aim is a landing on top of what is there, not a strike.
static func _strike(
	course: GrenadeCourse,
	query: PhysicsShapeQueryParameters3D,
	arc: Arc,
	reach: float,
) -> Variant:
	if course.space == null:
		return null
	var time: float = arc.time
	var along := reach / time
	var direction := _direction(course)
	var before := _point(course, direction, along, arc, 0.0)
	var first := _point(course, direction, along, arc, time / SEGMENTS)
	if _starts_into(course, query, before, first - before):
		return _spot(before)
	for i in SEGMENTS:
		var at := time * float(i + 1) / SEGMENTS
		var after := _point(course, direction, along, arc, at)
		var started := time * float(i) / SEGMENTS
		query.exclude = course.passed if along * started < THROWER_CLEAR else NOBODY
		query.transform = Transform3D(Basis(), before)
		query.motion = after - before
		var res := course.space.cast_motion(query)
		if not res.is_empty() and res[0] < 1.0:
			var stopped := before + (after - before) * float(res[1])
			if _lands(course, before, after, stopped):
				return null
			return _spot(stopped)
		before = after
	return null


## Whether a strike at `stopped`, on the way from `before` to `after`, is a landing: on the way
## down, within `LAND_NEAR` of the aim, on a surface that faces up (a floor, a piece's top), or over
## the edge of a piece (a level feeler the cylinder's width higher meets nothing). The face of a
## wall rising beside the aim is a strike, not a landing.
static func _lands(
	course: GrenadeCourse,
	before: Vector3,
	after: Vector3,
	stopped: Vector3,
) -> bool:
	if after.y >= before.y or PlanSpace.plan_of(stopped).distance_to(course.to) > LAND_NEAR:
		return false
	var reach := maxf(course.margin, GrenadeConfig.radius)
	var onward := (after - before).normalized()
	var feel := PhysicsRayQueryParameters3D.create(
		stopped, stopped + onward * (reach + FEEL), course.mask & SURFACES
	)
	feel.exclude = course.passed
	var hit := course.space.intersect_ray(feel)
	if hit.is_empty() or Vector3(hit["normal"]).y > ItemFlight.FACES_UP:
		return true
	var level := Vector3(onward.x, 0.0, onward.z).normalized()
	var up := Vector3(0.0, reach + 1.0, 0.0)
	var higher := PhysicsRayQueryParameters3D.create(
		stopped + up, stopped + up + level * (reach + FEEL), course.mask & SURFACES
	)
	higher.exclude = course.passed
	return course.space.intersect_ray(higher).is_empty()


## The plan point of a `_strike` answer.
static func _plan_of(strike: Vector3) -> Vector2:
	return Vector2(strike.x, strike.y)


## The plan point and height of 3D point `point`, as `_strike` answers.
static func _spot(point: Vector3) -> Vector3:
	var across := PlanSpace.plan_of(point)
	return Vector3(across.x, across.y, PlanSpace.height_of(point))


## Whether the cylinder `query` at `start` (the hand) already overlaps a body that `motion`, its
## first stretch, drives it into: a cast that starts inside a body finds nothing to strike, so a
## hand held against a wall and thrown at it would pass for clear (one that overlaps a body only to
## throw away from it is free).
static func _starts_into(
	course: GrenadeCourse,
	query: PhysicsShapeQueryParameters3D,
	start: Vector3,
	motion: Vector3,
) -> bool:
	query.exclude = course.passed
	query.transform = Transform3D(Basis(), start)
	query.motion = Vector3.ZERO
	var info := course.space.get_rest_info(query)
	if info.is_empty():
		return false
	var normal: Vector3 = info["normal"]
	return normal.dot(motion.normalized()) < -START_INTO


## Whether one face blocks every arc: the lowest arc and the highest strike at the same place (a
## wall, a jamb and its lintel: a body that spans every height between). Costs two sweeps, and saves
## the rest of the arcs' when it does.
static func _faced(
	course: GrenadeCourse,
	query: PhysicsShapeQueryParameters3D,
	arcs: Array[Arc],
) -> bool:
	if arcs.size() < 2:
		return false
	var low: Variant = _strike(course, query, arcs[0], _reach(course, arcs[0]))
	if low == null:
		return false
	var top: Arc = arcs[arcs.size() - 1]
	var high: Variant = _strike(course, query, top, _reach(course, top))
	return (
		high != null
		and minf((low as Vector3).z, (high as Vector3).z) >= FACE_HEIGHT
		and _plan_of(low).distance_to(_plan_of(high)) <= FACE_SLACK
	)


## The 3D point of the arc `time` s after the release.
static func _point(
	course: GrenadeCourse,
	direction: Vector2,
	along: float,
	arc: Arc,
	time: float,
) -> Vector3:
	var height: float = (
		course.release + arc.rise * time - 0.5 * GrenadeConfig.gravity * time * time
	)
	if time >= arc.time:
		height = GrenadeConfig.radius + ItemFlight.GROUND_GAP
	return PlanSpace.lift(course.from + direction * along * time, height)


## The way across the floor, from the hand to the aim (right for an aim at the hand).
static func _direction(course: GrenadeCourse) -> Vector2:
	var to := course.to - course.from
	return to.normalized() if to.length() > 0.5 else Vector2.RIGHT


## Where `arc` first touching down `reach` out rests, flown over the floor (`rest_of`).
static func _rest(course: GrenadeCourse, arc: Arc, reach: float) -> Vector2:
	var far := _comes_to_rest(course.row, arc, reach)
	var direction := _direction(course)
	if _skid_clear(course, reach, far):
		return course.from + direction * far
	return rest_of(course, _launch(course, arc, reach, true, course.to))


## Whether nothing stands on the floor between where an arc first touches down (`reach` px from the
## hand) and where, over a flat floor, it comes to rest (`far`): a grenade then rests where
## `_comes_to_rest` says and need not be flown (a flight is up to a hundred sweeps).
static func _skid_clear(course: GrenadeCourse, reach: float, far: float) -> bool:
	if course.space == null:
		return true
	var shape := SphereShape3D.new()
	shape.radius = GrenadeConfig.radius * RenderConfig.unit
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = course.mask
	query.exclude = course.passed
	var direction := _direction(course)
	var floor_y := GrenadeConfig.radius + ItemFlight.GROUND_GAP
	query.transform = Transform3D(Basis(), PlanSpace.lift(course.from + direction * reach, floor_y))
	query.motion = PlanSpace.lift(direction * (far - reach + SKID_SLACK))
	var res := course.space.cast_motion(query)
	return not res.is_empty() and res[0] >= 1.0


## The launch of `arc` first touching down `reach` px out.
static func _launch(
	course: GrenadeCourse,
	arc: Arc,
	reach: float,
	ok: bool,
	rest: Vector2,
) -> GrenadeLaunch:
	var launch := GrenadeLaunch.new()
	launch.ok = ok
	launch.capped = arc.capped
	launch.direction = _direction(course)
	launch.speed = reach / arc.time
	launch.rise = arc.rise
	launch.apex = arc.apex
	launch.time = arc.time
	launch.touchdown = course.from + launch.direction * reach
	launch.rest = rest
	return launch


## One arc of a plan: its peak `apex` (px, the centre's height), the launch `rise` (px/s up) and the
## flight `time` (s) from the hand to the floor, the `vdown` it falls at, how far the arm throws it
## (`cap`), where it first touches down so that it comes to rest at the aim (`reach`, -1 until
## solved), `capped` when it cannot get there, and the `farthest` it may be lobbed.
class Arc:
	var apex := 0.0
	var rise := 0.0
	var time := 0.0
	var vdown := 0.0
	var cap := 0.0
	var reach := -1.0
	var capped := false
	var farthest := 0.0


## The search of `plan` through the arcs and how far each is lobbed: how many `FIT_STEP`s farther
## than solved it is on (`step`), the arcs swept and flown so far, and the arc that rested nearest
## the aim.
class Fit:
	var step := 0
	var swept := 0
	var tries := 0
	var best: Dictionary = {}
	var best_off := INF
	## The apexes whose arc was struck early on its way: lobbing it farther strikes it again.
	var early := {}

	## Whether the budget of sweeps or of flights is used up.
	func spent() -> bool:
		return swept >= SWEEPS or tries >= FIT_TRIES

	## Keep the arc (first touching down `reach` out, resting at `rest`, `off` px from the aim) when
	## it rests nearer than any before.
	func offer(arc: Arc, reach: float, rest: Vector2, off: float) -> void:
		if off < best_off:
			best_off = off
			best = { "arc": arc, "reach": reach, "rest": rest }
