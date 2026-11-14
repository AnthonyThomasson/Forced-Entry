extends RefCounted
## AI DECISION sub-domain: ONE decision as a job the controller drives with `request(forced)` and a
## per-frame `advance()`: the claim on the budget's pool (`decision_budget.gd`), the snapshot build,
## the order-refusal step, the group and throw pieces and the planner's walk, each piece priced in
## `DecisionBudget` and run only when the frame's pool allows. What is read when, the interrupt
## rules (`stale`, `frozen`) and the retry of a refused claim: `decision-job.md`.
##
## A data part, no owner (ADR 0006): it holds the perception, the planner and the cadence its
## controller hands it and three reads of the behaviour and reflexes as `Callable`s.

## Where the job is: claimed (its start still to run, paid for by the claim), building, taking its
## order-refusal step, building the groups the root reads (`GROUP`), searching for a throw (the
## `grenade_ready` fact), building the throws it found (`GRENADE`), or walking.
enum Stage {
	IDLE,
	CLAIMED,
	BUILD,
	REFUSAL,
	GROUP,
	THROW,
	GRENADE,
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
## The group builds' step kinds (`GroupBuild.Kind`), to price them.
const GroupBuild := preload("res://scenes/ai/perception/snapshot/group_build.gd")

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
## The steps in hand, in the group, throw or grenade stage: a `GroupSteps` or a `ThrowSearch`.
var _steps: RefCounted
## The kind of the steps' next one as they last said it (`GroupBuild.Kind` or `ThrowSearch.Kind`, -1
## before they have): asking prepares the step, so the job asks once and prices from this.
var _step_kind := -1
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
	return (_stage == Stage.BUILD or _stage == Stage.REFUSAL or _stage == Stage.GROUP
			or _stage == Stage.THROW or _stage == Stage.GRENADE)


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
	_steps = null
	_step_kind = -1
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
			Stage.GROUP:
				go = _group_piece()
			Stage.THROW:
				go = _throw_piece()
			Stage.GRENADE:
				go = _grenade_piece()
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


## The order-refusal step, when the pool allows; the groups the root reads are made ready after it
## (only for a decision that starts at the root: a fight or an order starts deeper and never reads
## them).
func _refusal() -> bool:
	if not _take(Budget.cost_refusal):
		return false
	_refuse_order()
	_steps = _snapshot["demand"].group_steps() if _entry == &"root" else null
	_step_kind = -1
	_stage = Stage.GROUP
	return true


## The group piece, when the pool allows: the leads (and the entries, while a stun can be thrown)
## the root reads whatever the situation, built a lead or a doorway a step so the planner finds them
## in the snapshot, not one frame's heavy lump. The throw search is made ready as it ends.
func _group_piece() -> bool:
	if not _run_steps(group_cost_of, GroupBuild.Kind.DONE):
		return false
	_steps = _snapshot["demand"].throw_search(Budget.throw_block)
	_step_kind = -1
	_stage = Stage.THROW
	return true


## The throw search's steps, when the pool allows; the throws it found are made ready as it ends.
func _throw_piece() -> bool:
	if not _run_steps(throw_cost_of, ThrowSearch.Kind.DONE):
		return false
	_steps = _snapshot["demand"].grenade_steps()
	_step_kind = -1
	_stage = Stage.GRENADE
	return true


## The grenade piece, when the pool allows: the throws at the hostile the search found one at, a
## kind a step; the walk begins as it ends. What the walk is told is read as it begins, not at the
## claim, the build and the pieces after it having spread over frames: the radio callouts (a
## teammate's claim since is seen) and what it marks "(your current plan)".
func _grenade_piece() -> bool:
	if not _run_steps(group_cost_of, GroupBuild.Kind.DONE):
		return false
	_steps = null
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


## What the build's next piece costs. A kind with no price is a loud error (`push_error` fails every
## test through the log gate; the suite pins that every kind is priced) and then runs as free, not
## never: a shipped build keeps deciding rather than freezing an NPC's brain on a piece the pool
## cannot price.
func _build_cost() -> int:
	var cost := cost_of(_build.next_piece())
	if cost < 0:
		push_error("DecisionJob: a build piece of kind %d has no price" % _build.next_piece())
		return 0
	return cost


## The steps in hand, as many as the pool allows, each priced by `prices` (a step's kind to its
## units, -1 for a kind with no price, a loud error run as free, as `_build_cost`): whether they
## are over (`done_kind` is the kind they say then).
func _run_steps(prices: Callable, done_kind: int) -> bool:
	while _steps != null:
		var kind: int = _steps.next_kind()
		_step_kind = kind
		if kind == done_kind:
			return true
		var cost: int = prices.call(kind)
		if cost < 0:
			push_error("DecisionJob: a step of kind %d has no price" % kind)
			cost = 0
		if not _take(cost):
			return false
		_steps.step()
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


## What a group build step of `kind` (`GroupBuild.Kind`) costs, or -1 for an unknown kind: a unit of
## work (a lead, a doorway, one kind of grenade) or the finish, which sorts and caps and costs
## nothing.
func group_cost_of(kind: int) -> int:
	match kind:
		GroupBuild.Kind.UNIT:
			return Budget.cost_group_unit
		GroupBuild.Kind.FINISH:
			return Budget.cost_group_finish
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
		Stage.GROUP, Stage.GRENADE:
			return _steps_next_cost(group_cost_of, GroupBuild.Kind.DONE)
		Stage.THROW:
			return _steps_next_cost(throw_cost_of, ThrowSearch.Kind.DONE)
		Stage.WALK:
			return Budget.cost_level if planner.has_piece() else 0
	return 0


## What the steps' next one costs, from the kind they last said (`_step_kind`): they are not asked
## again outside the pool's budget.
func _steps_next_cost(prices: Callable, done_kind: int) -> int:
	if _steps == null or _step_kind == done_kind or _step_kind < 0:
		return 0
	return maxi(0, prices.call(_step_kind))


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
