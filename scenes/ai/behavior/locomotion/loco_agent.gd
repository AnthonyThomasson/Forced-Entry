extends RefCounted
## AI BEHAVIOUR sub-domain — LOCOMOTION's agent, its part `agent` (D4): the walk's
## `NavigationAgent3D` in plan terms. The nav is 3D (a plan point is the point (x, 0, y) of its
## floor, `NavPlan`), and this is the walk's seam where the agent's `Vector3`s become plan
## `Vector2`s and back: every consumer of a walk (`aim`, `give_way`, `leaves`) asks it what a
## `NavigationAgent2D` was asked, by the same names. (The debug overlay, `agent_debug.gd`, and a few
## tests read the raw `NavigationAgent3D`, which they only look at.)
##
## The agent needs a `Node3D` parent for its position: the `NavAnchor` of `npc.tscn`, a `Node3D`
## child of the NPC with no collider, never mirrored and owned by Locomotion (`domain-character`).
## It is put at (x, 0, y) of the NPC before every ask that reads it (`_sync`): a walk's position is
## the character's plan position and nothing else. The agent does not avoid (the AI's own give-way
## does), so only its path is used.

## The agent's `NavigationAgent3D`.
var agent: NavigationAgent3D
## The walk's destination, a plan point.
var target_position: Vector2:
	get:
		return NavPlan.plan_of(agent.target_position)
	set(value):
		_sync()
		agent.target_position = NavPlan.lift(value)
## How close (px) to the destination counts as arrived.
var target_desired_distance: float:
	get:
		return agent.target_desired_distance
	set(value):
		agent.target_desired_distance = value
## The anchor the agent rides, and the NPC's plan handle it is kept at.
var _anchor: Node3D
var _body: Node2D


## Wrap `node`, an agent whose parent is the `NavAnchor` (a `Node3D`) of an NPC (a plan handle).
func _init(node: NavigationAgent3D) -> void:
	agent = node
	_anchor = node.get_parent() as Node3D
	_body = _anchor.get_parent() as Node2D


## The NPC the agent walks for (its plan handle).
func body() -> Node2D:
	return _body


## The map the agent paths on.
func get_navigation_map() -> RID:
	return agent.get_navigation_map()


## Put the agent on `map`.
func set_navigation_map(map: RID) -> void:
	agent.set_navigation_map(map)


## The next waypoint of the walk, a plan point (advances the agent's path index).
func get_next_path_position() -> Vector2:
	_sync()
	return NavPlan.plan_of(agent.get_next_path_position())


## The walk's waypoints, plan points.
func get_current_navigation_path() -> PackedVector2Array:
	return NavPlan.plan_path(agent.get_current_navigation_path())


## The waypoint the walk is heading for, an index of `get_current_navigation_path`.
func get_current_navigation_path_index() -> int:
	return agent.get_current_navigation_path_index()


## Whether the walk has arrived (or has no path).
func is_navigation_finished() -> bool:
	_sync()
	return agent.is_navigation_finished()


## Whether the destination is on the map's navmesh as far as the path goes.
func is_target_reachable() -> bool:
	_sync()
	return agent.is_target_reachable()


## Keep the anchor at the NPC's plan point (x, 0, y).
func _sync() -> void:
	var at := NavPlan.lift(_body.global_position)
	if _anchor.position != at:
		_anchor.position = at
