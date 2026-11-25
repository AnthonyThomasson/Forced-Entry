extends GameTest
## G16, the escape pool's bound on a wait (`EscapePool`): however many searches are begun and
## however they arrive, a search lands no later than `AGE_FRAMES` after it begins plus the work of
## the searches begun before it, over the pool (`per_frame`), and well before its grenade's fuse
## less `ARRIVE_MARGIN`. The order of the pool (the NPC nearest the burst first) alone gives no such
## bound: a stream of nearer searches would serve a farther one last, so a search begun
## `AGE_FRAMES` ago, or whose grenade goes off within the margin and the age, is served first,
## oldest first (`EscapePool.urgent`). The searches here are priced models (`FakeSearch`: a
## search's work in units, run to its end a candidate, 7 units, at a time, as the real one), so the
## pool's schedule is pinned alone, the real search's cost being `escape_pool_spreads_plans`'s. Each
## scenario's owners ask after their search every `ASK_EVERY` frames. A stale search is not revived
## (`serving`), and one whose owner is gone is dropped and served no more.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const AgentThrow := preload("res://scenes/ai/perception/agent_throw.gd")
## The units of one search: what a new plan cost on average over the ai domain's tests (111; the
## median was 65, the dearest 620).
const WORK := 110
## The shortest fuse (a stun, 1.5 s) in frames, and the frames an arrival must beat it by.
const SHORT_FUSE := 1.5
const STREAM_FUSE := 0.5
const ASK_EVERY := 2


func describe() -> Dictionary:
	return {
		"name": "The escape pool bounds a search's wait: oldest and nearest-to-fuse first",
		"description": "Forty searches of 20 NPCs on two grenades, 34 round one frag and a "
			+ "stream of nearer searches that outruns the pool: each lands within the age plus "
			+ "the work before it over the pool and before its fuse less the margin; a search "
			+ "left unasked is not revived and one whose owner is gone is not served.",
		"tags": ["ai", "grenade", "evade", "perf"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.warehouse(s, false)
	EscapePool.reset()
	s.von_script([])


func run(t: TestContext) -> void:
	await _scenario(t, "20 NPCs x 2 grenades", [[1, 20, 40.0, 0], [1, 20, 40.0, 1]])
	await _scenario(t, "34 round one frag", [[1, 34, 60.0, 0]])
	# A stream: two searches a frame for 50 frames, nearer and each with a fuse sooner than the far
	# search's: more than the pool can serve, and one far search (the one checked) begun on the
	# tenth.
	var stream: Array = [[10, 1, 400.0, 0, SHORT_FUSE, true]]
	for frame in range(1, 52):
		stream.append([frame, 2, 40.0, 0, STREAM_FUSE, false])
	await _scenario(t, "outrun by a stream of nearer searches", stream)
	_check_urgent(t)
	_check_order(t)
	await _check_stale(t)
	await _check_owner_gone(t)


## Run searches `arrivals` (`[frame, count, distance (px), grenade, fuse (s), checked]`: `count`
## searches begun `frame` frames after the start (the fuse and `checked` default to the shortest and
## true), their runners `distance` px from the burst, the first of a grenade paying the candidates
## round it) with their owners asking, and check each wait.
func _scenario(t: TestContext, label: String, arrivals: Array) -> void:
	EscapePool.reset()
	var start := Engine.get_physics_frames()
	var rows: Array = []
	var told := {}
	var last := int(arrivals[arrivals.size() - 1][0])
	for guard in last + 400:
		await t.frames(1)
		var now := Engine.get_physics_frames() - start
		for arrival: Array in arrivals:
			if int(arrival[0]) == now:
				_arrive(rows, arrival, told, now)
		_note_backlog(rows, now)
		if _ask_all(rows, now) == 0 and now >= last:
			break
	var late := _late(rows)
	t.check(not rows.is_empty() and late["over"].is_empty(),
			"%s: %d searches, the worst wait %d frames; over the bound: %s"
			% [label, rows.size(), late["worst"], late["over"].slice(0, 3)])
	EscapePool.reset()


## Every owner asks after its search `ASK_EVERY` frames (the frames since it began), at `now`
## frames after the start; the frame a search lands on is noted. How many are still open.
func _ask_all(rows: Array, now: int) -> int:
	var open := 0
	for row: Dictionary in rows:
		var search: FakeSearch = row["search"]
		if not search.done and (now - int(row["began"]) + int(row["seq"])) % ASK_EVERY == 0:
			EscapePool.ask(search)
		if search.done and not row.has("landed"):
			row["landed"] = now
		open += 0 if row.has("landed") else 1
	return open


## The searches that waited past their bound (the age and the work before them over the pool, and
## the shortest fuse less the margin), and the worst wait.
func _late(rows: Array) -> Dictionary:
	var over: Array = []
	var worst := 0
	var fuse_frames := roundi(SHORT_FUSE * Engine.physics_ticks_per_second)
	var margin := ceili(AgentThrow.ARRIVE_MARGIN * Engine.physics_ticks_per_second)
	for row: Dictionary in rows:
		if not row["checked"]:
			continue
		var wait: int = int(row.get("landed", 1_000_000)) - int(row["began"])
		worst = maxi(worst, wait)
		var bound := (
			EscapePool.AGE_FRAMES
			+ ceili(float(row["backlog"]) / EscapePool.per_frame)
			+ 2 * ASK_EVERY
		)
		if wait > bound or wait > fuse_frames - margin:
			over.append("search %d began %d waited %d (bound %d, before the fuse %d)"
					% [row["seq"], row["began"], wait, bound, fuse_frames - margin])
	return { "over": over, "worst": worst }


## `now` frames after the scenario's start.
func _arrive(rows: Array, arrival: Array, told: Dictionary, now: int) -> void:
	for i in int(arrival[1]):
		var search := FakeSearch.new(WORK)
		var grenade: int = arrival[3]
		search.work["built"] = 0 if told.has(grenade) else EscapeSearch.AROUND_UNITS
		told[grenade] = true
		var fuse: float = arrival[4] if arrival.size() > 4 else SHORT_FUSE
		EscapePool.begin(search, false, fuse, float(arrival[2]) + i)
		rows.append({
			"search": search, "began": now, "backlog": 0, "seq": rows.size(),
			"checked": arrival.size() < 6 or arrival[5],
		})


## The work a search begun at `now` waits behind: that of every search begun before it or on the
## same frame (the order of a wave among itself is the nearest first, not the first begun) that is
## not finished.
func _note_backlog(rows: Array, now: int) -> void:
	var backlog := 0
	for row: Dictionary in rows:
		if not (row["search"] as FakeSearch).done:
			backlog += (row["search"] as FakeSearch).left
	for row: Dictionary in rows:
		if int(row["began"]) == now:
			row["backlog"] = backlog


## `urgent`: begun `AGE_FRAMES` ago, or going off within the margin and the age.
func _check_urgent(t: TestContext) -> void:
	var frame := Engine.get_physics_frames()
	var margin := ceili(AgentThrow.ARRIVE_MARGIN * Engine.physics_ticks_per_second)
	var cases := [
		["fresh, a long fuse", [false, frame + 300, 50.0, 1, frame, false], false],
		["aged", [false, frame + 300, 50.0, 1, frame - EscapePool.AGE_FRAMES, false], true],
		["just under the age",
			[false, frame + 300, 50.0, 1, frame - EscapePool.AGE_FRAMES + 1, false], false],
		["its fuse within the margin and the age",
			[false, frame + margin + EscapePool.AGE_FRAMES, 50.0, 1, frame, false], true],
		["its fuse one frame beyond", [false, frame + margin + EscapePool.AGE_FRAMES + 1, 50.0,
			1, frame, false], false],
	]
	for c: Array in cases:
		var search := EscapeSearch.new(RID(), Vector2.ZERO, [], 0.0, Callable())
		search.key = c[1]
		t.expect_eq(EscapePool.urgent(search, frame), c[2], "urgent: %s" % c[0])


## The order with urgency: an urgent search before any other, the oldest of them first, the rest
## in the known order (a new plan, the grenade that goes off first, the nearest runner, the first
## begun).
func _check_order(t: TestContext) -> void:
	var frame := Engine.get_physics_frames()
	var rows := [
		{ "id": 1, "key": [false, frame + 200, 10.0, 5, frame - 2, false] },
		{ "id": 2, "key": [false, frame + 200, 300.0, 3, frame - 20, true] },
		{ "id": 3, "key": [true, frame + 200, 5.0, 2, frame - 30, true] },
		{ "id": 4, "key": [false, frame + 100, 400.0, 4, frame - 3, false] },
	]
	var searches: Array[EscapeSearch] = []
	for row: Dictionary in rows:
		var search := EscapeSearch.new(RID(), Vector2.ZERO, [], 0.0, Callable())
		search.key = row["key"]
		search.touched = row["id"]
		searches.append(search)
	searches.sort_custom(EscapePool._before)
	t.expect_eq(
		searches.map(func(s: EscapeSearch) -> int: return s.touched),
		[3, 2, 4, 1],
		"urgent before the rest, the oldest first; then the soonest fuse",
	)


## A search its owner leaves unasked for more than `STALE_FRAMES` is not served: asked about again,
## its owner gets a new search from where it stands and the fuse left.
func _check_stale(t: TestContext) -> void:
	EscapePool.reset()
	var search := FakeSearch.new(WORK)
	EscapePool.begin(search, false, SHORT_FUSE, 100.0)
	t.check(EscapePool.serving(search), "a search just begun is being served")
	await t.frames(EscapePool.STALE_FRAMES + 10)
	t.check(not EscapePool.serving(search),
			"a search unasked for %d frames is no longer served" % [EscapePool.STALE_FRAMES + 10])
	EscapePool.reset()


## A search whose owner is gone is dropped on the next serve, and spends nothing.
func _check_owner_gone(t: TestContext) -> void:
	EscapePool.reset()
	var owner_alive := [true]
	var gone := FakeSearch.new(WORK)
	gone.alive = func() -> bool: return owner_alive[0]
	var kept := FakeSearch.new(WORK)
	EscapePool.begin(gone, false, SHORT_FUSE, 10.0)
	EscapePool.begin(kept, false, SHORT_FUSE, 400.0)
	owner_alive[0] = false
	await t.frames(1)
	EscapePool.ask(kept)
	t.check(gone.done and gone.left == WORK,
			"a search whose owner is gone is dropped unserved (left %d of %d)" % [gone.left, WORK])
	t.check(kept.left < WORK, "the pool serves the search of an owner that is alive")
	EscapePool.reset()


## A search of `left` units of work, run a candidate (up to 7 units) at a time.
class FakeSearch extends EscapeSearch:
	var left: int

	func _init(units: int) -> void:
		super._init(RID(), Vector2.ZERO, [], 0.0, Callable())
		left = units

	func step(units: int) -> int:
		var spent := 0
		while left > 0 and spent < units:
			var candidate := mini(7, left)
			spent += candidate
			left -= candidate
		if left <= 0:
			done = true
		return spent
