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

## The frame the test is on; each test starts on a frame of its own.
static var _next_base := 9000

var _frame := 0
var _perception: Fakes.FakePerception
var _planner: Fakes.FakePlanner
var _cadence: Cadence
var _job: RefCounted


func before_test() -> void:
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
	DecisionBudget.per_frame = 1
	DecisionBudget.cost_start = 1
	DecisionBudget.cost_hostile = 0
	DecisionBudget.cost_finish = 0
	DecisionBudget.cost_refusal = 0
	DecisionBudget.cost_level = 0
	DecisionBudget.cost_throw_block = 0
	DecisionBudget.cost_throw_rank = 0
	DecisionBudget.cost_throw_route = 0
	DecisionBudget.throw_block = 16


## A job with a fake perception, planner and cadence of its own, on the same pool.
func _new_job() -> RefCounted:
	var job: RefCounted = Job.new()
	job.setup(Fakes.FakePerception.new(), Fakes.FakePlanner.new(), Cadence.new())
	job.reads = func() -> Dictionary: return { "goal": "goal", "activity": "", "engaged": 0 }
	job.ongoing = func() -> bool: return false
	job.refresh = func() -> Builds.FakeConfinement: return _perception.confinement
	return job


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
