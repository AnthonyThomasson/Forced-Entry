extends RefCounted
## AI DECISION sub-domain: ONE decision as a job the controller drives with `request(forced)` and a
## per-frame `advance()`. It owns the claim (the budget's pool, `decision_budget.gd`), the retry
## (a refused claim changes nothing, so the controller's wish stands and is asked again next
## frame), the snapshot build in its pieces (`AgentPerception.begin_sense`), the order-refusal step
## and the planner's walk, one piece per level. Every piece is priced in `DecisionBudget` and runs
## only when the frame's pool allows, so at the default prices (the claim's start costs the pool's
## one unit, every later piece nothing) a whole decision runs in the frame it was claimed and each
## later level as Von answers it, and a re-pricing slices it over frames.
##
## A claim made while a job is in flight (half-built, or walking) drops that job without a signal
## and starts the new one; refused, the job in flight carries on. A dropped build is freed, never
## resumed (`snapshot-staged.md`). What the last decision knew (`last_facts`, `last_sections`,
## `last_demand`, `last_analysed`, on the cadence) changes only when a build completes.
##
## What is read when. At the claim (the build's first `advance`, the claim frame's): the goal, the
## activity, the engaged contact (`reads`), whether the behaviour's last choice is still running
## (`ongoing`, judged for "(your current plan)" on that state), the order held and the entry the
## decision starts from (the planner's entry rule over the perception's quick facts). The build's
## START freezes the knowledge and the confinement copy (`perception.md`). After the build, at the
## order-refusal step: the live confinement refreshed (`refresh`) when the order the build saw is
## refused, replacing the snapshot's copy before the first level.
##
## Interrupting (`stale`, `frozen`): the controller applies one test to a job in flight. A walk is
## stale when the situation's entry (`entry_for(quick_facts)`) is not the one it started from; a
## build is stale when it is not the one the build started from (its start-time facts). Stale, a
## forced decision claims over it. Not stale, a walk is left to finish and the wish is dropped; a
## build whose START has run (`frozen`) has not seen what forced it, so the wish is kept until the
## walk begins.
##
## A data part, no owner (ADR 0006): it holds the perception, the planner and the cadence its
## controller hands it and three reads of the behaviour and reflexes as `Callable`s.

## Where the job is: claimed (its start still to run, paid for by the claim), building, taking its
## order-refusal step, or walking.
enum Stage {
	IDLE,
	CLAIMED,
	BUILD,
	REFUSAL,
	WALK,
}

## The snapshot build's piece kinds (`SnapshotBuild.Piece`), to price them.
const SnapshotBuild := preload("res://scenes/ai/perception/snapshot/snapshot_build.gd")
const Budget := preload("res://scenes/ai/decision/decision_budget.gd")

## The planner that walks the snapshot, driven by this job (`driven`): the controller reads its
## config, signals and debug state through here.
var planner: Object
## The perception that builds the snapshot (`begin_sense`) and holds the order.
var perception: Object
## What the last completed build held, for the observers (npc_cadence.gd).
var cadence: RefCounted
## What a build starts from: `{ goal, activity, engaged }` (the goal as written, the behaviour's
## activity line, the engaged contact's id).
var reads: Callable
## Whether the behaviour's last choice is still running, read at the claim.
var ongoing: Callable
## The confinement refreshed from this tick's rules (the reflexes'), as an order is refused.
var refresh: Callable
var _stage := Stage.IDLE
var _build: RefCounted
var _snapshot := {}
## The id of the order the build started with (-1: none): the refusal step judges that one.
var _order_seen := -1
## Whether the behaviour's last choice was still running at the claim.
var _continuing := false
## The entry node the decision starts from, worked out at the claim: what a build is compared with.
var _entry: StringName = &"root"


## Wire the job to the perception, the planner and the cadence its controller holds (the three
## `Callable`s above are set by the controller too). The planner is driven from here on.
func setup(perception_: Object, planner_: Object, cadence_: RefCounted) -> void:
	perception = perception_
	planner = planner_
	cadence = cadence_
	planner.driven = true
	planner.piece_ready.connect(_on_piece_ready)


## Whether a decision is in flight: claimed, building or walking (the planner's walk may have ended
## on its own, a failed transport).
func pending() -> bool:
	if _stage == Stage.WALK:
		return planner.is_pending()
	return _stage != Stage.IDLE


## Whether the walk is under way (its snapshot built and handed to the planner).
func walking() -> bool:
	return _stage == Stage.WALK and planner.is_pending()


## Whether the build's START has run and its walk has not begun: what it knows is frozen, and a
## forced decision since has not been weighed in it.
func frozen() -> bool:
	return _stage == Stage.BUILD or _stage == Stage.REFUSAL


## Whether the job in flight no longer fits a situation that starts at node `entry`: a walk that
## started from another node, or a build whose claim-time facts started from another.
func stale(entry: StringName) -> bool:
	if walking():
		return planner.current_entry() != entry
	return pending() and _entry != entry


## Ask to begin a decision: claims its first piece, the build's start, from the frame's pool.
## Claimed, any job in flight is dropped and a new one begins (its first piece runs on the next
## `advance`); the caller then books the decision. Refused (the pool is spent), nothing changes:
## the job in flight carries on and the wish stands for the caller to ask again next frame. A
## cadence wish (`forced` false) never claims over a job in flight.
func request(forced: bool) -> bool:
	if pending() and not forced:
		return false
	if not Budget.take(Budget.cost_start):
		return false
	cancel()
	_stage = Stage.CLAIMED
	return true


## Drop the job in flight, its build and its walk, with no signal.
func cancel() -> void:
	planner.cancel()
	_build = null
	_snapshot = {}
	_stage = Stage.IDLE


## Run the job in flight's pieces for as long as the frame's pool allows: the build's start, its
## hostiles and its finish, the order-refusal step, then the walk's levels that Von has answered.
func advance() -> void:
	while true:
		match _stage:
			Stage.CLAIMED:
				var read: Dictionary = reads.call()
				_build = perception.begin_sense(read["goal"], read["activity"], read["engaged"])
				_order_seen = int(perception.orders.current().get("id", -1))
				_continuing = bool(ongoing.call())
				_entry = planner.entry_for(perception.quick_facts())
				_build.step()  # the start, paid for by the claim
				_stage = Stage.BUILD
			Stage.BUILD:
				if not Budget.take(_cost_of(_build.next_piece())):
					return
				_build.step()
				if _build.done():
					_complete_build()
			Stage.REFUSAL:
				if not Budget.take(Budget.cost_refusal):
					return
				_refuse_order()
				planner.begin(_snapshot, _continuing)
				_stage = Stage.WALK
			Stage.WALK:
				if not planner.is_pending():
					_stage = Stage.IDLE
					return
				if not planner.has_piece() or not Budget.take(Budget.cost_level):
					return
				planner.step()
			_:
				return


## Von answered a level: it runs at once when its price fits the pool, else on a later `advance`.
func _on_piece_ready() -> void:
	if _stage == Stage.WALK:
		advance()


## What a build's next piece costs.
func _cost_of(piece: int) -> int:
	match piece:
		SnapshotBuild.Piece.HOSTILE:
			return Budget.cost_hostile
		SnapshotBuild.Piece.FINISH:
			return Budget.cost_finish
	return Budget.cost_start


## The build is over: what it holds is the last decision's, for the observers.
func _complete_build() -> void:
	_snapshot = _build.result()
	_build = null
	cadence.last_facts = _snapshot["facts"]
	cadence.last_sections = _snapshot["sections"]
	cadence.last_demand = _snapshot["demand"]
	cadence.last_analysed = _snapshot["sections_per_target"].keys()
	_stage = Stage.REFUSAL


## The order-refusal step: an order it cannot carry out (a room or doorway it does not know) is said
## so and dropped, and the walk is the NPC's own: its confinement holds no order's rules from this
## tick on, and in the snapshot the walk decides over.
func _refuse_order() -> void:
	var held: Dictionary = perception.orders.current()
	if (held.is_empty()
			or int(held["id"]) != _order_seen
			or not (_snapshot["options"]["order"]["options"] as Array).is_empty()):
		return
	perception.orders.end(held["id"], "refused")
	cadence.last_facts["ordered"] = false
	_snapshot["confinement"] = refresh.call().copy()
