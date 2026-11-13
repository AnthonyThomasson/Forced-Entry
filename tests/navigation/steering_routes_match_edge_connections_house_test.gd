extends "res://tests/navigation/steering_routes_match_edge_connections_test.gd"
## `navigation/steering_routes_match_edge_connections` for a lone house: its steering map is one
## region (no seams), so the pass has nothing to join but what the bake made one polygon of; the
## routes between the middles of its polygons are the same with it off as on.

const HOUSE_SEED := 7
## A polygon in this many is a point to route between.
const EVERY := 4


func describe() -> Dictionary:
	var d := super.describe()
	d["name"] = "A lone house's steering map routes the same with its edge connections off"
	return d


func _world(s: TestSetup) -> void:
	s.house(HOUSE_SEED)


func _stops() -> Array:
	return []


func _stride() -> int:
	return EVERY
