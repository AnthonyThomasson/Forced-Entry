extends UnitSuite
## Native unit suite (pure logic): the decision job's throw piece and the memo it holds (#195),
## stepped by `DecisionBudget.frame_source` with no engine frames (`decision_job_suite` holds the
## rest of the job). A fake build is its own demand and hands the job a throw search of scripted
## steps; the job runs one step per priced unit between the order-refusal step and the walk, the
## callouts read again at the refusal step, and the walked-route memo held only while the pieces
## run together in a frame.

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


func test_the_throw_search_is_a_piece_between_the_refusal_and_the_walk() -> void:
	DecisionBudget.cost_refusal = 1
	DecisionBudget.cost_throw_block = 1
	DecisionBudget.cost_throw_rank = 1
	DecisionBudget.cost_throw_route = 1
	var search := Builds.FakeSearch.new()
	search.kinds = [0, 0, 1, 2]  # two blocks of candidates, the rank pass, a route
	_perception.search = search
	assert_bool(_job.request(false)).is_true()
	_job.advance()
	assert_int(_perception.rereads).is_equal(0)  # the refusal step has not run
	_frame += 1
	_job.advance()
	assert_int(_perception.rereads).is_equal(1)  # the callouts are read again at the refusal step
	assert_int(search.steps).is_equal(0)
	assert_bool(_job.frozen()).is_true()  # what it knows is still the build's
	for expected in [1, 2, 3]:
		_frame += 1
		_job.advance()
		assert_int(search.steps).is_equal(expected)
		assert_int(_planner.begun).is_equal(0)  # the walk waits for the search
	_frame += 1
	_job.advance()
	assert_int(search.steps).is_equal(4)
	assert_int(_planner.begun).is_equal(1)  # the walk began as the search ended
	assert_bool(_job.frozen()).is_false()


func test_a_throw_search_costing_nothing_runs_whole_before_the_walk_in_the_claim_frame() -> void:
	var search := Builds.FakeSearch.new()
	search.kinds = [0, 0, 0, 1, 2]
	_perception.search = search
	assert_bool(_job.request(false)).is_true()
	_job.advance()
	assert_int(search.steps).is_equal(5)
	assert_int(_planner.begun).is_equal(1)


func test_the_walked_route_memo_is_held_only_while_pieces_run_together() -> void:
	DecisionBudget.cost_hostile = 1
	assert_bool(_job.request(false)).is_true()
	_job.advance()  # the start, and a build left half-built for a frame
	assert_object(_job.get("_walks")).is_null()  # nothing kept to the next frame
	assert_int(_perception.memos_held).is_equal(1)
	for i in 3:
		_frame += 1
		_job.advance()
	assert_int(_planner.begun).is_equal(1)  # premise: the walk has begun
	assert_object(_job.get("_walks")).is_null()
	assert_int(_perception.memos_held).is_equal(3)  # a frame the build ran in, not the walk
