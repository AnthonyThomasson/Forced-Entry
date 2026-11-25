class_name EscapePool
extends RefCounted
## AI PERCEPTION sub-domain — THE FRAME'S POOL of escape work (`EscapeSearch`, `docs/grenades.md`
## G16), shared by every NPC fleeing a grenade as `DecisionBudget` is by every decision.
##
## `per_frame` units a physics frame (80: about 2 ms, a unit being about 25 us; `EscapeSearch`
## prices them) across every search. A search runs candidates while the pool lasts, so a frame
## spends the pool and at most one candidate's work (7 units) more; while a search is urgent it
## holds `urgent_extra` units more.
##
## **The order.** Searches are served on each ask, in this order: an urgent search first (see
## `urgent`), the one begun first of them; then a plan an NPC has none of yet before a replan; then
## the grenade that goes off first; then the runner nearest the burst (the NPC most in danger); then
## the search begun first. So a wait is bounded: a search lands within `AGE_FRAMES` plus the work of
## the searches begun before it or on its frame, over the pool, whatever begins after it. A search
## is first served the frame after it begins, so the NPCs that begin one on a frame are ordered
## together, not by who asked first. A search that cannot finish this frame continues the next, and
## the NPC carries on as it was (its old plan, or none) until it lands. A search its owner stops
## asking about is dropped after `STALE_FRAMES` (and is not served again if asked about), one whose
## NPC is gone is cancelled.

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
## The most units any physics frame has spent since `reset` (what tests observe).
static var peak_spent := 0
## The most units any physics frame has spent serving searches (`peak_spent` less what the
## candidates round a burst cost to begin one) since `reset`: the pool and one candidate.
static var peak_served := 0
static var _pending: Array[EscapeSearch] = []
static var _spent := 0
static var _built := 0
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
		false,
	]
	search.touched = frame
	_spent += int(search.work["built"])
	_built += int(search.work["built"])
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
	_pending = _pending.filter(_kept.bind(frame))
	var order := _pending.filter(
		func(s: EscapeSearch) -> bool:
			return s.space == space and s.map == map and s.key[4] != frame
	)
	for search: EscapeSearch in order:
		search.key[5] = urgent(search, frame)
	order.sort_custom(_before)
	var limit := per_frame + (urgent_extra if not order.is_empty() and order[0].key[5] else 0)
	for search: EscapeSearch in order:
		if _spent >= limit:
			break
		_spent += search.step(limit - _spent)
	peak_spent = maxi(peak_spent, _spent)
	peak_served = maxi(peak_served, _spent - _built)


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
	_spent = 0
	_spent_frame = -1
	peak_spent = 0
	peak_served = 0
	_built = 0


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
		_spent = 0
		_built = 0


## The order rule: an urgent search before the rest, the one begun first of them first (a wave
## begun on one frame stays in the order below); then no plan yet before a replan, the grenade that
## goes off first, the runner nearest the burst, the search begun first.
static func _before(a: EscapeSearch, b: EscapeSearch) -> bool:
	var ka: Array = a.key
	var kb: Array = b.key
	if ka[5] != kb[5]:
		return ka[5]
	if ka[5] and ka[4] != kb[4]:
		return ka[4] < kb[4]
	for i in 4:
		if ka[i] != kb[i]:
			return ka[i] < kb[i]
	return false
