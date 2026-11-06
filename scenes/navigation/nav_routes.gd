class_name NavRoutes
extends RefCounted
## Exact answers to `NavBuilder.route`, remembered by the public planning map and its two endpoints.
## A district's ring may supply the answer instead, so both maps' iterations validate every entry:
## either one re-baking starts the answers afresh. Only a ready map reaches this cache, and the
## final route after any ring-to-district fallback is what is kept.

## Most routes kept per map before its answers start afresh.
const KEPT := 4096
## Most maps whose routes are kept.
const MAPS_KEPT := 32

## Public map RID -> `{ iteration: [district, ring], routes: { [from, to]: path } }`.
static var _answers: Dictionary = {}
## How many path queries the memo has sent to NavigationServer2D; an observable of a cache miss.
static var server_queries := 0


## The route the ring-first, district-fallback algorithm gives, from the memo when this exact
## question was answered while both supplying maps stood at the same iterations.
static func route(map: RID, from: Vector2, to: Vector2) -> PackedVector2Array:
	var ring := NavRing.map_of(map)
	var iteration := [
		NavigationServer2D.map_get_iteration_id(map),
		NavigationServer2D.map_get_iteration_id(ring) if ring.is_valid() else -1,
	]
	var kept: Dictionary = _answers.get(map, {})
	if kept.get("iteration", []) != iteration or (kept["routes"] as Dictionary).size() >= KEPT:
		if _answers.size() > MAPS_KEPT:
			_answers.clear()
		kept = { "iteration": iteration, "routes": {} }
		_answers[map] = kept
	var remembered: Dictionary = kept["routes"]
	var ends := [from, to]
	if remembered.has(ends):
		return (remembered[ends] as PackedVector2Array).duplicate()
	var asked := NavRing.map_for(map, ends)
	server_queries += 1
	var path := NavigationServer2D.map_get_path(asked, from, to, true)
	if asked != map and not NavRing.keeps(asked, path, to):
		server_queries += 1
		path = NavigationServer2D.map_get_path(map, from, to, true)
	var answer := path if path.size() >= 2 else PackedVector2Array([from, to])
	remembered[ends] = answer.duplicate()
	return answer


## Forget a freed public map's routes. Ring answers live under their public planning map's entry.
static func forget(map: RID) -> void:
	_answers.erase(map)
