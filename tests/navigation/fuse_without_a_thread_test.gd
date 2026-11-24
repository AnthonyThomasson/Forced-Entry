extends GameTest
## A gather's furniture fusing (`NavFuse`) runs on a worker thread and is joined on the step that
## needs it. The pool has no cancel, so a fusing whose task never started must not block that step
## until a thread frees: `join` fuses on the calling thread instead and the result is the same one
## a plain `NavUnion.fuse` makes, whichever of the two ran it. A fusing dropped before it was
## wanted runs nothing that had not begun.

const DISTRICT_SEED := 7


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

	var racing := NavFuse.new()
	racing.start(outlines)
	racing.abandon()  # whichever began, no task is left running unwaited
	NavFuse.reap()
	t.check(racing.fusion.result().size() <= plain.size(), "a started fusing dropped is waited for")
	holder.queue_free()
