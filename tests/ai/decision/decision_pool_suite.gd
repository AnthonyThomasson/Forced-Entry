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


## The pool a frame's decision work is held to (#194): three units, and no decision with a hostile
## (a start, the hostile's two pieces, a finish) fits one frame, so the first frames of a fight
## spread their builds instead of holding one lump; no piece but a lob is dearer than two units.
func test_the_shipped_pool_never_lets_one_frame_run_a_whole_decision() -> void:
	var whole: int = _shipped["cost_start"] + 2 * _shipped["cost_hostile"] + _shipped["cost_finish"]
	assert_int(_shipped["per_frame"]).is_equal(3)
	assert_bool(whole > _shipped["per_frame"]).is_true()
	assert_bool(_shipped["cost_hostile"] <= 1 and _shipped["cost_ambush"] <= 1).is_true()
	assert_bool(ThrowSpots.block_work <= 16).is_true()


func test_at_most_one_decision_starts_in_a_frame_whatever_the_pool_holds() -> void:
	DecisionBudget.per_frame = 10
	var other := _new_job()
	assert_bool(_job.request(false)).is_true()
	assert_bool(other.request(false)).is_false()  # the pool has room, the frame's start is gone
	_frame += 1
	assert_bool(other.request(false)).is_true()


func test_the_pool_is_served_oldest_claim_first_whatever_the_tree_order() -> void:
	DecisionBudget.per_frame = 3
	DecisionBudget.cost_hostile = 2
	DecisionBudget.cost_finish = 2
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


func test_a_job_that_never_runs_again_holds_no_one_up_once_released() -> void:
	DecisionBudget.per_frame = 1
	DecisionBudget.cost_hostile = 1
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
	DecisionBudget.cost_hostile = 1
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
	DecisionBudget.cost_hostile = 2
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
