extends RefCounted
## Test helper (perf): a fixed reference loop timed in the same frames as the work under test, so a
## guard can be a ratio that a loaded machine moves as much as it moves the work (`time_ms()` of
## the loop and the update both stretch with the load, their ratio does not). The loop does what a
## per-frame update does in miniature: reads a row of a dictionary, checks a node is alive and reads
## a property of it. `release()` frees its nodes.

const ROWS := 400
const PASSES := 3

var _rows: Array[Dictionary] = []


func _init() -> void:
	for i in ROWS:
		_rows.append({ "node": Node3D.new(), "gone": false, "id": i })


## One run of the loop, in ms.
func time_ms() -> float:
	var seen := 0
	var from := Time.get_ticks_usec()
	for _pass in PASSES:
		for row in _rows:
			if row.get("gone", false) or not is_instance_valid(row["node"]):
				continue
			if (row["node"] as Node3D).visible:
				seen += 1
	var spent := float(Time.get_ticks_usec() - from) / 1000.0
	assert(seen == ROWS * PASSES)
	return spent


## Free the nodes the loop holds.
func release() -> void:
	for row in _rows:
		(row["node"] as Node).free()
	_rows.clear()
