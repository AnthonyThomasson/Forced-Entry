extends RefCounted
## The worst-frames report of a frame-based perf test (`perf.md`): the N slowest frames of a
## window, each with its wall time and what ran in it, so a red run names its spike. Load it with
## `const Report := preload("res://tests/_perf/frame_report.gd")`; `Perf.frame_stats` takes the
## counters while the game's log is on (`--verbose`) and `Perf.within_frames` prints the report.
## Not a test (no `_test.gd` suffix).
##
## What ran is read off counters the game keeps, cheap ints and no clock (the wall clock stays in
## tests/perf and tests/_perf, lint rule `timing_in_perf`; the one counter added to the game is the
## roster's claim count): the decisions claimed (`DecisionRoster.claims()`: the snapshot build runs
## in its claim's frame and Von's answer lands later), the shots, grenades thrown, explosions, radio
## callouts and deaths posted (the event log), the asks made of Von (`DecisionStub.requests`, one a
## planner level, so a decision is one or more), the cone rebuilds a view started and published
## (`PlayerView.starts`, `rebuilds`), the nav bakes started and the late ones (`NavBake`). The pure
## part (`worst`, `deltas`, `ran_between`, `line`) is `tests/perf/frame_report_suite.gd`.

## The event log's topics that are counters, and the key each counts under.
const EVENTS := {
	&"shot": "shots", &"throw": "throws", &"explosion": "explosions",
	&"callout": "callouts", &"death": "deaths",
}
## The counters, in the order a line names them, each with the words a count of one and of more use.
const COUNTERS := [
	["claims", "decision claimed", "decisions claimed"],
	["asks", "decision asked", "decisions asked"],
	["shots", "shot", "shots"],
	["cone_starts", "cone start", "cone starts"],
	["cone_publishes", "cone publish", "cone publishes"],
	["throws", "grenade thrown", "grenades thrown"],
	["explosions", "explosion", "explosions"],
	["callouts", "callout", "callouts"],
	["deaths", "death", "deaths"],
	["bakes", "nav bake", "nav bakes"],
	["late_bakes", "late bake", "late bakes"],
]

var _t: TestContext
var _views: Array
## How many of the event log's entries `sample` has read.
var _events_seen := 0
## Event counts by counter key, for the topics `EVENTS` maps.
var _events := {}
## The totals `sample` took, in order.
var _taken: Array = []


## A reader of the counters for the running test `t`: its views (`PlayerView` nodes of the world,
## found once) are the cone counters' source.
static func counters_of(t: TestContext) -> RefCounted:
	var reader := new()
	reader._t = t
	reader._views = t.world.find_children("*", "PlayerView", true, false)
	reader._events_seen = t.events.size()
	return reader


## Take the counters now, each a running total (`deltas` of two samples is what ran between them).
## Reads only the log's new entries and a few ints; free while nothing calls it.
func sample() -> void:
	_taken.append(_read())


## What ran in each frame between the samples taken (`ran_per_frame`).
func ran_per_frame() -> Array:
	return ran_between(_taken)


func _read() -> Dictionary:
	var events := _t.events
	for i in range(_events_seen, events.size()):
		var key: String = EVENTS.get(events[i]["topic"], "")
		if key != "":
			_events[key] = _events.get(key, 0) + 1
	_events_seen = events.size()
	var starts := 0
	var publishes := 0
	for view: Node in _views:
		if is_instance_valid(view):
			starts += view.starts()
			publishes += view.rebuilds()
	return {
		"claims": DecisionBudget.Roster.claims(),
		"asks": DecisionStub.requests.size(),
		"shots": _events.get("shots", 0),
		"throws": _events.get("throws", 0),
		"explosions": _events.get("explosions", 0),
		"callouts": _events.get("callouts", 0),
		"deaths": _events.get("deaths", 0),
		"cone_starts": starts,
		"cone_publishes": publishes,
		"bakes": NavBake.started_total,
		"late_bakes": NavBake.late_total,
	}


## What rose between two samples: each counter whose total grew, by how much.
static func deltas(before: Dictionary, after: Dictionary) -> Dictionary:
	var out := {}
	for key: Variant in after:
		var rise: int = int(after[key]) - int(before.get(key, 0))
		if rise > 0:
			out[key] = rise
	return out


## What ran in each frame of a window from the totals sampled at its frames' starts and once after
## the last: one entry per pair, the first frame's the rise from the first sample to the second.
static func ran_between(samples: Array) -> Array:
	var out := []
	for i in range(1, samples.size()):
		out.append(deltas(samples[i - 1], samples[i]))
	return out


## The `n` slowest frames of `samples` (ms a frame), the slowest first, an equal pair in frame
## order: `[{ frame, ms, ran }]`, `ran` the frame's entry of `ran` (`ran_between`; `{}` where
## there is none). Fewer when the window is shorter.
static func worst(samples: Array[float], ran: Array, n: int) -> Array[Dictionary]:
	var order := range(samples.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return samples[a] > samples[b] or (samples[a] == samples[b] and a < b))
	var out: Array[Dictionary] = []
	for frame: int in order.slice(0, n):
		out.append({
			"frame": frame,
			"ms": samples[frame],
			"ran": ran[frame] if frame < ran.size() else {},
		})
	return out


## One worst frame as a line: `#<frame> <ms> ms: 2 decisions asked, 1 shot`, or `nothing counted`.
static func line(entry: Dictionary) -> String:
	var parts: PackedStringArray = []
	var ran: Dictionary = entry["ran"]
	for counter: Array in COUNTERS:
		var count: int = ran.get(counter[0], 0)
		if count > 0:
			parts.append("%d %s" % [count, counter[1] if count == 1 else counter[2]])
	return "#%d %.1f ms: %s" % [
		entry["frame"],
		entry["ms"],
		", ".join(parts) if not parts.is_empty() else "nothing counted",
	]
