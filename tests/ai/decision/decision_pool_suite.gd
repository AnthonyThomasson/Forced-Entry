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


## The pool a frame's decision work is held to (#194): four units, about two milliseconds, and no
## decision with a hostile (a start, the hostile's five pieces, the retreat spots, a finish) fits
## one frame, so the first frames of a fight spread their builds instead of holding one lump; no
## piece is dearer than the pool less the start's unit, so a start and the dearest piece fit one
## frame.
func test_the_shipped_pool_never_lets_one_frame_run_a_whole_decision() -> void:
	var analysis: int = (
		_shipped["cost_hostile"] + _shipped["cost_spots"] + 2 * _shipped["cost_flanks"]
		+ _shipped["cost_rest"]
	)
	var whole: int = (
		_shipped["cost_start"] + analysis + _shipped["cost_retreat"] + _shipped["cost_finish"]
	)
	assert_int(_shipped["per_frame"]).is_equal(4)
	assert_bool(whole > _shipped["per_frame"]).is_true()
	for price in PIECE_PRICES:
		assert_bool(_shipped[price] <= _shipped["per_frame"] - _shipped["cost_start"]).is_true()
	assert_bool(ThrowSpots.block_work <= 24).is_true()


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


func test_one_hostile_lands_its_build_in_four_frames() -> void:
	# start, rings (3) | spots, flank (4) | flank, rest (3) | retreat, finish (4)
	assert_int(_frames_to_land(1)).is_equal(4)


func test_two_hostiles_land_their_build_in_seven_frames() -> void:
	# start, rings | spots, flank | flank, rest | rings | spots, flank | flank, rest | retreat,
	# finish: a piece that does not fit what is left of a frame waits for the next
	assert_int(_frames_to_land(2)).is_equal(7)


func test_an_ambush_build_lands_in_the_frames_its_chunks_price() -> void:
	var offsets: int = (
		EntryPosts.AMBUSH_DEPTHS.size() * EntryPosts.AMBUSH_LATERALS.size() * 2
	)
	var chunks: int = int(offsets / float(EntryPosts.AMBUSH_CHUNK))
	assert_int(chunks).is_equal(20)  # premise: 80 offsets, 4 a piece
	# A hostile's analysis (9 units after the start's), the 20 chunks, the retreat spots (3) and the
	# finish: 34 units, four a frame, but the retreat (3) does not fit what the last chunks leave,
	# so it and the finish take a frame of their own: start, rings | spots, flank | flank, rest,
	# a chunk | 4 chunks a frame for four frames | the last three | retreat, finish.
	assert_int(_frames_to_land(1, chunks)).is_equal(9)


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
	var order := ["attacked", "ordered", "task resolved", "follows its leader", "way blocked"]
	for i in range(1, order.size()):
		assert_bool(rank.call(order[i - 1]) < rank.call(order[i])).is_true()
	assert_bool(rank.call("way blocked") < rank.call("sight returned")).is_true()
	assert_int(rank.call("cadence")).is_equal(rank.call("sight returned"))


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
