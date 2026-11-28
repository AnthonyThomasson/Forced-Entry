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
## The order is not the claim's alone: a forced decision's reason ranks it (`rank_of`). A job in
## flight is served after the jobs of a better rank (attacked and a new hostile, then an order, a
## task resolved, following, a way blocked, any other reason, a cadence decision last) and, within
## a rank, after the older ones; so under fire an NPC's decision is not queued behind the routine
## ones begun before it. A rank ages, in frames, never by a clock: a job's effective rank is its
## reason's rank less one for every `AGE_FRAMES` frames since its claim (`_aged`, never below 0).
## That is the starvation bound: a stream of better claims holds a job back until it reaches rank 0,
## at the worst `OTHER_RANK` x `AGE_FRAMES` (150) frames after its claim; there it ranks with them
## and, begun before every one of them, is served first, and its own build (a few frames) follows.
## A routine decision and an ordered one (rank 1: it waited 122 frames in the opening before) alike.
##
## At most one decision begins in a physics frame whatever the pool holds (`may_start`).

## The rank of a forced decision's reason: 0 is served first. Reasons not named here (and "cadence")
## rank `OTHER_RANK`. The engaged contact lost is a change of the hostile belief too
## (`goal_controller.gd`'s salient key): it ranks with it. "sight returned" is the NPC's own
## blindness ending (`npc_reflexes.gd`), not a hostile seen again: rank 0 because an NPC just
## unblinded must decide again at once.
const REASON_RANK := {
	"attacked": 0,
	"hostile belief changed": 0,
	"sight returned": 0,
	"lost the engaged contact": 0,
	"ordered": 1,
	"task resolved": 2,
	"follows its leader": 3,
	"way blocked": 4,
}
const OTHER_RANK := 5
## Frames a claim waits for its rank to improve by one.
const AGE_FRAMES := 30

## job id -> `{ seq, rank, claim, cost, frame }`: the claim's order, its reason's rank, the frame it
## was claimed on, what the next piece costs and the frame the job last had its turn.
static var _entries := {}
## The claim counter.
static var _seq := 0
## The physics frame a decision last began on.
static var _start_frame := -1
## How many decisions have begun (`began` calls) since the last `reset`.
static var _claims := 0


## The rank of a decision begun for `reason` (`REASON_RANK`).
static func rank_of(reason: String) -> int:
	return REASON_RANK.get(reason, OTHER_RANK)


## Whether no decision has begun in this physics frame yet.
static func may_start() -> bool:
	return _start_frame != DecisionBudget.frame()


## A decision began in this physics frame: `job` is the youngest claim now, with nothing yet to
## pay for (its start is paid by the claim). The jobs that have not had a turn for three frames
## (their NPC freed) are forgotten.
static func began(job: int, rank := OTHER_RANK) -> void:
	_start_frame = DecisionBudget.frame()
	_claims += 1
	for id in _entries.keys():
		if _entries[id]["frame"] < _start_frame - 2:
			_entries.erase(id)
	_seq += 1
	_entries[job] = {
		"seq": _seq, "rank": rank, "claim": _start_frame, "cost": 0, "frame": _start_frame,
	}


## `job`'s turn in this frame ended: its next piece costs `cost` (0: nothing to run, as a walk that
## waits for Von). A job the roster had forgotten (it was not served for a while, then ran again)
## takes its place again, as the youngest claim.
static func note(job: int, cost: int) -> void:
	if not _entries.has(job):
		_seq += 1
		_entries[job] = {
			"seq": _seq, "rank": OTHER_RANK, "claim": DecisionBudget.frame(), "cost": cost,
			"frame": DecisionBudget.frame(),
		}
		return
	var entry: Dictionary = _entries[job]
	entry["cost"] = cost
	entry["frame"] = DecisionBudget.frame()


## `job` is no longer in flight (decided, failed, dropped or freed).
static func leave(job: int) -> void:
	_entries.erase(job)


## What the jobs ahead of `job` (of a better rank, or of its rank and older; or, for a new claim by
## it, `fresh`, of `rank`'s rank or better) that have not had their turn in this frame still need:
## what a piece of `job` must leave in the pool for them. Its own entry owes nothing.
static func owed(job: int, fresh := false, rank := OTHER_RANK) -> int:
	var frame := DecisionBudget.frame()
	var mine: Dictionary = _entries.get(job, {})
	var my_rank: int = rank if fresh else _aged(mine, frame)
	var behind: int = _seq + 1 if fresh else mine.get("seq", _seq + 1)
	var total := 0
	for id in _entries:
		var entry: Dictionary = _entries[id]
		var their_rank := _aged(entry, frame)
		var same_rank_older: bool = their_rank == my_rank and entry["seq"] < behind
		var ahead: bool = their_rank < my_rank or same_rank_older
		if id != job and ahead and entry["frame"] < frame and entry["frame"] >= frame - 2:
			total += entry["cost"]
	return total


## The rank of a job's entry as it stands at `frame`: its reason's rank less a step for every
## `AGE_FRAMES` since its claim, never below 0 (an entry with no entry: the worst rank).
static func _aged(entry: Dictionary, frame: int) -> int:
	if entry.is_empty():
		return OTHER_RANK
	return maxi(0, entry["rank"] - floori(float(frame - entry["claim"]) / float(AGE_FRAMES)))


## How many decisions have begun, each `began` one claim, since the last `reset`: a job the roster
## forgot that runs again (`note` re-registers it) is not counted. A perf test's worst-frames
## report reads the rise of it between frames (`tests/_perf/frame_report.gd`).
static func claims() -> int:
	return _claims


## Forget every job and the frame a decision last began on (a test's cleanup).
static func reset() -> void:
	_entries.clear()
	_seq = 0
	_claims = 0
	_start_frame = -1
