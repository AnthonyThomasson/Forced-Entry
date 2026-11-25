extends UnitSuite
## Native unit suite (pure logic): the pool the decision jobs share (`DecisionBudget`,
## `decision_roster.gd`), stepped by `DecisionBudget.frame_source` with no engine frames
## (`decision_job_suite` holds the job): at most one decision begins in a frame whatever the pool
## holds, and the pool is served oldest claim first, whatever order the NPCs take their turns in:
## a job in flight before any new start, and a job never overtaken by a younger one ahead of it.

const Job := preload("res://scenes/ai/decision/decision_job.gd")
const Cadence := preload("res://scenes/ai/npc_cadence.gd")
const Fakes := preload("res://tests/_ai/job_fakes.gd")
const Builds := preload("res://tests/_ai/job_build_fakes.gd")
const ThrowSpots := preload("res://scenes/ai/perception/throw_spots.gd")
const EntryPosts := preload("res://scenes/ai/perception/entry/entry_posts.gd")
## The build pieces' prices (`Fakes.PIECE_PRICES`).
const PIECE_PRICES := Fakes.PIECE_PRICES
## The kinds of the pieces of one hostile's analysis (`SnapshotBuild.Piece`): the rings, the spots,
## a flank for each of two sides, the rest. The retreat spots (kind 8) run after them, before the
## finish, whenever a hostile is known (the fake build does the same).
const ANALYSIS := [1, 5, 6, 6, 7]

## The base of the frame the last test started on; each test starts on a frame of its own. An
## instance var, not a `static var`: one in a suite script crashes the 4.4.1 Windows engine at exit
## (tools/tests/test_suites_no_static_var.py).
var _next_base := 9000
## The frame the test is on.
var _frame := 0
var _perception: Fakes.FakePerception
var _planner: Fakes.FakePlanner
var _cadence: Cadence
var _job: RefCounted
## The game's pool and prices, put back after each test.
var _shipped := {}


func before_test() -> void:
	_shipped = Fakes.prices()
	Fakes.whole_prices()
	_next_base += 1000
	_frame = _next_base
	DecisionBudget.frame_source = func() -> int: return _frame
	DecisionBudget.reset()
	_perception = Fakes.FakePerception.new()
	_planner = Fakes.FakePlanner.new()
	_cadence = Cadence.new()
	_job = Job.new()
	_job.setup(_perception, _planner, _cadence)
	_job.reads = func() -> Dictionary: return { "goal": "goal", "activity": "", "engaged": 0 }
	_job.ongoing = func() -> bool: return false
	_job.refresh = func() -> Builds.FakeConfinement: return _perception.confinement


func after_test() -> void:
	DecisionBudget.frame_source = Callable()
	DecisionBudget.reset()
	Fakes.set_prices(_shipped)


## A job with a fake perception, planner and cadence of its own, on the same pool.
func _new_job() -> RefCounted:
	var job: RefCounted = Job.new()
	job.setup(Fakes.FakePerception.new(), Fakes.FakePlanner.new(), Cadence.new())
	job.reads = func() -> Dictionary: return { "goal": "goal", "activity": "", "engaged": 0 }
	job.ongoing = func() -> bool: return false
	job.refresh = func() -> Builds.FakeConfinement: return _perception.confinement
	return job


## The pool a frame's decision work is held to (#194 pool6): six units, about three milliseconds,
## and no decision with a hostile (a start, the hostile's five pieces, the retreat spots, a finish)
## fits one frame, so the first frames of a fight spread their builds instead of holding one lump;
## no piece is dearer than the pool less the start's unit, so a start and the dearest piece fit one
## frame.
func test_the_shipped_pool_never_lets_one_frame_run_a_whole_decision() -> void:
	var analysis: int = (
		_shipped["cost_hostile"] + _shipped["cost_spots"] + 2 * _shipped["cost_flanks"]
		+ _shipped["cost_rest"]
	)
	var whole: int = (
		_shipped["cost_start"] + analysis + _shipped["cost_retreat"] + _shipped["cost_finish"]
	)
	assert_int(_shipped["per_frame"]).is_equal(6)
	assert_bool(whole > _shipped["per_frame"]).is_true()
	for price in PIECE_PRICES:
		assert_bool(_shipped[price] <= _shipped["per_frame"] - _shipped["cost_start"]).is_true()
	assert_bool(ThrowSpots.block_work <= 96).is_true()


## What a throw search worked is a difference of the planner's and the scan's own counts, so it is
## the same whatever the process counted before it (#194 replfix): `tested` is a total that runs
## on through every play and test of a process, and the search's block ends at a work cap, so a
## floor of that total (a quarter of it, as an integer) made a block's end follow the total's
## residue: the same match, one play later or one frame off, cut its blocks elsewhere and decided
## on other frames (`perf/match_npc_vision_replay`).
func test_the_throw_works_difference_does_not_follow_what_the_process_counted_before() -> void:
	var kept_tested := ThrowSpots.tested
	var worked := []
	for counted in 8:
		ThrowSpots.tested = counted
		var started := ThrowSpots.work()
		ThrowSpots.tested += 6
		worked.append(ThrowSpots.work() - started)
	ThrowSpots.tested = kept_tested
	for one: int in worked:
		assert_int(one).is_equal(worked[0])


## One block of the throw search ends where its work says (#194 replfix, the case the difference
## test above stands for, run through `scan_step`): a raw candidate is a quarter-unit and the
## planner's question four (the lob test, stubbed here to ask once and refuse), so the block cut at
## 80 quarters ends after 16 candidates and has charged exactly 80, whatever `tested` and the
## planner's total stood at when it began. The first scan starts them at a residue of one, the
## second at another; a block cut on a floor of the running totals would end elsewhere in one of
## them.
func test_a_throw_block_ends_at_the_same_candidate_whatever_the_process_counted_before() -> void:
	var kept_tested := ThrowSpots.tested
	var kept_asked := GrenadeArc.work
	assert_int(ThrowSpots.block_work).is_equal(80)
	var ends := []
	var charges := []
	for residue: Array in [[0, 0], [3, 2]]:
		ThrowSpots.tested = 1000 + residue[0]
		GrenadeArc.work = 5000 + residue[1]
		var spots := ThrowSpots.new()
		spots.spot_walk = 1000.0
		var aim := ThrowAim.new()
		aim.spot = Vector2.ZERO
		aim.reach = 1000.0
		aim.lob = func(_from: Vector2) -> bool:
			GrenadeArc.work += 1
			return false
		var tactics := StubTactics.new()
		var ctx := { "self_pos": Vector2.ZERO }
		var scan: RefCounted = ThrowSpots.ThrowScan.new(tactics, ctx, aim, [])
		var started := ThrowSpots.work()
		spots.scan_step(tactics, scan, 48)
		ends.append(scan.cursor)
		charges.append(ThrowSpots.work() - started)
	ThrowSpots.tested = kept_tested
	GrenadeArc.work = kept_asked
	for i in 2:
		assert_int(ends[i]).is_equal(16)
		assert_int(charges[i]).is_equal(80)


## The frames a decision's build takes to land at the shipped prices (the planner begins its walk),
## counted from the frame it is claimed (frame 1): the cadence the docs' frame counts rest on
## (`decision-prices.md`). Each hostile is a run of pieces (`ANALYSIS`), an ambush's ranking
## `chunks` more.
func _frames_to_land(hostiles: int, chunks := 0) -> int:
	Fakes.set_prices(_shipped)
	_perception.hostiles = hostiles
	_perception.run = ANALYSIS
	_perception.ambush = chunks
	assert_bool(_job.request(false)).is_true()
	var frames := 1
	_job.advance()
	while _planner.begun == 0 and frames < 100:
		_frame += 1
		frames += 1
		_job.advance()
	return frames


func test_one_hostile_lands_its_build_in_three_frames() -> void:
	# start, rings, spots (6) | flank, flank, rest (4: the retreat's 3 does not fit) | retreat,
	# finish (4)
	assert_int(_frames_to_land(1)).is_equal(3)


func test_two_hostiles_land_their_build_in_four_frames() -> void:
	# start, rings, spots | flank, flank, rest, rings | spots, flank, flank | rest, retreat, finish:
	# a piece that does not fit what is left of a frame waits for the next
	assert_int(_frames_to_land(2)).is_equal(4)


func test_an_ambush_build_lands_in_the_frames_its_chunks_price() -> void:
	var offsets: int = (
		EntryPosts.AMBUSH_DEPTHS.size() * EntryPosts.AMBUSH_LATERALS.size() * 2
	)
	var chunks: int = int(offsets / float(EntryPosts.AMBUSH_CHUNK))
	assert_int(chunks).is_equal(20)  # premise: 80 offsets, 4 a piece
	# A hostile's analysis (9 units after the start's), the 20 chunks, the retreat spots (3) and the
	# finish: 34 units, six a frame: start, rings, spots | flank, flank, rest, 2 chunks | 6 chunks
	# a frame for three frames | retreat, finish (the 20th chunk fills the fifth frame).
	assert_int(_frames_to_land(1, chunks)).is_equal(6)


func test_at_most_one_decision_starts_in_a_frame_whatever_the_pool_holds() -> void:
	DecisionBudget.per_frame = 10
	var other := _new_job()
	assert_bool(_job.request(false)).is_true()
	assert_bool(other.request(false)).is_false()  # the pool has room, the frame's start is gone
	_frame += 1
	assert_bool(other.request(false)).is_true()


func test_the_pool_is_served_oldest_claim_first_whatever_the_tree_order() -> void:
	DecisionBudget.per_frame = 3
	DecisionPrices.cost_hostile = 2
	DecisionPrices.cost_finish = 2
	_perception.hostiles = 1
	assert_bool(_job.request(false)).is_true()  # the oldest: start, hostile, finish
	_job.advance()
	var oldest: Builds.FakeBuild = _perception.builds[0]
	assert_int(oldest.piece).is_equal(2)  # premise: its start and hostile ran, the finish waits
	_frame += 1
	# A new start is first in the tree and the pool has room for its unit, but the oldest job still
	# needs 2 of the 3 this frame: the start fits behind them (a job in flight comes first).
	var younger := _new_job()
	younger.perception.hostiles = 1
	assert_bool(younger.request(false)).is_true()
	younger.advance()  # its turn comes first: the older job's finish is not given away
	var young: Builds.FakeBuild = younger.perception.builds[0]
	assert_int(young.piece).is_equal(1)  # its hostile waits, whoever is first in the tree
	_job.advance()
	assert_int(_planner.begun).is_equal(1)  # the oldest ran its finish: never overtaken
	_frame += 1
	younger.advance()
	assert_int(young.piece).is_equal(2)  # then the younger one's hostile
	# A start waits while an older job needs the pool: nobody starves behind new claims.
	DecisionBudget.per_frame = 2
	var newest := _new_job()
	_frame += 1
	assert_bool(newest.request(false)).is_false()  # the younger's finish needs the 2 units
	younger.advance()
	assert_int(young.piece).is_equal(3)  # and the finish ran
	_frame += 1
	assert_bool(newest.request(false)).is_true()


## The order the pool serves forced decisions in (`DecisionRoster.rank_of`): attacked and a new
## hostile first, then an order, a task resolved, following, a way blocked, and any other reason
## (a cadence decision last).
func test_the_reasons_rank_attacked_and_new_hostile_first() -> void:
	var rank := DecisionBudget.Roster.rank_of
	assert_int(rank.call("attacked")).is_equal(rank.call("hostile belief changed"))
	# The engaged one lost is a change of the hostile belief too; "sight returned" is the NPC's own
	# blindness ending: rank 0 because an NPC just unblinded must decide again at once.
	assert_int(rank.call("sight returned")).is_equal(rank.call("hostile belief changed"))
	assert_int(rank.call("lost the engaged contact")).is_equal(rank.call("hostile belief changed"))
	var order := ["attacked", "ordered", "task resolved", "follows its leader", "way blocked"]
	for i in range(1, order.size()):
		assert_bool(rank.call(order[i - 1]) < rank.call(order[i])).is_true()
	assert_bool(rank.call("way blocked") < rank.call("off the leash")).is_true()
	assert_int(rank.call("cadence")).is_equal(rank.call("off the leash"))


## An urgent claim is served before an older routine job: the older one's next piece no longer
## holds back what the younger one's needs, so under fire a decision does not queue behind the
## routine ones begun before it.
func test_an_urgent_claim_is_served_before_an_older_routine_one() -> void:
	DecisionBudget.per_frame = 3
	DecisionPrices.cost_hostile = 2
	DecisionPrices.cost_finish = 2
	_perception.hostiles = 1
	assert_bool(_job.request(true, "way blocked")).is_true()
	_job.advance()  # its start and hostile ran; its finish (2) waits for a fresh frame
	var routine: Builds.FakeBuild = _perception.builds[0]
	assert_int(routine.piece).is_equal(2)  # premise
	_frame += 1
	var urgent := _new_job()
	urgent.perception.hostiles = 1
	assert_bool(urgent.request(true, "attacked")).is_true()
	urgent.advance()
	var hurried: Builds.FakeBuild = urgent.perception.builds[0]
	assert_int(hurried.piece).is_equal(2)  # its hostile ran, on the pool the older finish needed
	_job.advance()
	assert_int(_planner.begun).is_equal(0)  # the older job waits behind it
	# It lands first; the older job is served once it is out of the way.
	_frame += 1
	urgent.advance()
	assert_int(urgent.planner.begun).is_equal(1)
	_job.advance()
	assert_int(_planner.begun).is_equal(0)  # the pool is spent on the urgent one's finish
	_frame += 1
	_job.advance()
	assert_int(_planner.begun).is_equal(1)


## A job's rank ages, in frames (`DecisionRoster.AGE_FRAMES`): a routine job (rank 5) stands behind
## a stream of attacked claims for five steps of 30 frames (150, `OTHER_RANK` x `AGE_FRAMES`), then
## it ranks with them and is older than every one of them, so it is served first and its own build
## (a few frames) follows: it lands after 150 frames and within 180.
func test_a_job_reaches_the_best_rank_after_five_ageing_steps_behind_better_ones() -> void:
	DecisionBudget.per_frame = 3
	DecisionPrices.cost_hostile = 2
	DecisionPrices.cost_finish = 2
	_perception.hostiles = 1
	assert_bool(_job.request(false)).is_true()  # a cadence decision: the worst rank
	var stream: Array = []
	var frames := 0
	while _planner.begun == 0 and frames < 400:
		var urgent := _new_job()
		urgent.perception.hostiles = 1
		urgent.request(true, "attacked")
		stream.append(urgent)
		stream = stream.filter(func(j): return j.planner.begun == 0)
		for job in stream:
			job.advance()  # first in the tree's order, every frame
		_job.advance()
		_frame += 1
		frames += 1
	assert_int(_planner.begun).is_equal(1)
	var ageing: int = DecisionBudget.Roster.OTHER_RANK * DecisionBudget.Roster.AGE_FRAMES
	assert_bool(frames > ageing).is_true()  # premise: it did wait out the ageing
	assert_bool(frames <= ageing + DecisionBudget.Roster.AGE_FRAMES).is_true()  # then its own build


## What a job owes the pool is judged at its aged rank: a worse-ranked job in flight owes nothing to
## a fresh better claim until it has waited, a rank better every 30 frames (a stand of 150 frames
## brings a cadence decision to the best rank).
func test_a_waiting_job_owes_the_pool_at_its_aged_rank() -> void:
	var roster := DecisionBudget.Roster
	var step: int = roster.AGE_FRAMES
	var routine := _new_job()
	var claimed := _frame
	assert_bool(routine.request(false)).is_true()  # rank 5 (cadence)
	var me := _new_job()
	var best: int = roster.rank_of("attacked")
	var owed := func(age: int, rank: int) -> int:
		_frame = claimed + age * step + 1
		roster.note(routine.get_instance_id(), 2)  # what it needs next
		_frame += 1  # and it has not had its turn in this frame
		return roster.owed(me.get_instance_id(), true, rank)
	assert_int(owed.call(0, best)).is_equal(0)  # rank 5: behind every better claim
	assert_int(owed.call(4, best)).is_equal(0)  # rank 1 after four steps: still behind the best
	assert_int(owed.call(4, 1)).is_equal(2)  # and ahead of a claim of its rank that is younger
	assert_int(owed.call(5, best)).is_equal(2)  # rank 0, older: ahead of every claim
	assert_int(owed.call(9, best)).is_equal(2)  # never better than the best


func test_a_job_that_never_runs_again_holds_no_one_up_once_released() -> void:
	DecisionBudget.per_frame = 1
	DecisionPrices.cost_hostile = 1
	_perception.hostiles = 1
	assert_bool(_job.request(false)).is_true()
	_job.advance()  # the start ran, its hostile piece waits for a frame: it needs a unit next
	var young := _new_job()
	_frame += 1
	# The oldest NPC died (or left): it never advances, and nothing says it is gone.
	assert_bool(young.request(false)).is_false()  # premise: it still owes the pool a unit
	_job.release()  # the controller's exit on death
	assert_bool(young.request(false)).is_true()


func test_a_job_whose_npc_does_not_think_owes_the_pool_nothing() -> void:
	DecisionBudget.per_frame = 1
	DecisionPrices.cost_hostile = 1
	_perception.hostiles = 1
	assert_bool(_job.request(false)).is_true()
	_job.advance()
	var young := _new_job()
	_frame += 1
	assert_bool(young.request(false)).is_false()  # premise: it owes a unit
	_job.rest()  # its NPC is in a service interaction this frame: no piece will run
	assert_bool(young.request(false)).is_true()


func test_a_job_the_pool_had_forgotten_takes_its_place_again_when_it_runs() -> void:
	DecisionBudget.per_frame = 2
	DecisionPrices.cost_hostile = 2
	_perception.hostiles = 2
	assert_bool(_job.request(false)).is_true()
	_job.advance()
	DecisionBudget.Roster.leave(_job.get_instance_id())  # forgotten: it was not served for a while
	_frame += 1
	_job.advance()  # its first hostile ran; the second waits for a frame: it needs 2 units
	var young := _new_job()
	_frame += 1
	assert_bool(young.request(false)).is_false()  # the job is in the pool again, and first


func test_a_step_that_did_more_work_than_its_price_is_charged_the_rest() -> void:
	DecisionBudget.per_frame = 4
	DecisionBudget.work_unit = 15
	assert_bool(DecisionBudget.take(1)).is_true()
	DecisionBudget.charge(60, 1)  # 60 of planner work is 4 units: 1 taken, 3 more owed
	assert_bool(DecisionBudget.take(1)).is_false()  # the pool is spent for this frame
	_frame += 1
	assert_bool(DecisionBudget.take(1)).is_true()
	DecisionBudget.charge(10, 1)  # under its price: nothing more
	assert_bool(DecisionBudget.take(1)).is_true()
	DecisionBudget.charge(500, 0)  # a free piece is never charged
	assert_bool(DecisionBudget.take(1)).is_true()


## A stand-in for the `AgentTactics` facade the cheap tests read: every candidate snaps to itself
## and is no nearer the NPC than a stride, so each reaches the lob test.
class StubTactics:
	extends RefCounted
	const SNAP_TOLERANCE := 4.0
	const STRIDE := 0.0

	func snap(_ctx: Dictionary, r: Vector2) -> Vector2:
		return r
