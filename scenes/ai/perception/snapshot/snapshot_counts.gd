class_name SnapshotCounts extends RefCounted
## AI PERCEPTION sub-domain — SNAPSHOT COUNTS. How many times each lazy build of `SnapshotDemand`
## has run since the process began, by name: the groups (`leads`, `entries`, `search_rooms`,
## `explore`, `interactions`, `rooms`, `grenade_throws`), a hostile's throws (`target_throws`) and
## the facts' two searches (`lead_outside`, `grenade_ready`: a search begun, one-shot or stepped).
## A plain running total, read by a perf probe (`tests/_perf/frame_report.gd`) to name what a frame
## spent its time on; it changes nothing a decision does.

## Build name -> how many times it has run.
static var built: Dictionary = {}


## Count one build of `name`.
static func note(name: String) -> void:
	built[name] = int(built.get(name, 0)) + 1
