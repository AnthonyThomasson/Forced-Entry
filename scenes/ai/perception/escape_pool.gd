class_name EscapePool
extends RefCounted
## AI PERCEPTION sub-domain — THE FRAME'S POOL of escape work (`EscapeSearch`, `docs/grenades.md`
## G16), shared by every NPC fleeing a grenade as `DecisionBudget` is by every decision.
##
## `per_frame` units a physics frame (80: about 2 ms, a unit being about 25 us; `EscapeSearch`
## prices them) across every search. A search runs candidates while the pool lasts, so a frame
## spends the pool and at most one candidate's work (7 units) more.
##
## **The order.** Searches are served on each ask, in this order: a plan an NPC has none of yet
## before a replan; then the grenade that goes off first; then the runner nearest the burst (the
## NPC most in danger); then the search begun first. A search is first served the frame after it
## begins, so the NPCs that begin one on a frame are ordered together, not by who asked first. A
## search that cannot finish this frame continues the next, and the NPC carries on as it was (its
## old plan, or none) until it lands. A search its owner stops asking about is dropped after
## `STALE_FRAMES`.

## How many physics frames a search may go unasked before it is dropped (an NPC asks every second
## frame at the slowest).
const STALE_FRAMES := 30

## The units a physics frame holds across every search. Tests set it.
static var per_frame := 80
## The most units any physics frame has spent since `reset` (what tests observe).
static var peak_spent := 0
static var _pending: Array[EscapeSearch] = []
static var _spent := 0
static var _spent_frame := -1
static var _begun := 0


## Register `search` (begun at this physics frame, its grenade going off in `fuse` s, its runner
## `distance` px from the burst, `is_replan` when it replaces a plan), charging the units it was
## built with.
static func begin(
	search: EscapeSearch,
	is_replan: bool,
	fuse: float,
	distance: float,
) -> void:
	_roll_frame()
	var frame := Engine.get_physics_frames()
	_begun += 1
	search.key = [
		is_replan,
		frame + roundi(fuse * Engine.physics_ticks_per_second),
		distance,
		_begun,
		frame,
	]
	search.touched = frame
	_spent += int(search.work["built"])
	_pending.append(search)


## The owner asks after `search`: it is alive. Serve the pool, then whether it is done.
static func ask(search: EscapeSearch) -> bool:
	search.touched = Engine.get_physics_frames()
	serve(search.space, search.map)
	return search.done


## Give the frame's pool to the searches on `space` and `map`, in the order above, until it is
## spent. Safe to call at every ask: what is spent in a frame stays spent.
static func serve(space: PhysicsDirectSpaceState3D, map: RID) -> void:
	_roll_frame()
	var frame := Engine.get_physics_frames()
	_pending = _pending.filter(
		func(s: EscapeSearch) -> bool: return not s.done and frame - s.touched <= STALE_FRAMES
	)
	var order := _pending.filter(
		func(s: EscapeSearch) -> bool:
			return s.space == space and s.map == map and s.key[4] != frame
	)
	order.sort_custom(_before)
	for search: EscapeSearch in order:
		if _spent >= per_frame:
			break
		_spent += search.step(per_frame - _spent)
	peak_spent = maxi(peak_spent, _spent)


## Whether `search` is still being served (not finished, not dropped as stale).
static func serving(search: EscapeSearch) -> bool:
	return not search.done and _pending.has(search)


## Forget `search` (its grenade is gone).
static func cancel(search: EscapeSearch) -> void:
	search.done = true
	_pending.erase(search)


## Forget every search and the stats: a test's start.
static func reset() -> void:
	_pending.clear()
	_spent = 0
	_spent_frame = -1
	peak_spent = 0


## Start counting a new physics frame's spend.
static func _roll_frame() -> void:
	var frame := Engine.get_physics_frames()
	if frame != _spent_frame:
		_spent_frame = frame
		_spent = 0


## The order rule: no plan yet before a replan, the grenade that goes off first, the runner nearest
## the burst, the search begun first.
static func _before(a: EscapeSearch, b: EscapeSearch) -> bool:
	var ka: Array = a.key
	var kb: Array = b.key
	for i in 4:
		if ka[i] != kb[i]:
			return ka[i] < kb[i]
	return false
