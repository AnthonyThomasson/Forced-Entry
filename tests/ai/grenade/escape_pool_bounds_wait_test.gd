extends GameTest
## G16, the escape pool's bound on a wait (`EscapePool`): however many searches are begun and
## however they arrive, an urgent search (begun `AGE_FRAMES` ago, or its grenade going off within
## the margin and the age: `EscapePool.urgent`) is served first, the one whose grenade goes off
## first of them, then the one begun first, so a search lands before its fuse less `ARRIVE_MARGIN`
## whenever the work of the searches with a fuse no later than its own fits in the time, and
## otherwise by the age and the work begun before it over the pool (the first rule below). The
## order of the pool (the NPC nearest the burst first) alone gives no such bound: a stream of
## nearer searches would serve a farther one last. The searches here are priced models
## (`FakeSearch`: a search's work in units, run to its end a candidate, 7 units, at a time, as the
## real one), so the pool's schedule is pinned alone, the real search's cost being
## `escape_pool_spreads_plans`'s. Each scenario's owners ask after their search every `ASK_EVERY`
## frames (so the bound holds for an owner asking at least every `STALE_FRAMES`). A stale search
## is not revived (`serving`), and one whose owner is gone is dropped and served no more.
##
## Two bounds, by what is checked in a scenario: `by_deadline` rows land before their fuse less the
## margin, the others (one fuse, one wave after another) also within `AGE_FRAMES` plus the work
## begun before them over the pool. A later grenade with a sooner fuse goes ahead of an earlier
## wave (`_check_two_waves`), so a far search with a long fuse behind a stream of sooner fuses
## has only its deadline for a bound (`stream`, the trade the order makes).

const Maps := preload("res://tests/_ai/flank_maps.gd")
const AgentThrow := preload("res://scenes/ai/perception/agent_throw.gd")
## The units of one search: what a new plan cost on average over the ai domain's tests (111; the
## median was 65, the dearest 620).
const WORK := 110
## The shortest fuse (a stun, 1.5 s) in frames, and the frames an arrival must beat it by.
const SHORT_FUSE := 1.5
const STREAM_FUSE := 0.5
const ASK_EVERY := 2
## The pool, the urgent extra and a candidate, as written here (80 + 80 + 7), not read from the
## statics: a change of the pool is a change of what this test pins.
const POOL := 80
const FRAME_MOST := 167
const ONE_CANDIDATE := 7


func describe() -> Dictionary:
	return {
		"name": "The escape pool bounds a search's wait: urgent first, the soonest fuse first",
		"description": "Forty searches of 20 NPCs on two grenades, 34 round one frag, a stream "
			+ "of nearer searches that outruns the pool, a stream of new grenades, a frag "
			+ "thrown after a stun wave and a replan with a short fuse: each lands within its "
			+ "bound and before its fuse less the margin; no frame serves more than the pool "
			+ "(and the urgent extra while a search is urgent); a search left unasked is not "
			+ "revived and one whose owner is gone is not served.",
		"tags": ["ai", "grenade", "evade", "perf"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.warehouse(s, false)
	EscapePool.reset()
	s.von_script([])


func run(t: TestContext) -> void:
	var two := [_arrival(1, 20, 40.0, 0), _arrival(1, 20, 40.0, 1)]
	var seen: Dictionary = await _scenario(t, "20 NPCs x 2 grenades", two)
	t.check(
		seen["peak_served"] > POOL and seen["peak_served"] <= FRAME_MOST,
		"a wave past the age is served at the urgent rate, and no more (a frame: %d of %d + %d)"
			% [seen["peak_served"], POOL, FRAME_MOST - POOL],
	)
	await _scenario(t, "34 round one frag", [_arrival(1, 34, 60.0, 0)])
	# A stream: two searches a frame for 50 frames, nearer and each with a fuse sooner than the far
	# search's: more than the pool can serve, and one far search (the one checked) begun on the
	# tenth. The sooner fuses go first, so the far search is bound by its own deadline only.
	var stream: Array = [_arrival(10, 1, 400.0, 0, { "fuse": SHORT_FUSE, "by_deadline": true })]
	for frame in range(1, 52):
		stream.append(_arrival(frame, 2, 40.0, 0, { "fuse": STREAM_FUSE, "checked": false }))
	await _scenario(t, "outrun by a stream of nearer searches", stream)
	await _check_new_grenades(t)
	await _check_two_waves(t)
	await _check_young_replan(t)
	_check_urgent(t)
	_check_order(t)
	await _check_stale(t)
	await _check_owner_gone(t)


## An arrival: `count` searches begun `at` (from 1) frames after the scenario's start, their runners
## `distance` px from the burst (a px further each), of grenade number `grenade`. `opts`: `fuse`
## (s, the shortest), `checked` (the waits are held to a bound, true), `by_deadline` (the bound is
## the fuse less the margin only, false), `each_new` (every search is of a new grenade, paying the
## candidates round it, false) and `replan` (the search replaces a plan, false).
func _arrival(
	at: int,
	count: int,
	distance: float,
	grenade: int,
	opts: Dictionary = {},
) -> Dictionary:
	var arrival := {
		"at": at, "count": count, "distance": distance, "grenade": grenade,
		"fuse": SHORT_FUSE, "checked": true, "by_deadline": false, "each_new": false,
		"replan": false,
	}
	arrival.merge(opts, true)
	return arrival


## Run searches `arrivals` (`_arrival`) with their owners asking, and check each wait, and what a
## frame served. Returns `{ peak_served }` (the most units a frame served, by the searches' own
## count).
func _scenario(t: TestContext, label: String, arrivals: Array) -> Dictionary:
	EscapePool.reset()
	var start := Engine.get_physics_frames()
	var rows: Array = []
	var told := {}
	var served := {}
	var last := 0
	for arrival: Dictionary in arrivals:
		last = maxi(last, int(arrival["at"]))
	for guard in last + 600:
		await t.frames(1)
		var now := Engine.get_physics_frames() - start
		for arrival: Dictionary in arrivals:
			if int(arrival["at"]) == now:
				_arrive(rows, arrival, told, now, served)
		_note_backlog(rows, now)
		_note_urgent(rows, served)
		if _ask_all(rows, now) == 0 and now >= last:
			break
	var late := _late(rows)
	t.check(not rows.is_empty() and late["over"].is_empty(),
			"%s: %d searches, the worst wait %d frames; over the bound: %s"
			% [label, rows.size(), late["worst"], late["over"].slice(0, 3)])
	var peak := _check_frames(t, label, served)
	t.check(
		EscapePool.peak_served == peak and EscapePool.peak_spent >= peak,
		"%s: the pool's count of the most a frame served (%d) is the searches' (%d); spent %d"
			% [label, EscapePool.peak_served, peak, EscapePool.peak_spent],
	)
	EscapePool.reset()
	return { "peak_served": peak }


## What each frame served (`served`: frame -> `{ units, urgent }`): a frame with no urgent search
## served the pool and one candidate at most, any frame the pool, the urgent extra and one
## candidate. The most a frame served.
func _check_frames(t: TestContext, label: String, served: Dictionary) -> int:
	var peak := 0
	var over_calm: Array = []
	var over_any: Array = []
	for frame: int in served:
		var row: Dictionary = served[frame]
		peak = maxi(peak, int(row["units"]))
		if not row["urgent"] and int(row["units"]) > POOL + ONE_CANDIDATE:
			over_calm.append("frame %d served %d" % [frame, row["units"]])
		if int(row["units"]) > FRAME_MOST:
			over_any.append("frame %d served %d" % [frame, row["units"]])
	t.check(over_calm.is_empty(), "%s: a frame with no urgent search serves at most %d: %s"
			% [label, POOL + ONE_CANDIDATE, over_calm.slice(0, 3)])
	t.check(over_any.is_empty(), "%s: no frame serves more than %d: %s"
			% [label, FRAME_MOST, over_any.slice(0, 3)])
	return peak


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


## The searches that waited past their bound (the age and the work before them over the pool, or
## only the fuse less the margin for a `by_deadline` one), and the worst wait.
func _late(rows: Array) -> Dictionary:
	var over: Array = []
	var worst := 0
	var margin := ceili(AgentThrow.ARRIVE_MARGIN * Engine.physics_ticks_per_second)
	for row: Dictionary in rows:
		if not row["checked"]:
			continue
		var wait: int = int(row.get("landed", 1_000_000)) - int(row["began"])
		worst = maxi(worst, wait)
		var until_fuse := roundi(float(row["fuse"]) * Engine.physics_ticks_per_second) - margin
		var bound := until_fuse
		if not row["by_deadline"]:
			bound = mini(
				until_fuse,
				EscapePool.AGE_FRAMES
				+ ceili(float(row["backlog"]) / POOL)
				+ 2 * ASK_EVERY,
			)
		if wait > bound:
			over.append("search %d began %d waited %d (bound %d, before the fuse %d)"
					% [row["seq"], row["began"], wait, bound, until_fuse])
	return { "over": over, "worst": worst }


## `now` frames after the scenario's start.
func _arrive(
	rows: Array,
	arrival: Dictionary,
	told: Dictionary,
	now: int,
	served: Dictionary,
) -> void:
	for i in int(arrival["count"]):
		var search := FakeSearch.new(WORK)
		search.served = served
		var grenade: int = arrival["grenade"]
		search.work["built"] = (
			0 if told.has(grenade) and not arrival["each_new"] else EscapeSearch.AROUND_UNITS
		)
		told[grenade] = true
		EscapePool.begin(
			search, arrival["replan"], float(arrival["fuse"]), float(arrival["distance"]) + i,
		)
		rows.append({
			"search": search, "began": now, "backlog": 0, "seq": rows.size(),
			"checked": arrival["checked"], "by_deadline": arrival["by_deadline"],
			"fuse": arrival["fuse"],
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


## Whether any search still open is urgent at this frame (the pool is served after the owners
## have asked, so what the next ask serves is read here, before it).
func _note_urgent(rows: Array, served: Dictionary) -> void:
	var frame := Engine.get_physics_frames()
	var urgent := false
	for row: Dictionary in rows:
		var search: FakeSearch = row["search"]
		if not search.done and int(search.key[4]) != frame and EscapePool.urgent(search, frame):
			urgent = true
	if not served.has(frame):
		served[frame] = { "units": 0, "urgent": false }
	served[frame]["urgent"] = served[frame]["urgent"] or urgent


## New grenades begun every frame (ten a frame, each paying its 16 candidate units: more than the
## frame's pool and the urgent extra between them) do not take the frame from the urgent work: a
## wave of 20 begun first lands within its bound, the units a grenade is built with being no part
## of what a frame serves.
func _check_new_grenades(t: TestContext) -> void:
	var arrivals: Array = [_arrival(1, 20, 400.0, 0)]
	for frame in range(2, 42):
		var opts := { "each_new": true, "checked": false }
		arrivals.append(_arrival(frame, 10, 40.0, 100 + frame, opts))
	var seen: Dictionary = await _scenario(t, "a stream of new grenades", arrivals)
	t.check(
		seen["peak_served"] > POOL,
		"the urgent wave was served past the pool (%d) while new grenades were built"
			% [seen["peak_served"]],
	)


## A wave begun at frame 1 (60 NPCs round a stun, 1.5 s) and a frag begun at frame 21 with 0.7 s
## (42 frames) of fuse left: the frag's plans land by its fuse less the margin (18 frames), before
## the stun's wave, because the sooner fuse is served first once urgent (a search is served in the
## order of the first begun, a wave begun first would hold it until frame 53).
func _check_two_waves(t: TestContext) -> void:
	var seen: Dictionary = await _scenario(t, "a frag thrown 20 frames after a stun wave", [
		_arrival(1, 60, 40.0, 0, { "by_deadline": true }),
		_arrival(21, 6, 40.0, 1, { "fuse": 0.7, "by_deadline": true }),
	])
	t.check(seen["peak_served"] <= FRAME_MOST, "set-up: no frame served more than %d" % FRAME_MOST)


## A replan begun young whose grenade goes off within 36 frames (the margin and the age) is urgent
## at once: it is served ahead of 30 older searches with no plan yet that are not urgent (the
## order puts a new plan first, so only urgency lets the replan by), and lands by its deadline.
func _check_young_replan(t: TestContext) -> void:
	await _scenario(t, "a young replan with a short fuse among older new plans", [
		_arrival(1, 30, 40.0, 0, { "fuse": 3.0, "checked": false }),
		_arrival(5, 1, 400.0, 1, { "fuse": STREAM_FUSE, "replan": true, "by_deadline": true }),
	])


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


## The order with urgency: an urgent search before any other, the one whose grenade goes off first
## of them (a later grenade with a sooner fuse goes ahead of an earlier one), then the oldest, the
## rest in the known order (a new plan, the grenade that goes off first, the nearest runner, the
## first begun).
func _check_order(t: TestContext) -> void:
	var frame := Engine.get_physics_frames()
	var rows := [
		{ "id": 1, "key": [false, frame + 200, 10.0, 5, frame - 2, false] },
		{ "id": 2, "key": [false, frame + 200, 300.0, 3, frame - 20, true] },
		{ "id": 3, "key": [true, frame + 200, 5.0, 2, frame - 30, true] },
		{ "id": 4, "key": [false, frame + 100, 400.0, 4, frame - 3, false] },
		{ "id": 5, "key": [false, frame + 60, 90.0, 6, frame - 13, true] },
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
		[5, 3, 2, 4, 1],
		"urgent before the rest, the soonest fuse first, then the oldest; then the soonest fuse",
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
	## What each physics frame served: frame -> `{ units, urgent }`, shared by a scenario's
	## searches.
	var served := {}

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
		var frame := Engine.get_physics_frames()
		if not served.has(frame):
			served[frame] = { "units": 0, "urgent": false }
		served[frame]["units"] += spent
		return spent
