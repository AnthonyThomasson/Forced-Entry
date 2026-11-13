extends RefCounted
## AI PERCEPTION sub-domain — the option groups of a snapshot's demand, built ahead of the walk in
## steps: a run of `GroupBuild`s, each begun when its turn comes and stored in the demand as it ends
## (`SnapshotDemand.store`), so the planner finds the group built. The decision job's group piece
## drives it (`decision-job.md`), a priced step at a time: `next_kind()` says what the next step is
## (`GroupBuild.Kind`: a unit of work, a build's free finish, or the end), `step()` runs it. Each
## step takes the demand's own scratch first (`open`), as any lazy read does, so a snapshot
## completed in between never leaves it the wrong decision's.

const GroupBuild := preload("res://scenes/ai/perception/snapshot/group_build.gd")
## The kinds of step, as `GroupBuild` says them.
const Kind := GroupBuild.Kind

## The demand the groups are stored in.
var demand: RefCounted
## The groups still to build, in order: `{ name, id }` (`id`: the hostile a `grenade_throws` group
## is of, `SnapshotDemand.GLOBAL` for a global group).
var _jobs: Array = []
var _job := {}
var _build: RefCounted


## Begin building the groups in `jobs` of `demand`.
func begin(demand_: RefCounted, jobs: Array) -> RefCounted:
	demand = demand_
	_jobs = jobs
	return self


## What the next step is (`Kind`): works through what needs no price first (the next group's begin,
## a group the demand holds already), a few reads at most.
func next_kind() -> int:
	var _scope: RefCounted = demand.open()
	while _build == null and not _jobs.is_empty():
		_job = _jobs.pop_front()
		if demand.holds(_job["name"], _job["id"]):
			continue
		_build = demand.begin_group(_job["name"], _job["id"])
		if _build.done():
			_end()
	if _build == null:
		return Kind.DONE
	return _build.next_kind()


## Whether every group is built.
func done() -> bool:
	return _build == null and _jobs.is_empty()


## Run the next step: a unit of the group in hand, or its finish.
func step() -> void:
	if next_kind() == Kind.DONE:
		return
	var _scope: RefCounted = demand.open()
	_build.step()
	if _build.done():
		_end()


## The group in hand is built: into the demand.
func _end() -> void:
	demand.store(_job["name"], _job["id"], _build.result)
	_build = null
