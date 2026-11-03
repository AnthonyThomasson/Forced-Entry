class_name DistrictKeepouts
extends RefCounted
## World Generation domain: what a district's street furniture keeps clear of, world space: the
## doorway zones of every tower, the crossings and their landings, every tower's body and the
## lamps' posts. The lamps (`DistrictStreets.lamps`) obey the first two, the sidewalk clutter all
## four and the clutter placed before it (`DistrictStreets.clutter`).

## The door rule's zones of every tower (`StreetLamps.door_zones`).
var zones: Array = []
## The rects of the crossings and the sidewalk at both ends of each (`DistrictLayout`'s `landings`).
var landings: Array[Rect2] = []
## Every tower's body: its rooms grown by the podium band and the margin.
var bodies: Array[Rect2] = []
## The lamps' posts, once placed.
var posts: Array[Rect2] = []


## Whether clutter on `rect` keeps clear of every doorway zone (its strip and
## `WorldGenDistrictConfig.clutter_door_clear` of its centre), landing, tower body and lamp post.
func clear(rect: Rect2) -> bool:
	for zone: Dictionary in zones:
		var p: Vector2 = zone["pos"]
		if (rect.intersects(zone["strip"])
				or p.distance_to(p.clamp(rect.position, rect.end))
				< WorldGenDistrictConfig.clutter_door_clear):
			return false
	for group: Array[Rect2] in [landings, bodies, posts]:
		for blocked: Rect2 in group:
			if rect.intersects(blocked):
				return false
	return true
