class_name DecisionBudget
extends RefCounted
## AI DECISION sub-domain: the work units NPCs may spend on decisions in one physics frame, a pool
## shared by every NPC. A decision (`decision_job.gd`) is a run of pieces: the snapshot build's
## start, one per analysed hostile and its finish, the order-refusal step, then one per planner
## level. Building a snapshot is the costliest thing an NPC does in a frame, and NPCs that spawned
## or came under fire together want to decide on the same frame, so each piece asks here for its
## price before it runs. A refused NPC keeps its wish and asks again next frame, so one waits at
## most a frame per NPC ahead of it. Units are counted, never timed, so when an NPC decides never
## depends on the machine's speed: a test sees the same frames every run, and two NPCs that would
## claim the same flank side on one frame decide on different ones, each hearing the other's radio
## first (`tests/ai/decision/decisions_spread_over_frames_test.gd`).
##
## At the default prices a decision's first piece costs the one unit the pool holds and every later
## piece nothing, so one whole decision is one unit: it starts and finishes in a frame as it always
## has. Re-pricing the pieces is what slices a decision over frames.
##
## The pool is served oldest claim first, whatever order NPCs take their turn in, and at most one
## decision begins in a frame whatever the pool holds (`decision_roster.gd`): `take`'s `owed` is
## what the older jobs still need this frame.

const Roster := preload("res://scenes/ai/decision/decision_roster.gd")

## Work units that may be spent in one physics frame. A test raises it to see every NPC decide at
## once.
static var per_frame: int = 1
## What each kind of piece costs: a decision's first piece (the snapshot build's start; the claim),
## one analysed hostile, the build's finish, the order-refusal step, one planner level.
static var cost_start: int = 1
static var cost_hostile: int = 0
static var cost_finish: int = 0
static var cost_refusal: int = 0
static var cost_level: int = 0
## What a step of the throw search costs (the piece between the order-refusal step and the walk,
## which resolves the `grenade_ready` fact): a block of `throw_block` raw candidates, the rank pass,
## one route. The default, nothing, keeps the search whole in the frame its decision's walk begins.
static var cost_throw_block: int = 0
static var cost_throw_rank: int = 0
static var cost_throw_route: int = 0
## Raw throw-spot candidates one block step works through.
static var throw_block: int = 16
## Where the frame number comes from, when not the engine's physics frame: a unit test steps frames
## by it, with no engine running them (the way `DecisionStub.source` stands in for the server).
static var frame_source := Callable()
## The physics frame the spending is for.
static var _frame := -1
## Units spent this frame.
static var _spent := 0


## The physics frame the pool is spent in (the engine's, or a unit suite's `frame_source`).
static func frame() -> int:
	return frame_source.call() if frame_source.is_valid() else Engine.get_physics_frames()


## Whether a piece costing `cost` units may run now: it fits what is left of the frame's pool after
## the `owed` older jobs still need, or the pool is untouched and nothing is owed (a piece dearer
## than the whole pool then runs alone, so a job never stalls, and nothing is left for anyone
## else). A true answer spends the units; a piece costing nothing always runs.
static func take(cost: int, owed := 0) -> bool:
	if cost <= 0:
		return true
	var now := frame()
	if now != _frame:
		_frame = now
		_spent = 0
	if (_spent > 0 or owed > 0) and _spent + cost + owed > per_frame:
		return false
	_spent += cost
	return true


## Forget the frame's spending and every job in flight (a test's cleanup: a unit suite that stood in
## for the frame leaves none of its units behind).
static func reset() -> void:
	_frame = -1
	_spent = 0
	Roster.reset()
