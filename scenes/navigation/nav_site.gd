class_name NavSite extends RefCounted
## What a bake of the navigation map is made from beside the footprints measured for it: the house
## whose static colliders are parsed, its rooms (the walkable footprint) and the agent radius. The
## Navigation domain's own (`NavBuilder`'s bakes and `nav_updater.gd`'s re-bakes).

## The house (or layout) node the walls are parsed from; the map lies in its local frame.
var house: Node2D
## The house's rooms, `{ rect, ... }` dicts (world-space `rect`), whose bounds are walkable.
var rooms: Array = []
## The agent radius the bake erodes by, px.
var agent_radius: float = NavBuilder.AGENT_RADIUS
## The walkable footprint (world space) when it is not the rooms' bounds grown by
## `NavBuilder.BOUNDS_PAD`: a district's streets, out to the shells. An empty Rect2 is "from the
## rooms".
var bounds := Rect2()


func _init(
	of_house: Node2D = null,
	of_rooms: Array = [],
	radius: float = NavBuilder.AGENT_RADIUS,
	of_bounds := Rect2(),
) -> void:
	house = of_house
	rooms = of_rooms
	agent_radius = radius
	bounds = of_bounds


## The walkable `bounds` in the house's local frame (what a bake is made in): a rect with no area
## when
## the footprint is from the rooms.
func footprint() -> Rect2:
	return Rect2(bounds.position - house.position, bounds.size)
