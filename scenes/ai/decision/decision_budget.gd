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
## One unit is about half a millisecond of the piece's work, measured per piece in the 10v10 match
## (`decision-prices.md`): a decision lands over a few frames and a frame's decision work stays
## near the pool's 3 ms. A piece that costs nothing is too cheap to price (the order-refusal step,
## a planner level, each well under a millisecond), so it runs whenever its turn comes. A test that
## means a decision to run whole in one frame sets the pool to one and every piece but the claim's
## start to nothing (`tests/_ai/job_fakes.gd`).
##
## The pool is served oldest claim first, whatever order NPCs take their turn in, and at most one
## decision begins in a frame whatever the pool holds (`decision_roster.gd`): `take`'s `owed` is
## what the older jobs still need this frame.

const Roster := preload("res://scenes/ai/decision/decision_roster.gd")

## Work units that may be spent in one physics frame: about 3 ms of decision work (a unit is about
## half a millisecond), a typical decision landing over three to four frames. A test raises it
## to see the pieces of many decisions run in one frame; it never lets two decisions start in one
## (`decision_roster.gd`).
static var per_frame: int = 6
## What the order-refusal step (0.01 ms) and one planner level (0.1 ms, the odd level that builds a
## lazy group 2 to 7) cost; the snapshot build's pieces are priced in `DecisionPrices`.
static var cost_refusal: int = 0
static var cost_level: int = 0
## What a step of the throw search costs (the piece between the order-refusal step and the walk,
## which resolves the `grenade_ready` fact): a block of the throw-spot scan (`ThrowSpots.block_size`
## candidates, ending at `ThrowSpots.block_work` of work: about a millisecond), the rank pass and
## one route (each about a millisecond).
static var cost_throw_block: int = 2
static var cost_throw_rank: int = 2
static var cost_throw_route: int = 2
## What a step of the group piece costs (the piece between the order-refusal step and the throw
## piece, which builds the leads and, with a stun in the stack, the entries the root reads; and the
## piece after it that builds the throws at the hostiles, the one the search found one at first):
## one unit of work, a lead's route, a doorway's pick, one kind's throw spot step (about a
## millisecond), and the finish that sorts and caps what the units made (free: no price to set).
static var cost_group_unit: int = 2
## The throw search's work (`ThrowSpots.work()`, a count in quarter-units: four per
## `GrenadeArc.work`, one a raw candidate tested, not a time: about 0.01 ms each) one unit holds: a
## priced step that did more than its price's worth (a throw block of 80 is 2 units) is charged the
## rest once it has run (`charge`), so a frame holds one such block, not four heavy ones from four
## NPCs. 0: no charge.
static var work_unit: int = 40
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


## Charge the pool for a priced step (`cost` units, taken) that did `work` of planner work: the
## units its work is worth beyond `cost`. What is over the pool refuses every piece after it this
## frame.
static func charge(work: int, cost: int) -> void:
	if cost <= 0 or work_unit <= 0:
		return
	var extra := ceili(float(work) / float(work_unit)) - cost
	if extra > 0:
		_spent += extra


## Forget the frame's spending and every job in flight (a test's cleanup: a unit suite that stood in
## for the frame leaves none of its units behind).
static func reset() -> void:
	_frame = -1
	_spent = 0
	Roster.reset()
