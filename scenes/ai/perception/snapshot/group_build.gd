extends RefCounted
## AI PERCEPTION sub-domain — an option group built in steps: the units of work its author splits
## it into (a lead's route, a doorway's pick, one grenade kind's throw), then one free step that
## puts what the units made into the group (the sort, the cap, the summary). The author
## (`SnapshotOptions`, `SnapshotThrows`) makes the units in the order its one-shot build works, so
## the rays, routes and random draws are the same and a group built a unit at a time equals the
## one built whole (`run`), whatever the pace. A caller that prices the steps (the decision job's
## group piece, `decision-job.md`) spreads the build over frames: `next_kind()` says what the next
## step is, `step()` runs it.

## What the next step is: one unit of work, the finish, or nothing (the group is built).
enum Kind {
	UNIT,
	FINISH,
	DONE,
}

## The group once built: `{ summary, options, ... }`.
var result := {}
var _units: Array[Callable] = []
var _finish: Callable
var _finished := false


## Set the build's `units` (one `Callable` a step) and the `finish` that returns the group.
func begin(units: Array[Callable], finish: Callable) -> RefCounted:
	_units = units
	_finish = finish
	return self


## A build with no work: the group `out` as it stands.
func already(out: Dictionary) -> RefCounted:
	result = out
	_finished = true
	return self


## What the next step is (`Kind`).
func next_kind() -> int:
	if not _units.is_empty():
		return Kind.UNIT
	return Kind.DONE if _finished else Kind.FINISH


## Whether the group is built.
func done() -> bool:
	return _finished and _units.is_empty()


## Run the next step: one unit, else the finish.
func step() -> void:
	if not _units.is_empty():
		var unit: Callable = _units.pop_front()
		unit.call()
	elif not _finished:
		_finished = true
		result = _finish.call()


## Run every step: the group, as the one-shot build makes it.
func run() -> Dictionary:
	while not done():
		step()
	return result
