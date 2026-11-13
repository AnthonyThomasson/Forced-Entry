extends RefCounted
## Test helper: the snapshot build and its pieces the decision job suites (`decision_job_suite`,
## `decision_job_pieces_suite`) drive, as fakes: a confinement stand-in, the held order, a build of
## START / HOSTILE / FINISH pieces that is its own demand, and a throw search of scripted steps.
## `FakePerception` and `FakePlanner` (`job_fakes.gd`) hand them out.


## A confinement stand-in: the live one reads `label`, a copy keeps what it was when copied.
class FakeConfinement:
	extends RefCounted
	var label := ""

	func copy() -> FakeConfinement:
		var c := FakeConfinement.new()
		c.label = label
		return c


## The held order, and what was done to it.
class FakeOrders:
	extends RefCounted
	var held := {}
	var ended: Array = []

	func current() -> Dictionary:
		return held

	func end(id: int, why: String) -> void:
		ended.append([id, why])


## A snapshot being built: START, one HOSTILE piece per hostile, FINISH (the kinds of
## `SnapshotBuild.Piece`: 0, 1, 2, then DONE = 3).
class FakeBuild:
	extends RefCounted
	var perception: RefCounted
	var number := 0
	var hostiles := 0
	var piece := 0
	var steps := 0
	var _taken := 0
	var _confinement: FakeConfinement
	var _result := {}

	func next_piece() -> int:
		return piece

	func done() -> bool:
		return piece == 3

	func step() -> void:
		steps += 1
		match piece:
			0:
				_confinement = perception.confinement.copy()
				piece = 1 if hostiles > 0 else 2
			1:
				_taken += 1
				piece = 1 if _taken < hostiles else 2
			2:
				_result = {
					"facts": { "build": number },
					"sections": { "goal": "build %d" % number },
					"demand": self,
					"sections_per_target": { 7: "x" },
					"options": { "order": { "options": perception.order_options } },
					"confinement": _confinement,
				}
				piece = 3

	func result() -> Dictionary:
		return _result

	## The demand's throw search (this fake is its snapshot's demand): `perception.search` as the
	## next throw search, once, or none.
	func throw_search(_block: int) -> RefCounted:
		var search: RefCounted = perception.search
		perception.search = null
		return search

	## The demand's group steps (`perception.groups` once, or none) and the throws' after the throw
	## search (`perception.grenades`).
	func group_steps() -> RefCounted:
		var groups: RefCounted = perception.groups
		perception.groups = null
		return groups

	func grenade_steps() -> RefCounted:
		var grenades: RefCounted = perception.grenades
		perception.grenades = null
		return grenades


## A throw search of scripted steps: each kind in `kinds` (`ThrowSearch.Kind`) is a step, then done
## (`done_kind`: 3 for a throw search; `GroupBuild.Kind.DONE`, 2, for group steps).
class FakeSearch:
	extends RefCounted
	var kinds: Array = []
	var steps := 0
	var done_kind := 3
	## How often the job asked for the next step's kind (a real search does its free work then).
	var kind_calls := 0

	func next_kind() -> int:
		kind_calls += 1
		return kinds[steps] if steps < kinds.size() else done_kind

	func step() -> void:
		steps += 1
