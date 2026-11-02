extends RefCounted
## AI BEHAVIOUR sub-domain — LOCOMOTION's aim, its part `aim`: points the nav agent at the walk's
## goal. Setting an agent's target asks the navigation server for a path (the agent computes it when
## it is next read), and the server scans every polygon of the map to place the path's two ends, so
## on a district's map (ten times a house's polygons) a path per walker per frame is the biggest nav
## cost of a match. The target is sent again when the goal moved, the agent changed map or
## `tuning.pace.reask_frames` frames have passed (a re-baked map or a body off its path is met
## within that); in between the path it has stands. Built once with its Locomotion, it holds it (a
## node, so no reference cycle) for the tuning.
##
## A period is the model, not an event: the agent moves on to the next waypoint once the body is
## within `path_desired_distance` of it, so a path that stands takes a corner as a cut, and one
## asked from the body keeps the corner until the straight line from where it stands clears it.
## Nothing tells the walk when it is cutting a corner too close, and a long wait lets it press into
## the wall for a second (`ai/entry/stack_reach_garage_home_garage_exit` at 20 frames), so the
## period is short; the walk's timing is what the entry tests are sensitive to, and
## `ai/entry/entry_team_flows_in` pins that it stays.

## The Locomotion it belongs to.
var loco: Node
## The map the target was last sent on, and the physics frame it was sent on.
var _map := RID()
var _frame := -1000


func _init(locomotion: Node) -> void:
	loco = locomotion


## Point `agent` at `goal`: send the target when it can change the path (see above).
func at(agent: NavigationAgent2D, goal: Vector2) -> void:
	var map := agent.get_navigation_map()
	var frame := Engine.get_physics_frames()
	if (agent.target_position == goal and map == _map
			and frame - _frame < loco.tuning.pace.reask_frames):
		return
	agent.target_position = goal
	_map = map
	_frame = frame
