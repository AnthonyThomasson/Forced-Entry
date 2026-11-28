class_name EscapePool
extends RefCounted
## AI PERCEPTION sub-domain — THE FRAME'S POOL of escape work (`EscapeSearch`, `docs/grenades.md`
## G16), shared by every NPC fleeing a grenade as `DecisionBudget` is by every decision.
##
## `per_frame` units a physics frame (80: about 2 ms, a unit being about 25 us; `EscapeSearch`
## prices them) across every search. A search runs candidates while the pool lasts, so a frame
## serves the pool and at most one candidate's work (7 units) more; while a search is urgent it
## holds `urgent_extra` units more (167 at the most). The candidates round a burst (16 units, paid
## by the search that begins a grenade's first) are charged when the search begins and are not
## served: they never take a frame's pool from the searches waiting (`peak_spent` counts both).
##
## **The order.** Searches are served on each ask, in this order: an urgent search first (see
## `urgent`), the one whose grenade goes off first of them, the one begun first of those; then a
## plan an NPC has none of yet before a replan; then the grenade that goes off first; then the
## runner nearest the burst (the NPC most in danger); then the search begun first. A search is first
## served the frame after it begins, so the NPCs that begin one on a frame are ordered together,
## not by who asked first. A search that cannot finish this frame continues the next, and the NPC
## carries on as it was (its old plan, or none) until it lands. A search its owner stops asking
## about is dropped after `STALE_FRAMES` (and is not served again if asked about), one whose NPC
## is gone is cancelled. The order is made once a frame.
##
## **The bound on a wait** (for an owner asking at least every `STALE_FRAMES`: one that does not has
## its search dropped and begins another). A search's deadline is its grenade's fuse frame less
## `ARRIVE_MARGIN`: the latest its plan may land and still arrive. Once urgent, a search is behind
## only the urgent searches whose grenade goes off sooner (or as soon, and begun first), so it lands
## when the work of those has been served: within `AGE_FRAMES` (until it is urgent) plus that work
## over the pool and the urgent extra. So (1) among searches of one fuse (or of a fuse no sooner
## than the searches begun before it) a search lands within `AGE_FRAMES` plus the work of the
## searches begun before it or on its frame, over the pool, whatever begins after it; (2) a search
## lands by its deadline whenever the work of the searches whose fuse is no later than its own fits
## in the time. Under overload nothing is promised: a search past its deadline has the soonest fuse
## of the urgent ones, so it heads them, ahead of searches that could still make theirs. A fuse
## frame is the fuse left rounded to frames from the frame the search began, so two NPCs fleeing one
## grenade can have fuse frames 1 apart, and the order takes them as two fuses. The trade: a search
## with a long fuse waits behind searches begun after it with a sooner fuse, so a far search behind
## a stream of sooner fuses has only its deadline for a bound, not `AGE_FRAMES` plus the work before
## it (`escape_pool_bounds_wait`), and a frag thrown just after a wave round a stun is served before
## the wave's tail.

const AgentThrow := preload("res://scenes/ai/perception/agent_throw.gd")
## How many physics frames a search may go unasked before it is dropped (an NPC asks every second
## frame at the slowest).
const STALE_FRAMES := 30
## How many physics frames a search may wait before it is served first, the one begun first of them
## (the bound on a wait), and the frames added to `ARRIVE_MARGIN` within which a search whose
## grenade is about to go off is served first as well.
const AGE_FRAMES := 12

## The units a physics frame holds across every search. Tests set it.
static var per_frame := 80
## The units a frame holds on top of that while any search is urgent (a wait past `AGE_FRAMES`, or a
## fuse about to run out): a wave too big for the pool is then served at twice its rate, so its
## last NPCs are not caught for waiting. Tests set it.
static var urgent_extra := 80
## The most units any physics frame has spent since `reset`, serving searches and building the
## candidates round a burst (16 a new grenade) together (what tests observe).
static var peak_spent := 0
## The most units any physics frame has served searches since `reset`: the pool, the urgent extra
## and one candidate (167 at the most), whatever the candidates round new bursts cost.
static var peak_served := 0
static var _pending: Array[EscapeSearch] = []
static var _served := 0
static var _built := 0
static var _spent_frame := -1
static var _order: Array[EscapeSearch] = []
static var _order_frame := -1
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
		false,
	]
	search.touched = frame
	_built += int(search.work["built"])
	peak_spent = maxi(peak_spent, _served + _built)
	_pending.append(search)


## The owner asks after `search`: it is alive. Serve the pool, then whether it is done.
static func ask(search: EscapeSearch) -> bool:
	search.touched = Engine.get_physics_frames()
	serve(search.space, search.map)
	return search.done


## Give the frame's pool to the searches on `space` and `map`, in the order above, until it is
## spent. Safe to call at every ask: what is spent in a frame stays spent, and the order is made
## once a frame (`_order_of`), a call after the frame's pool is spent returns at once.
static func serve(space: PhysicsDirectSpaceState3D, map: RID) -> void:
	_roll_frame()
	if _served >= per_frame + urgent_extra:
		return
	var order := _order_of(Engine.get_physics_frames())
	var first := _first_live(order, space, map)
	var limit := per_frame + (urgent_extra if first != null and first.key[5] else 0)
	for search: EscapeSearch in order:
		if _served >= limit:
			break
		if search.space == space and search.map == map and _live(search):
			_served += search.step(limit - _served)
	peak_spent = maxi(peak_spent, _served + _built)
	peak_served = maxi(peak_served, _served)


## Whether `search` is served ahead of the order below: begun `AGE_FRAMES` ago or more, or its
## grenade goes off within `ARRIVE_MARGIN` and `AGE_FRAMES` (a plan that lands later arrives with no
## margin).
static func urgent(search: EscapeSearch, frame: int) -> bool:
	var margin := ceili(AgentThrow.ARRIVE_MARGIN * Engine.physics_ticks_per_second)
	return (
		frame - int(search.key[4]) >= AGE_FRAMES
		or int(search.key[1]) - frame <= margin + AGE_FRAMES
	)


## Whether `search` is still being served (not finished, not dropped as stale).
static func serving(search: EscapeSearch) -> bool:
	return (
		not search.done
		and Engine.get_physics_frames() - search.touched <= STALE_FRAMES
		and _pending.has(search)
	)


## Forget `search` (its grenade is gone).
static func cancel(search: EscapeSearch) -> void:
	search.done = true
	_pending.erase(search)


## Forget every search and the stats: a test's start.
static func reset() -> void:
	_pending.clear()
	_served = 0
	_spent_frame = -1
	_order.clear()
	_order_frame = -1
	peak_spent = 0
	peak_served = 0
	_built = 0


## The searches served at `frame`, in the order above, made on the frame's first call: the pool
## kept to the searches that stay (`_kept`), those begun this frame left out (served from the next),
## each with its urgency (`key[5]`) set.
static func _order_of(frame: int) -> Array[EscapeSearch]:
	if _order_frame != frame:
		_order_frame = frame
		_pending = _pending.filter(_kept.bind(frame))
		_order.clear()
		for search: EscapeSearch in _pending:
			if search.key[4] != frame:
				search.key[5] = urgent(search, frame)
				_order.append(search)
		_order.sort_custom(_before)
	return _order


## The first of `order` on `space` and `map` still being served, null if none.
static func _first_live(
	order: Array[EscapeSearch],
	space: PhysicsDirectSpaceState3D,
	map: RID,
) -> EscapeSearch:
	for search: EscapeSearch in order:
		if search.space == space and search.map == map and _live(search):
			return search
	return null


## Whether `search` is still to be served this frame: not finished, and its owner (if it has one)
## still there (one that has gone since the order was made is cancelled).
static func _live(search: EscapeSearch) -> bool:
	if search.done:
		return false
	if search.alive.is_valid() and not search.alive.call():
		search.done = true
		return false
	return true


## Whether `search` stays in the pool at `frame`: not finished, asked after within `STALE_FRAMES`
## (one that was not is only dropped: its owner begins a new one), and its owner still there (one
## that is gone is cancelled).
static func _kept(search: EscapeSearch, frame: int) -> bool:
	if search.done:
		return false
	if search.alive.is_valid() and not search.alive.call():
		search.done = true
		return false
	return frame - search.touched <= STALE_FRAMES


## Start counting a new physics frame's spend.
static func _roll_frame() -> void:
	var frame := Engine.get_physics_frames()
	if frame != _spent_frame:
		_spent_frame = frame
		_served = 0
		_built = 0


## The order rule: an urgent search before the rest, the one whose grenade goes off first of them
## first, then the one begun first (a wave begun on one frame stays in the order below); then no
## plan yet before a replan, the grenade that goes off first, the runner nearest the burst, the
## search begun first.
static func _before(a: EscapeSearch, b: EscapeSearch) -> bool:
	var ka: Array = a.key
	var kb: Array = b.key
	if ka[5] != kb[5]:
		return ka[5]
	if ka[5]:
		for i in [1, 4]:
			if ka[i] != kb[i]:
				return ka[i] < kb[i]
	for i in 4:
		if ka[i] != kb[i]:
			return ka[i] < kb[i]
	return false
