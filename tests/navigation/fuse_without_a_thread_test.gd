extends GameTest
## A gather's furniture fusing (`NavFuse`) runs on a worker thread and is joined on the step that
## needs it. The pool has no cancel, so a fusing whose task never started must not block that step
## until a thread frees: `join` fuses on the calling thread instead and the result is the same one
## a plain `NavUnion.fuse` makes, whichever of the two ran it. A fusing dropped before it was
## wanted runs nothing that had not begun.

const DISTRICT_SEED := 7
## How long a sleeper holds its thread: past the fusing's inline run.
const SLEEP_MS := 600


func describe() -> Dictionary:
	return {
		"name": "A fusing whose thread never started is fused by the step that needs it",
		"description": "NavFuse.join runs the fusing inline when the worker has not started, and "
			+ "its result equals a plain fuse's, as does one a worker made.",
		"tags": ["navigation", "district", "rebake", "perf"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


func run(t: TestContext) -> void:
	var holder := Node2D.new()
	t.world.add_child(holder)
	var district := WorldGen.generate_district(DISTRICT_SEED, "", Vector2.ZERO, holder)
	await t.frames(2)
	var outlines := NavSource.local_outlines(
		district.position,
		NavBuilder.furniture_holes(district),
	)
	if not t.require(outlines.size() > 100, "premise: a crowd of footprints"):
		return
	var plain := NavUnion.fuse(outlines)

	var never := NavFuse.new()
	never.start(outlines, false)
	t.check(never.join() == NavFuse.Found.INLINE, "a fusing no thread started is fused inline")
	t.check(never.fusion.result() == plain, "and equals a plain fuse")
	t.check(never.join() == NavFuse.Found.DONE, "a second join finds it done")

	await _check_queued_behind_busy_threads(t, outlines, plain)

	var worked := NavFuse.new()
	worked.start(outlines)
	var found := worked.join()  # the thread may or may not have begun: either way
	t.check(
		worked.fusion.result() == plain,
		"a fusing started on a worker equals a plain fuse (joined: %s)"
			% NavFuse.Found.keys()[found],
	)

	var dropped := NavFuse.new()
	dropped.start(outlines, false)
	dropped.abandon()
	t.check(dropped.fusion.result().is_empty(), "a fusing dropped before it began fused nothing")
	holder.queue_free()


## A real worker task that never starts: every pool thread held by a high-priority sleeper (two
## waves, so the fusing is queued behind a second one still), as the ring bake's test does. The
## fusing is joined inline; the task that runs once the sleepers end finds it claimed and fuses
## nothing (`_next_id` counts the outlines a fusion took in, so a second fusing would move it).
func _check_queued_behind_busy_threads(
	t: TestContext, outlines: Array, plain: Array,
) -> void:
	await _drain_orphans(t)  # a task an earlier join left queued is not this case's
	var sleepers: Array[int] = []
	for _i in OS.get_processor_count() * 2:
		sleepers.append(
			WorkerThreadPool.add_task(func() -> void: OS.delay_msec(SLEEP_MS), true),
		)
	var queued := NavFuse.new()
	queued.start(outlines)
	t.check(
		queued.join() == NavFuse.Found.INLINE,
		"a fusing queued behind busy threads is fused inline",
	)
	t.check(queued.fusion.result() == plain, "and equals a plain fuse")
	t.check(
		NavFuse._orphans.size() == 1,
		"its queued task is kept to be waited for once it has run",
	)
	t.expect_eq(queued.fusion._next_id, outlines.size(), "it fused each outline once")
	for task in sleepers:
		WorkerThreadPool.wait_for_task_completion(task)
	await _drain_orphans(t)
	t.check(NavFuse._orphans.is_empty(), "the late task ran and was reaped")
	t.expect_eq(
		queued.fusion._next_id,
		outlines.size(),
		"the late task found the fusing claimed: it fused nothing",
	)
	t.check(queued.fusion.result() == plain, "and the fusion is unchanged")


## Wait for the tasks `NavFuse.join` left queued to have run, and reap them.
func _drain_orphans(t: TestContext) -> void:
	var waited := 0
	while not NavFuse._orphans.is_empty() and waited < 300:
		NavFuse.reap()
		await t.frames(1)
		waited += 1
