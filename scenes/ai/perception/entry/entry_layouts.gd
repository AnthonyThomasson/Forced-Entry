extends RefCounted
## AI PERCEPTION sub-domain — ENTRY GEOMETRY's layouts, a part the entry geometry holds as
## `layouts`: where the doorways' geometry is kept once laid, its own (`cache`) and the geometry
## every NPC on a navigation map shares (`shared_on`, filed under `key`), and what
## `AgentEntry.warm_geometry` last found laid. The shared geometry and the frame it was last warmed
## in are static: one for every `AgentEntry`. Built once by `AgentEntry`, it holds nothing of it:
## the geometry is handed in at the call (`entry`), so no reference cycle forms.

## The entry geometry this part is one of, handed in at the call (never held: it holds the part).
const AgentEntry := preload("res://scenes/ai/perception/agent_entry.gd")

## The geometry every NPC on a navigation map shares (map RID -> "<house and tuning>|<opening
## id>><room key>" -> geometry): it is the house's and the map's, not the NPC's, and laying a
## doorway's slots is costly (`EntrySlots.lay`), so it is laid once per map, not once per NPC.
## Forgotten with the map's planning region.
static var _shared := {}
## The physics frame `warm_geometry` last laid a doorway in (one a frame, among every NPC).
static var warmed_frame := -1

## "<opening id>><room key>" -> the geometry of that entry.
var cache := {}
## The shared geometry (`shared_on`) in which `warm_geometry` last found every way in laid...
var warm_done_in := {}
## ... for these `tuning_inputs` (the house and the tunables): nothing to look for until either
## changes.
var warm_done_for: Array = []


## The geometry shared on `map` (`_shared`), made the first time it is asked for and dropped when
## the map's planning region leaves the tree; a map with no planning region shares nothing (an empty
## dictionary each time).
func shared_on(map: RID) -> Dictionary:
	if _shared.has(map):
		return _shared[map]
	var region := NavBuilder.planning_region(map)
	if region == null:
		return {}
	_shared[map] = {}
	region.tree_exited.connect(func() -> void: _shared.erase(map), CONNECT_ONE_SHOT)
	return _shared[map]


## What a doorway's geometry is laid from besides the map: the house and the tunables
## `AgentEntry._build` reads (the stack's spacing and standoff, the pie, the corners, the short
## room, the view's depth, and the sight that tells a hard corner). Cheap to make and compare, so
## `warm_geometry` checks it every pass; `key` is the same as the key the shared geometry is filed
## under.
func tuning_inputs(entry: AgentEntry) -> Array:
	var out: Array = [
		entry._house, entry.stack_spacing, entry.wall_standoff, entry.pie_radius, entry.pie_steps,
		entry.corner_inset, entry.short_room, entry.views.door_view_depth,
	]
	out.append_array([
		entry.vision.enabled, entry.vision.view_distance, entry.vision.fov_degrees,
		entry.vision.awareness_radius, entry.vision.see_over_coverage,
	])
	return out


## `tuning_inputs` as the shared geometry's key prefix.
func key(entry: AgentEntry) -> String:
	return str(tuning_inputs(entry))
