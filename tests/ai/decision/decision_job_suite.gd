extends UnitSuite
## Native unit suite (pure logic): the decision job (`decision_job.gd`, #208) stepped unit by unit
## with no engine frames. A fake perception makes the snapshot (START, one piece per hostile,
## FINISH) and a fake planner walks it level by level, each level waiting for a scripted answer;
## `DecisionBudget.frame_source` is the frame the test is on, and `_frame` moves it.
##
## A job that finishes; an interrupt that cancels a job half-built (the later pieces cost units, so
## the build is spread over frames) or walking; a refused claim that leaves the wish and the job in
## flight alone; a piece dearer than the pool, which runs alone on a fresh frame; an answered level
## that waits for a frame whose pool has room; and the snapshot frozen as built across all of it.

const Job := preload("res://scenes/ai/decision/decision_job.gd")
const Cadence := preload("res://scenes/ai/npc_cadence.gd")
const Fakes := preload("res://tests/_ai/job_fakes.gd")
const Builds := preload("res://tests/_ai/job_build_fakes.gd")

## The frame the test is on; each test starts on a frame of its own.
static var _next_base := 5000

var _frame := 0
var _perception: Fakes.FakePerception
var _planner: Fakes.FakePlanner
var _cadence: Cadence
var _job: RefCounted
var _decided := 0
var _failed := 0
## What the behaviour says of its last choice still running.
var _running := false
## The game's pool and prices, put back after each test.
var _shipped := {}


func before_test() -> void:
	_next_base += 1000
	_frame = _next_base
	DecisionBudget.frame_source = func() -> int: return _frame
	DecisionBudget.reset()
	_shipped = Fakes.prices()
	Fakes.whole_prices()
	_perception = Fakes.FakePerception.new()
	_planner = Fakes.FakePlanner.new()
	_cadence = Cadence.new()
	_decided = 0
	_failed = 0
	_running = false
	_planner.decided.connect(func(_leaf: Dictionary) -> void: _decided += 1)
	_planner.failed.connect(func() -> void: _failed += 1)
	_job = Job.new()
	_job.setup(_perception, _planner, _cadence)
	_job.reads = _reads
	_job.ongoing = _is_running
	_job.refresh = _refreshed


func after_test() -> void:
	DecisionBudget.frame_source = Callable()
	DecisionBudget.reset()
	Fakes.set_prices(_shipped)


func _reads() -> Dictionary:
	return { "goal": "goal", "activity": "", "engaged": 0 }


## What the reflexes' refresh gives: the live confinement as the NPC's own now.
func _refreshed() -> Builds.FakeConfinement:
	return _perception.confinement


## Another NPC spends `units` of this frame's pool.
func _someone_else_spends(units: int) -> bool:
	return DecisionBudget.take(units)


func test_a_job_builds_walks_and_decides_in_the_frame_it_was_claimed() -> void:
	assert_bool(_job.pending()).is_false()
	assert_bool(_job.request(false)).is_true()
	assert_int(_cadence.last_facts.size()).is_equal(0)  # premise: nothing built yet
	_job.advance()
	# Whole prices: the build ran whole in the claim frame and the walk is asking Von.
	assert_dict(_cadence.last_facts).is_equal({ "build": 1 })
	assert_int(_planner.begun).is_equal(1)
	assert_bool(_job.pending()).is_true()
	assert_int(_decided).is_equal(0)
	_planner.answer()  # Von answers a few frames on: the last level runs as it lands
	assert_int(_decided).is_equal(1)
	assert_bool(_job.pending()).is_false()
	assert_int(_planner.cancelled).is_equal(0)


func test_the_pool_is_shared_so_a_second_claim_waits_for_the_next_frame() -> void:
	assert_bool(_job.request(false)).is_true()
	var other: RefCounted = Job.new()
	other.setup(Fakes.FakePerception.new(), Fakes.FakePlanner.new(), Cadence.new())
	other.reads = _reads
	other.ongoing = _is_running
	other.refresh = _refreshed
	assert_bool(other.request(false)).is_false()
	_frame += 1
	assert_bool(other.request(false)).is_true()


func _is_running() -> bool:
	return _running


func test_an_interrupt_cancels_a_job_half_built_and_starts_the_new_one() -> void:
	# A whole job first: its snapshot is the last decision's.
	assert_bool(_job.request(false)).is_true()
	_job.advance()
	_planner.answer()
	assert_int(_decided).is_equal(1)
	assert_dict(_cadence.last_facts).is_equal({ "build": 1 })
	var kept_sections := _cadence.last_sections
	var kept_demand := _cadence.last_demand
	# Then a build spread over frames (a unit per hostile).
	DecisionBudget.cost_hostile = 1
	_perception.hostiles = 2
	_frame += 1
	assert_bool(_job.request(false)).is_true()
	_job.advance()
	var half: Builds.FakeBuild = _perception.builds[1]
	assert_int(half.piece).is_equal(1)  # the start only; the first hostile waits for a frame
	assert_bool(_job.pending()).is_true()
	_frame += 1
	_job.advance()
	assert_int(half.steps).is_equal(2)  # one hostile in, one still to go
	assert_dict(_cadence.last_facts).is_equal({ "build": 1 })  # the last decision still stands
	# A forced decision claims the next frame: the half-built job is dropped, silently.
	_frame += 1
	assert_bool(_job.request(true)).is_true()
	_job.advance()
	assert_int(_perception.builds.size()).is_equal(3)
	assert_int(half.steps).is_equal(2)  # never stepped again
	assert_int(_decided).is_equal(1)  # no walk came of it
	assert_int(_failed).is_equal(0)
	assert_dict(_cadence.last_facts).is_equal({ "build": 1 })
	assert_dict(_cadence.last_sections).is_equal(kept_sections)
	assert_object(_cadence.last_demand).is_same(kept_demand)
	# The new build runs on to its end, and only it replaces the last decision.
	for i in 4:
		_frame += 1
		_job.advance()
	assert_dict(_cadence.last_facts).is_equal({ "build": 3 })
	assert_int(_planner.begun).is_equal(2)


func test_an_interrupt_cancels_a_walk_in_flight_without_a_signal() -> void:
	assert_bool(_job.request(false)).is_true()
	_job.advance()
	assert_int(_planner.begun).is_equal(1)
	_frame += 1
	assert_bool(_job.request(true)).is_true()
	assert_int(_planner.cancelled).is_equal(1)
	assert_int(_decided).is_equal(0)
	assert_int(_failed).is_equal(0)
	_job.advance()
	assert_int(_planner.begun).is_equal(2)
	_planner.answer()
	assert_int(_decided).is_equal(1)  # one walk was decided, the second


func test_a_refused_claim_leaves_the_wish_and_a_job_in_flight_alone() -> void:
	assert_bool(_job.request(false)).is_true()
	_job.advance()
	_cadence.forced = true
	_cadence.force_reason = "hit"
	_cadence.decide_timer = 0.25
	_frame += 1
	assert_bool(_someone_else_spends(1)).is_true()  # an NPC ahead took this frame's unit
	assert_bool(_job.request(true)).is_false()
	assert_bool(_cadence.forced).is_true()
	assert_str(_cadence.force_reason).is_equal("hit")
	assert_float(_cadence.decide_timer).is_equal(0.25)
	assert_int(_planner.cancelled).is_equal(0)
	assert_bool(_job.pending()).is_true()  # the walk carries on
	_planner.answer()
	assert_int(_decided).is_equal(1)
	# The wish is asked again on the next frame and now claims.
	_frame += 1
	assert_bool(_job.request(true)).is_true()


func test_a_cadence_wish_never_cancels_a_job_in_flight() -> void:
	assert_bool(_job.request(false)).is_true()
	_job.advance()
	_frame += 1
	assert_bool(_job.request(false)).is_false()
	assert_int(_planner.cancelled).is_equal(0)
	assert_bool(_job.pending()).is_true()


func test_a_piece_dearer_than_the_pool_runs_alone_on_a_fresh_frame() -> void:
	DecisionBudget.cost_hostile = 3  # more than the pool holds
	DecisionBudget.cost_finish = 1
	_perception.hostiles = 1
	assert_bool(_job.request(false)).is_true()
	_job.advance()
	var build: Builds.FakeBuild = _perception.builds[0]
	assert_int(build.piece).is_equal(1)  # the start used the pool: the hostile waits
	_frame += 1
	assert_bool(_job.pending()).is_true()
	_job.advance()
	assert_int(build.piece).is_equal(2)  # it ran, over the pool, though dearer than it
	assert_bool(_someone_else_spends(1)).is_false()  # and nothing was left for anyone else
	assert_int(_planner.begun).is_equal(0)  # the finish had no room behind it
	_frame += 1
	_job.advance()
	assert_int(_planner.begun).is_equal(1)


func test_an_answered_level_that_costs_waits_for_a_frame_with_room() -> void:
	DecisionBudget.cost_level = 1
	assert_bool(_job.request(false)).is_true()
	_job.advance()
	# The claim frame's unit went on the start: the walk's first level waits for a frame.
	assert_int(_planner.begun).is_equal(1)
	assert_int(_planner.stepped).is_equal(0)
	_frame += 1
	_job.advance()
	assert_int(_planner.stepped).is_equal(1)  # the first level asked Von
	_planner.answer()  # the answer lands the same frame: its unit is spent
	assert_int(_decided).is_equal(0)
	assert_bool(_job.pending()).is_true()
	_frame += 1
	_job.advance()
	assert_int(_decided).is_equal(1)


func test_the_snapshot_stays_as_built_across_the_jobs_life() -> void:
	DecisionBudget.cost_hostile = 1
	DecisionBudget.cost_finish = 1
	_perception.confinement.label = "the house"
	assert_bool(_job.request(false)).is_true()
	_job.advance()
	# The confinement changes while the build waits between its pieces.
	for label in ["the kitchen", "the hall", "the garden"]:
		_frame += 1
		_perception.confinement.label = label
		_job.advance()
	var snapshot: Dictionary = _planner.snapshot
	assert_int(_planner.begun).is_equal(1)  # premise: the build is over
	assert_str(snapshot["confinement"].label).is_equal("the house")  # as at the build's start
	_perception.confinement.label = "the street"  # and after it
	assert_str(_planner.snapshot["confinement"].label).is_equal("the house")


func test_an_order_it_cannot_carry_out_is_refused_and_replaces_the_confinement_copy() -> void:
	DecisionBudget.cost_refusal = 1
	_perception.confinement.label = "the ordered room"  # the order's room
	_perception.orders.held = { "id": 9 }
	_perception.order_options = []  # no option built for it
	assert_bool(_job.request(false)).is_true()
	_job.advance()
	# The build is done; the refusal is a piece of its own and waits for a frame with room.
	assert_dict(_cadence.last_facts).is_equal({ "build": 1 })
	assert_int(_planner.begun).is_equal(0)
	assert_array(_perception.orders.ended).is_empty()
	_perception.confinement.label = "the whole house"  # the refresh drops the order's room
	_frame += 1
	_job.advance()
	assert_array(_perception.orders.ended).is_equal([[9, "refused"]])
	assert_bool(_cadence.last_facts["ordered"]).is_false()
	assert_int(_planner.begun).is_equal(1)
	assert_str(_planner.snapshot["confinement"].label).is_equal("the whole house")
	_perception.confinement.label = "elsewhere"
	assert_str(_planner.snapshot["confinement"].label).is_equal("the whole house")  # a copy


func test_a_build_is_stale_when_its_claim_time_entry_differs() -> void:
	DecisionBudget.cost_hostile = 1
	_perception.entry = &"root"  # what the situation calls for as the build is claimed
	assert_bool(_job.request(false)).is_true()
	assert_bool(_job.stale(&"root")).is_false()  # claimed: its start has not run
	_job.advance()
	assert_bool(_job.walking()).is_false()  # premise: still building
	assert_bool(_job.stale(&"root")).is_false()  # same entry: a forced event does not restart it
	assert_bool(_job.stale(&"combat")).is_true()  # another entry (a fight began): it does
	# The restart claims over the build and starts from what the situation is now.
	_frame += 1
	_perception.entry = &"combat"
	assert_bool(_job.request(true)).is_true()
	_job.advance()
	assert_int(_perception.builds.size()).is_equal(2)
	assert_bool(_job.stale(&"combat")).is_false()


func test_a_build_is_frozen_from_its_start_to_its_walk() -> void:
	DecisionBudget.cost_hostile = 1
	assert_bool(_job.frozen()).is_false()  # nothing in flight
	assert_bool(_job.request(false)).is_true()
	assert_bool(_job.frozen()).is_false()  # claimed: its start will still read what is now
	_job.advance()
	assert_bool(_job.frozen()).is_true()  # what it knows is fixed
	for i in 3:
		_frame += 1
		_job.advance()
	assert_bool(_job.walking()).is_true()  # premise: the walk has begun
	assert_bool(_job.frozen()).is_false()
	assert_bool(_job.stale(&"root")).is_false()
	assert_bool(_job.stale(&"combat")).is_true()  # a walk is compared with where it started


func test_whether_the_last_choice_continues_is_judged_as_the_walk_begins() -> void:
	DecisionBudget.cost_hostile = 1
	_running = true
	assert_bool(_job.request(false)).is_true()
	_job.advance()
	_running = false  # the choice ends while the build is spread over frames
	for i in 3:
		_frame += 1
		_job.advance()
	assert_int(_planner.begun).is_equal(1)  # premise: the walk has begun
	assert_bool(_planner.continuing).is_false()  # the walk is told what is so now, not at the claim


func test_an_order_taken_during_the_build_is_not_refused_on_a_snapshot_made_without_it() -> void:
	DecisionBudget.cost_hostile = 1
	_perception.order_options = []
	assert_bool(_job.request(false)).is_true()  # no order held as the build starts
	_job.advance()
	_perception.orders.held = { "id": 4 }  # one arrives while the build waits
	for i in 4:
		_frame += 1
		_job.advance()
	assert_array(_perception.orders.ended).is_empty()  # not judged on options made without it
	assert_int(_planner.begun).is_equal(1)


func test_a_carried_out_order_leaves_the_snapshot_as_built() -> void:
	_perception.confinement.label = "the ordered room"
	_perception.orders.held = { "id": 9 }
	_perception.order_options = [{ "id": "go" }]
	assert_bool(_job.request(false)).is_true()
	_job.advance()
	assert_array(_perception.orders.ended).is_empty()
	assert_str(_planner.snapshot["confinement"].label).is_equal("the ordered room")
	assert_bool(_cadence.last_facts.has("ordered")).is_false()


func test_an_answer_that_comes_at_once_does_not_run_advance_inside_itself() -> void:
	_planner.levels = 3
	_planner.answers_at_once = true
	assert_bool(_job.request(false)).is_true()
	_job.advance()
	assert_int(_planner.stepped).is_equal(3)  # every level ran, the first one asking
	assert_int(_planner.most_nested).is_equal(1)  # none inside another
	assert_int(_decided).is_equal(1)
	assert_bool(_job.pending()).is_false()


func test_an_order_overtakes_only_a_job_begun_before_it() -> void:
	assert_bool(_job.overtaken_by_order()).is_false()  # nothing in flight
	_cadence.decisions = 4  # the controller books the claim of the job in flight
	assert_bool(_job.request(false)).is_true()
	_job.advance()
	assert_bool(_job.overtaken_by_order()).is_false()  # no order awaited
	_cadence.order_from = 4  # an order taken while decision 4 was the latest
	assert_bool(_job.overtaken_by_order()).is_true()  # made without it: restarted
	_frame += 1
	assert_bool(_job.request(true)).is_true()  # the restart
	_cadence.decisions = 5  # booked
	assert_bool(_job.overtaken_by_order()).is_false()  # made with the order: not restarted for it


func test_every_piece_kind_has_its_own_price_and_an_unknown_one_has_none() -> void:
	DecisionBudget.cost_start = 3
	DecisionBudget.cost_hostile = 5
	DecisionBudget.cost_finish = 11
	DecisionBudget.cost_throw_block = 2
	DecisionBudget.cost_throw_rank = 4
	DecisionBudget.cost_throw_route = 7
	var build_kinds: Dictionary = Job.SnapshotBuild.Piece
	assert_int(_job.cost_of(build_kinds.START)).is_equal(3)
	assert_int(_job.cost_of(build_kinds.HOSTILE)).is_equal(5)
	assert_int(_job.cost_of(build_kinds.FINISH)).is_equal(11)
	assert_int(_job.cost_of(build_kinds.DONE)).is_equal(-1)  # nothing runs for it
	assert_int(_job.cost_of(99)).is_equal(-1)  # never taken for a start
	var throw_kinds: Dictionary = Job.ThrowSearch.Kind
	assert_int(_job.throw_cost_of(throw_kinds.BLOCK)).is_equal(2)
	assert_int(_job.throw_cost_of(throw_kinds.RANK)).is_equal(4)
	assert_int(_job.throw_cost_of(throw_kinds.ROUTE)).is_equal(7)
	assert_int(_job.throw_cost_of(99)).is_equal(-1)
