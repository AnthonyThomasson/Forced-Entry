extends RefCounted
## AI PERCEPTION sub-domain — SNAPSHOT LEAD MEMO. The walks to the leads an NPC heard (the length of
## the route it would walk and the point the lead snaps to), remembered for the belief window
## (`tuning.decision.belief_redecide_interval`, 0.5 s) so the decisions made inside one do not walk
## them again. A walk is kept by its two ends and answers only while the house is as it was when
## the window began: the planning map and its ring have the iterations they had (a re-bake of
## either swapped in starts the walks afresh, as `NavSnaps` and `NavRoutes` follow it) and no door
## has turned, fallen or come up since (`door_state`). The window ends the memo whatever happened;
## a window of nothing keeps nothing. `snapshot_options.gd` holds one per NPC.

## Most walks kept before the memo starts afresh.
const KEPT := 64

## The physics frame `door_state` last read the doors in, and what it read.
static var _doors_frame := -1
static var _doors_sig := 0

## `[from, to]` -> `{ len, snap }`.
var _walks := {}
## `GameClock` msec the window began.
var _stamp_ms := 0
## The planning map's and its ring's iterations and the doors' state the kept walks were made at.
var _iteration: Array = []
var _doors := 0


## A number that changes whenever a door of the house turns, comes to rest elsewhere, is knocked
## down or put up again: each door's angle and whether it is down (the door contract, interface 24),
## read once a physics frame for every NPC of the world.
static func door_state(tree: SceneTree) -> int:
	var frame := Engine.get_physics_frames()
	if frame == _doors_frame:
		return _doors_sig
	var sig := 0
	for door: Node in tree.get_nodes_in_group(&"doors"):
		if door.has_method("angle") and door.has_method("is_down"):
			sig = hash([sig, door.get_instance_id(), door.angle(), door.is_down()])
	_doors_frame = frame
	_doors_sig = sig
	return sig


## Start asking: forget every walk kept for another window, the planning-map or ring iterations
## of `map` or the state of the doors (`doors`, `door_state`). `window_s` is the window's length.
func open(map: RID, doors: int, window_s: float) -> void:
	var now := GameClock.msec()
	var iteration := NavBuilder.iterations(map)
	if (iteration == _iteration and doors == _doors and now >= _stamp_ms
			and now - _stamp_ms < roundi(window_s * 1000.0) and _walks.size() < KEPT):
		return
	_walks.clear()
	_stamp_ms = now
	_iteration = iteration
	_doors = doors


## The walk kept for `from` → `to` (`{ len, snap }`), or null.
func recall(from: Vector2, to: Vector2) -> Variant:
	return _walks.get([from, to])


## Keep `walk` for `from` → `to` until the window ends or the house changes.
func keep(from: Vector2, to: Vector2, walk: Dictionary) -> void:
	_walks[[from, to]] = walk
