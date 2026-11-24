class_name NavFuse extends RefCounted
## Navigation domain: one fusing of footprints (`NavUnion`) run on a worker thread, with a way out
## when the thread never starts. The pool has no cancel, so a task still queued when its result is
## wanted (every thread busy) would hold the frame until a thread frees. The fusing is claimed by
## whoever gets to it first: the worker (the task finds it claimed no more) or `join`, which then
## runs it on the calling thread, so a frame never waits for a thread that has not begun. Either
## way the result is the one a single `NavUnion.fuse` makes.

## How `join` found the fusing.
enum Found {
	DONE,
	WAITED,
	INLINE,
}

## Tasks whose fusing `join` ran itself: queued still, a no-op when they run, waited for once done
## (`reap`), as the pool wants every task waited for.
static var _orphans: Array[int] = []

## The fusion the outlines were fed to; read its `result()` after `join`.
var fusion := NavUnion.new()
var _outlines: Array = []
var _task := -1
var _mutex := Mutex.new()
var _claimed := false


## Start fusing `outlines` on a high-priority worker (so it does not queue behind the bakes in
## flight). With `on_worker` false none is queued: the test seam of a thread that never starts.
func start(outlines: Array, on_worker := true) -> void:
	_outlines = outlines
	if on_worker:
		_task = WorkerThreadPool.add_task(_run, true, "nav gather fuse")


## Have the fusing done: `Found.DONE` when the worker had finished, `WAITED` when it was running
## and the call waited for it, `INLINE` when it had not started and this call fused on its own
## thread.
func join() -> Found:
	var found := Found.DONE
	if _take():
		fusion.add_all(_outlines)
		found = Found.INLINE
		_orphan()
	elif _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			found = Found.WAITED
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	return found


## Drop the fusing before it is wanted: none runs that has not begun, and a running one is waited
## for.
func abandon() -> void:
	if _take():
		_orphan()
	elif _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## Wait for the tasks `join` left queued that are done now (the pool wants each waited for once).
static func reap() -> void:
	for id in _orphans.duplicate():
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			_orphans.erase(id)


## The worker's task: fuse, unless a `join` has.
func _run() -> void:
	if _take():
		fusion.add_all(_outlines)


## Claim the fusing; false when the worker (or a call) has it.
func _take() -> bool:
	_mutex.lock()
	var mine := not _claimed
	_claimed = true
	_mutex.unlock()
	return mine


## The task is queued still and a no-op when it runs: waited for once it is done (`reap`).
func _orphan() -> void:
	if _task >= 0:
		_orphans.append(_task)
		_task = -1
