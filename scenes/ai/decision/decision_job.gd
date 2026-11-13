extends RefCounted
## AI DECISION sub-domain: ONE decision as a job the controller drives with `request(forced)` and a
## per-frame `advance()`. It owns the claim (the budget's pool, `decision_budget.gd`), the retry
## (a refused claim changes nothing, so the controller's wish stands and is asked again next
## frame), the snapshot build in its pieces (`AgentPerception.begin_sense`), the order-refusal step,
## the throw piece (the `grenade_ready` search, in steps) and the planner's walk, one piece per
## level. Every piece is priced in `DecisionBudget` and runs
## only when the frame's pool allows, so a decision of a few units lands over two to four frames
## (and runs whole in its claim frame when its pieces are priced at nothing).
##
## A claim made while a job is in flight (half-built, or walking) drops that job without a signal
## and starts the new one; refused, the job in flight carries on. A dropped build is freed, never
## resumed (`snapshot-staged.md`). What the last decision knew (`last_facts`, `last_sections`,
## `last_demand`, `last_analysed`, on the cadence) changes only when a build completes.
##
## What is read when. At the claim (the build's first `advance`, the claim frame's): the goal, the
## activity, the engaged contact (`reads`), the order held and the entry the decision starts from
## (the planner's entry rule over the perception's quick facts). The build's START freezes the
## knowledge and the confinement copy (`perception.md`). After the build, at the order-refusal step:
## the live confinement refreshed (`refresh`) when the order the build saw is refused, replacing the
## snapshot's copy before the first level. As the walk begins, after the throw piece, the last
## things before the first level: the radio callouts again (`reread_claims`, so a claim radioed
## while the build and the throw search spread over frames is seen), then whether the behaviour's
## last choice is still running (`ongoing`, judged for "(your current plan)" on that state).
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
## order-refusal step, searching for a throw (the `grenade_ready` fact), or walking.
enum Stage {
	IDLE,
	CLAIMED,
	BUILD,
	REFUSAL,
	THROW,
	WALK,
}
## Whether `advance` is not running, running, or running with another round asked for.
enum Run {
	IDLE,
	BUSY,
	AGAIN,
}

## The snapshot build's piece kinds (`SnapshotBuild.Piece`), to price them.
const SnapshotBuild := preload("res://scenes/ai/perception/snapshot/snapshot_build.gd")
const Budget := preload("res://scenes/ai/decision/decision_budget.gd")
const Roster := preload("res://scenes/ai/decision/decision_roster.gd")
## The throw search's step kinds (`ThrowSearch.Kind`), to price them.
const ThrowSearch := preload("res://scenes/ai/perception/snapshot/throw_search.gd")

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
var _search: RefCounted
## The kind of the throw search's next step as the search last said it (`ThrowSearch.Kind`, -1
## before it has): asking prepares the step, so the job asks once and prices from this.
var _throw_kind := -1
## The doorway views' walked-route memo, held while the job's pieces run together in a frame
## (`hold_walks`), never kept between frames, nor into the walk.
var _walks: RefCounted
var _snapshot := {}
## The id of the order the build started with (-1: none): the refusal step judges that one.
var _order_seen := -1
## Whether `advance` is running (`Run`): a synchronous answer from Von must not run it again inside
## itself, but asks for another round once this one ends.
var _run_state := Run.IDLE
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
	return _stage == Stage.BUILD or _stage == Stage.REFUSAL or _stage == Stage.THROW


## Whether the job in flight no longer fits a situation that starts at node `entry`: a walk that
## started from another node, or a build whose claim-time facts started from another.
func stale(entry: StringName) -> bool:
	if walking():
		return planner.current_entry() != entry
	return pending() and _entry != entry


## Whether an order taken since (`cadence.order_from`, the decisions booked when it came) overtakes
## the job in flight: one begun before it, which was made without it. A job begun after the order
## already weighs it, and an event does not restart it for the order's sake again.
func overtaken_by_order() -> bool:
	return pending() and cadence.order_from >= 0 and cadence.decisions <= cadence.order_from


## Ask to begin a decision: claims its first piece, the build's start, from the frame's pool, at
## most one decision beginning in a physics frame whatever the pool holds, and behind the jobs in
## flight (`decision_roster.gd`). Claimed, any job in flight is dropped and a new one begins (its
## first piece runs on the next `advance`); the caller then books the decision. Refused (the pool
## is spent, or a decision already began this frame), nothing changes: the job in flight carries on
## and the wish stands for the caller to ask again next frame. A cadence wish (`forced` false)
## never claims over a job in flight.
func request(forced: bool) -> bool:
	if pending() and not forced:
		return false
	if (not Roster.may_start()
			or not Budget.take(Budget.cost_start, Roster.owed(get_instance_id(), true))):
		return false
	cancel()
	Roster.began(get_instance_id())
	_stage = Stage.CLAIMED
	return true


## Drop the job in flight, its build and its walk, with no signal.
func cancel() -> void:
	planner.cancel()
	_build = null
	_search = null
	_throw_kind = -1
	_walks = null
	_snapshot = {}
	_stage = Stage.IDLE
	Roster.leave(get_instance_id())


## The job's NPC does not think this frame (a service interaction holds its tick): no piece of its
## will run, so it owes the pool nothing now. `advance` notes its cost again on the next frame it
## runs.
func rest() -> void:
	if _stage != Stage.IDLE:
		Roster.note(get_instance_id(), 0)


## The job's NPC is gone (dead, or leaving the tree): it leaves the pool's roster without being
## dropped, so what it needed next holds no one up.
func release() -> void:
	Roster.leave(get_instance_id())


## Run the job in flight's pieces for as long as the frame's pool allows: the build's start, its
## hostiles and its finish, the order-refusal step, the throw search, then the walk's levels that
## Von has answered. Never run inside itself: a transport that answers at once asks for another
## round when this one ends.
func advance() -> void:
	if _run_state != Run.IDLE:
		_run_state = Run.AGAIN
		return
	_run_state = Run.AGAIN
	while _run_state == Run.AGAIN:
		_run_state = Run.BUSY
		_run()
	_run_state = Run.IDLE
	_walks = null
	if _stage == Stage.IDLE:
		Roster.leave(get_instance_id())
	else:
		Roster.note(get_instance_id(), _next_cost())


## One round of pieces: each stage's piece in turn, until one has to wait for the pool, for Von or
## the job is over.
func _run() -> void:
	var go := true
	while go:
		if _stage == Stage.WALK or _stage == Stage.IDLE:
			_walks = null
		elif _walks == null:
			_walks = perception.hold_walks()
		match _stage:
			Stage.CLAIMED:
				go = _start()
			Stage.BUILD:
				go = _build_piece()
			Stage.REFUSAL:
				go = _refusal()
			Stage.THROW:
				go = _throw_piece()
			Stage.WALK:
				go = _walk_piece()
			_:
				go = false


## The build's start, paid for by the claim.
func _start() -> bool:
	var read: Dictionary = reads.call()
	_build = perception.begin_sense(read["goal"], read["activity"], read["engaged"])
	_order_seen = int(perception.orders.current().get("id", -1))
	_entry = planner.entry_for(perception.quick_facts())
	_build.step()
	_stage = Stage.BUILD
	return true


## The build's next piece, when the pool allows.
func _build_piece() -> bool:
	if not _take(_build_cost()):
		return false
	_build.step()
	if _build.done():
		_complete_build()
	return true


## The order-refusal step, when the pool allows; the throw search is made ready after it.
func _refusal() -> bool:
	if not _take(Budget.cost_refusal):
		return false
	_refuse_order()
	_search = _snapshot["demand"].throw_search(Budget.throw_block)
	_throw_kind = -1
	_stage = Stage.THROW
	return true


## The throw search's steps, when the pool allows; the walk begins as it ends. What the walk is
## told is read as it begins, not at the claim, the build and the search having spread over frames:
## the radio callouts (a teammate's claim since is seen) and what it marks "(your current plan)".
func _throw_piece() -> bool:
	if not _throw_step():
		return false
	_search = null
	perception.reread_claims(_snapshot)
	planner.begin(_snapshot, bool(ongoing.call()))
	_stage = Stage.WALK
	return true


## The walk's next level, when Von has answered and the pool allows.
func _walk_piece() -> bool:
	if not planner.is_pending():
		_stage = Stage.IDLE
		return false
	if not planner.has_piece() or not _take(Budget.cost_level):
		return false
	planner.step()
	return true


## Spend `cost` units of the pool, behind the jobs older than this one that have not had their
## turn in this frame.
func _take(cost: int) -> bool:
	return Budget.take(cost, Roster.owed(get_instance_id()))


## What the build's next piece costs; a kind with no price is an error, then run as free.
func _build_cost() -> int:
	var cost := cost_of(_build.next_piece())
	if cost < 0:
		push_error("DecisionJob: a build piece of kind %d has no price" % _build.next_piece())
		return 0
	return cost


## The throw search's steps, as many as the pool allows: whether the search is over.
func _throw_step() -> bool:
	while _search != null:
		var kind: int = _search.next_kind()
		_throw_kind = kind
		if kind == ThrowSearch.Kind.DONE:
			return true
		var cost := throw_cost_of(kind)
		if cost < 0:
			push_error("DecisionJob: a throw search step of kind %d has no price" % kind)
			cost = 0
		if not _take(cost):
			return false
		_search.step()
	return true


## Von answered a level: it runs at once when its price fits the pool, else on a later `advance`.
func _on_piece_ready() -> void:
	if _stage == Stage.WALK:
		advance()


## What a build's piece of `kind` (`SnapshotBuild.Piece`) costs, or -1 for a kind with no price:
## every kind is priced explicitly, so a piece added without a price is found at once and not run
## as if it cost a start.
func cost_of(kind: int) -> int:
	match kind:
		SnapshotBuild.Piece.START:
			return Budget.cost_start
		SnapshotBuild.Piece.HOSTILE:
			return Budget.cost_hostile
		SnapshotBuild.Piece.FINISH:
			return Budget.cost_finish
	return -1


## What a throw search step of `kind` (`ThrowSearch.Kind`) costs, or -1 for an unknown kind.
func throw_cost_of(kind: int) -> int:
	match kind:
		ThrowSearch.Kind.BLOCK:
			return Budget.cost_throw_block
		ThrowSearch.Kind.RANK:
			return Budget.cost_throw_rank
		ThrowSearch.Kind.ROUTE:
			return Budget.cost_throw_route
	return -1


## What the piece the job runs next costs: what it asks the pool to leave for it (0: nothing to
## run, as a walk that waits for Von).
func _next_cost() -> int:
	match _stage:
		Stage.BUILD:
			return maxi(0, cost_of(_build.next_piece()))
		Stage.REFUSAL:
			return Budget.cost_refusal
		Stage.THROW:
			return _throw_next_cost()
		Stage.WALK:
			return Budget.cost_level if planner.has_piece() else 0
	return 0


## What the throw search's next step costs, from the kind it last said (`_throw_kind`): the search
## is not asked again outside the pool's budget.
func _throw_next_cost() -> int:
	if _search == null or _throw_kind == ThrowSearch.Kind.DONE or _throw_kind < 0:
		return 0
	return maxi(0, throw_cost_of(_throw_kind))


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
