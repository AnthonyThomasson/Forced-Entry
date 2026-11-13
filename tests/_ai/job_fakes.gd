extends RefCounted
## Test helper: a perception and a planner the decision job suites (`decision_job_suite`,
## `decision_job_pieces_suite`) drive the job with, no engine: the perception makes
## `Fakes.FakeBuild`s and holds the order and the confinement, the planner walks level by level,
## each level waiting for a scripted answer (`answer`).

const Builds := preload("res://tests/_ai/job_build_fakes.gd")
const Budget := preload("res://scenes/ai/decision/decision_budget.gd")
## The pool and prices of `DecisionBudget`, by name.
const PRICES := [
	"per_frame", "cost_start", "cost_hostile", "cost_finish", "cost_refusal", "cost_level",
	"cost_throw_block", "cost_throw_rank", "cost_throw_route", "throw_block",
]


## The pool and prices as they stand now (a suite keeps the game's own to put back).
static func prices() -> Dictionary:
	var budget: Object = Budget
	var out := {}
	for name: String in PRICES:
		out[name] = budget.get(name)
	return out


## Put `values` (from `prices`) back.
static func set_prices(values: Dictionary) -> void:
	var budget: Object = Budget
	for name: String in values:
		budget.set(name, values[name])


## The whole prices: a pool of one unit, the claim's start the one thing that costs, every later
## piece free, so a decision runs whole in the frame it was claimed (what a suite that steps
## pieces by hand starts from, then prices the pieces it means to).
static func whole_prices() -> void:
	set_prices({
		"per_frame": 1, "cost_start": 1, "cost_hostile": 0, "cost_finish": 0, "cost_refusal": 0,
		"cost_level": 0, "cost_throw_block": 0, "cost_throw_rank": 0, "cost_throw_route": 0,
		"throw_block": 16,
	})


class FakePerception:
	extends RefCounted
	## The entry node the situation calls for now (`quick_facts`).
	var entry := &"root"
	var confinement := Builds.FakeConfinement.new()
	var orders := Builds.FakeOrders.new()
	var hostiles := 2
	var order_options: Array = []
	var builds: Array = []
	## The throw search the next build's demand hands out (null: none).
	var search: RefCounted
	var rereads := 0
	var memos_held := 0

	func hold_walks() -> RefCounted:
		memos_held += 1
		return RefCounted.new()

	func reread_claims(_snapshot: Dictionary) -> void:
		rereads += 1

	func quick_facts() -> Dictionary:
		return { "entry": entry }

	func begin_sense(_goal: String, _activity: String, _engaged := 0) -> Builds.FakeBuild:
		var b := Builds.FakeBuild.new()
		b.perception = self
		b.hostiles = hostiles
		b.number = builds.size() + 1
		builds.append(b)
		return b


## A walk of `levels` levels: a level asks Von and waits for `answer()`, the last one finishes.
class FakePlanner:
	extends RefCounted
	signal decided(leaf: Dictionary)
	@warning_ignore("unused_signal")  # connected by the suites, never emitted here
	signal failed()
	signal piece_ready()
	var driven := false
	var levels := 2
	var snapshot := {}
	var continuing := false
	var begun := 0
	var cancelled := 0
	var stepped := 0
	## Whether Von answers each level the moment it is asked (a stub transport), inside `step`.
	var answers_at_once := false
	## How deep `step` was ever nested in itself (a job that re-entered would make it 2).
	var most_nested := 0
	var _nested := 0
	var _level := 0
	var _pending := false
	var _ready := false

	func begin(snap: Dictionary, ongoing: bool) -> void:
		snapshot = snap
		continuing = ongoing
		begun += 1
		_level = 0
		_pending = true
		_ready = true

	func is_pending() -> bool:
		return _pending

	func has_piece() -> bool:
		return _pending and _ready

	func current_entry() -> StringName:
		return &"root"

	func entry_for(facts: Dictionary) -> StringName:
		return facts["entry"]

	func cancel() -> void:
		if _pending:
			cancelled += 1
		_pending = false
		_ready = false

	func step() -> void:
		stepped += 1
		_nested += 1
		most_nested = maxi(most_nested, _nested)
		_ready = false
		_level += 1
		if _level >= levels:
			_pending = false
			decided.emit({ "path": ["leaf"] })
		elif answers_at_once:
			answer()
		_nested -= 1

	## Von's answer to the level asked.
	func answer() -> void:
		_ready = true
		piece_ready.emit()
