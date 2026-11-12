extends RefCounted
## AI DECISION sub-domain: who is deciding, in what order, for the pool of `DecisionBudget`. NPCs
## take their turn in the scene tree's order, which says nothing of whose decision began first, so
## with the pool shared by every NPC a decision begun late in a crowd would be served after a
## newcomer ahead of it in the tree again and again. The roster fixes the order the pool is served
## in, whatever the tree's: the oldest claim first, so a job in flight is served before any new
## start, and a job is never overtaken by one begun after it (the bound: it waits for the jobs
## older than itself, and no others, ever).
##
## Each job in flight notes what its next piece costs when its turn in a frame ends. A job asking
## the pool for a piece first sets aside what the older jobs that have not had their turn this
## frame still need (`owed`), so a younger one that comes first in the tree runs only on what is
## left. A job that was not served for the last three frames (its NPC is gone or does not think)
## owes nothing: a stalled job holds no one up. An NPC that stops thinking says so at once instead
## (`DecisionJob.rest`, `release`), so it holds no one up even for those frames.
##
## The starts are in the scene tree's order: NPCs ask for the frame's one start in the tree's order
## and it goes to the first that asks, so with many wishes at once an NPC late in the tree starts
## after the ones before it, each wish being asked again every frame. The roster orders the pool
## between jobs in flight, not the starts (a known limit, `decision-job.md`).
##
## At most one decision begins in a physics frame whatever the pool holds (`may_start`).

## job id -> `{ seq, cost, frame }`: the claim's order, what the next piece costs and the frame
## the job last had its turn.
static var _entries := {}
## The claim counter.
static var _seq := 0
## The physics frame a decision last began on.
static var _start_frame := -1


## Whether no decision has begun in this physics frame yet.
static func may_start() -> bool:
	return _start_frame != DecisionBudget.frame()


## A decision began in this physics frame: `job` is the youngest claim now, with nothing yet to
## pay for (its start is paid by the claim). The jobs that have not had a turn for three frames
## (their NPC freed) are forgotten.
static func began(job: int) -> void:
	_start_frame = DecisionBudget.frame()
	for id in _entries.keys():
		if _entries[id]["frame"] < _start_frame - 2:
			_entries.erase(id)
	_seq += 1
	_entries[job] = { "seq": _seq, "cost": 0, "frame": _start_frame }


## `job`'s turn in this frame ended: its next piece costs `cost` (0: nothing to run, as a walk that
## waits for Von). A job the roster had forgotten (it was not served for a while, then ran again)
## takes its place again, as the youngest claim.
static func note(job: int, cost: int) -> void:
	if not _entries.has(job):
		_seq += 1
		_entries[job] = { "seq": _seq, "cost": cost, "frame": DecisionBudget.frame() }
		return
	var entry: Dictionary = _entries[job]
	entry["cost"] = cost
	entry["frame"] = DecisionBudget.frame()


## `job` is no longer in flight (decided, failed, dropped or freed).
static func leave(job: int) -> void:
	_entries.erase(job)


## What the jobs older than `job` (than a new claim by it, with `fresh`) that have not had their
## turn in this frame still need: what a piece of `job` must leave in the pool for them. Its own
## entry owes nothing.
static func owed(job: int, fresh := false) -> int:
	var frame := DecisionBudget.frame()
	var mine: Dictionary = _entries.get(job, {})
	var behind: int = _seq + 1 if fresh else mine.get("seq", _seq + 1)
	var total := 0
	for id in _entries:
		var entry: Dictionary = _entries[id]
		if id != job and entry["seq"] < behind and entry["frame"] < frame and (
				entry["frame"] >= frame - 2):
			total += entry["cost"]
	return total


## Forget every job and the frame a decision last began on (a test's cleanup).
static func reset() -> void:
	_entries.clear()
	_seq = 0
	_start_frame = -1
