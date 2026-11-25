class_name EscapeSearch
extends RefCounted
## AI PERCEPTION sub-domain — ONE ESCAPE SEARCH as a resumable job (`AgentThrow.escape`,
## `docs/grenades.md` G16): the nearest-in-time walk over the candidate spots, stepped a few at a
## time against the frame's pool (`EscapePool`) shared by every NPC fleeing a grenade, as the
## decision job is against `DecisionBudget`. A search holds everything it needs (the candidates in
## their order, the verdicts the frame shared, the best so far), so it continues next frame from
## where it stopped. Run whole it is the plain search (`run_whole`).
##
## **Units** (counts of work done, never a clock, so a replay spends the same): one new navmesh
## snap `SNAP_UNITS`, one new verdict `JUDGE_UNITS`, one route `ROUTE_UNITS` (the dearest: a path
## query), the candidates round a burst `AROUND_UNITS` (paid once, by the search that built them).
## A unit is about 25 us (measured in `perf/match_10v10_opening` at seed 23).

## How far (px) a candidate may be pulled by navmesh snapping, how far short of a spot its route may
## end and still reach it, and the float noise a path's length may carry (`AgentThrow` aliases).
const SNAP_TOLERANCE := 40.0
const ROUTE_REACH := 2.0
const PRUNE_SLACK := 0.01
const SNAP_UNITS := 1
const JUDGE_UNITS := 1
const ROUTE_UNITS := 5
const AROUND_UNITS := 16

## Whether it has finished (or been cancelled).
var done := false
## The answer when `done`: `{ spot, crouch, route }`.
var best := { "spot": Vector2.INF, "crouch": false, "route": INF }
## What the resolver and the search share (no reference back: the resolver is built first):
## `snaps` and `judges` the resolver counted, `routes` measured (the pruning's observable),
## `bound` the farthest a candidate may be (px, by straight line) and still win (the lesser of the
## run allowed and the best route so far, plus the start's slack: the resolver skips one that
## cannot), `built` the units the owner spent on the burst's candidates.
var work := { "snaps": 0, "judges": 0, "routes": 0, "bound": INF, "built": 0 }
## The world it searches, and the pool's order: `[replan, deadline, distance, seq, began]`, set by
## `EscapePool.begin`.
var space: PhysicsDirectSpaceState3D
var map: RID
var key: Array = []
## The physics frame its owner last asked about it (`EscapePool`).
var touched := 0
var _from: Vector2
var _allowed: float
var _slack: float
var _resolve: Callable
## The candidate order: `Vector2(straight distance, index)`, sorted.
var _order: Array = []
var _next := 0
var _best_index := -1
var _lengths := {}


## A search of `points` from `from` on `nav_map`: the safe spot with the shortest route within
## `allowed` px (`AgentThrow._nearest_in_time`'s contract), `resolver` turning a point's index into
## `{ spot, crouch }` or {}.
func _init(
	nav_map: RID,
	from: Vector2,
	points: Array,
	allowed: float,
	resolver: Callable,
) -> void:
	map = nav_map
	_from = from
	_allowed = allowed
	_resolve = resolver
	_slack = from.distance_to(NavBuilder.snap(map, from)) + ROUTE_REACH + PRUNE_SLACK
	work["bound"] = allowed + _slack
	# Vector2 sorts by x, then y: (straight distance, index in `points`), a native sort.
	for i in points.size():
		_order.append(Vector2(from.distance_to(points[i]), i))
	_order.sort()


## Run it to the end in one go: what `escape` does outside a physics frame, and the oracle the
## sliced search is held to (`escape_sliced_matches_whole_test`).
func run_whole() -> Dictionary:
	while not done:
		step(1_000_000)
	return best


## Work candidates until `units` are spent (or it is done), returning the units spent (a candidate
## in hand runs to its end, so up to one candidate's work over).
func step(units: int) -> int:
	var spent := 0
	while not done and spent < units:
		spent += _candidate()
	return spent


## One candidate of the order: resolved (snapped, judged) and routed unless it cannot win.
func _candidate() -> int:
	if _next >= _order.size():
		done = true
		return 0
	var entry: Vector2 = _order[_next]
	_next += 1
	if entry.x - SNAP_TOLERANCE > work["bound"]:
		done = true
		return 0
	var before := _counted()
	var index := int(entry.y)
	var s: Dictionary = _resolve.call(index)
	var cost := _counted() - before
	if s.is_empty():
		return cost
	var spot: Vector2 = s["spot"]
	# A route is never shorter than the straight line to its spot less the slack: one that cannot
	# beat the best (or fit the run) is not measured (strictly, so a tie still is).
	if _from.distance_to(spot) > work["bound"]:
		return cost
	var length := _route(spot)
	cost += ROUTE_UNITS
	if length <= _allowed and (length < best["route"]
			or (length == best["route"] and index < _best_index)):
		best = { "spot": spot, "crouch": s["crouch"], "route": length }
		_best_index = index
		work["bound"] = minf(_allowed, length) + _slack
	return cost


## The units of snaps and verdicts the resolver has counted so far.
func _counted() -> int:
	return int(work["snaps"]) * SNAP_UNITS + int(work["judges"]) * JUDGE_UNITS


## The length of the route from the start to `spot`, INF when it ends short of it
## (`ROUTE_REACH`); measured once.
func _route(spot: Vector2) -> float:
	if _lengths.has(spot):
		return _lengths[spot]
	var path := NavBuilder.route(map, _from, spot)
	work["routes"] += 1
	var length := (NavBuilder.path_length(path)
			if path[path.size() - 1].distance_to(spot) <= ROUTE_REACH
			else INF)
	_lengths[spot] = length
	return length
