extends RefCounted
## AI BEHAVIOUR sub-domain — LOCOMOTION's aim, its part `aim`: points the nav agent at the walk's
## goal. Setting an agent's target asks the navigation server for a path, which scans every polygon
## of the map, so a path per walker per frame is the biggest nav cost of a district match. The
## target is sent again when the goal moved, the agent changed map or `reask_frames` frames have
## passed; in between the path it has stands. A long wait lets a walker that cuts a corner press
## into the wall (`ai/entry/stack_reach_garage_home_garage_exit` at 20 frames) and
## `ai/entry/entry_team_flows_in` pins that the period stays short. One per Locomotion.

## The map the target was last sent on, and the physics frame it was sent on.
var _map := RID()
var _frame := -1000


## Point `agent` at `goal`: send the target when it can change the path (see above), at the latest
## `reask_frames` physics frames after the last send.
func at(agent: NavigationAgent2D, goal: Vector2, reask_frames: int) -> void:
	var map := agent.get_navigation_map()
	var frame := Engine.get_physics_frames()
	if (agent.target_position == goal and map == _map
			and frame - _frame < reask_frames):
		return
	agent.target_position = goal
	_map = map
	_frame = frame
