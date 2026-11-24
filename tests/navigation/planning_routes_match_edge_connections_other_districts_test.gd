extends "res://tests/navigation/planning_routes_match_edge_connections_test.gd"
## `navigation/planning_routes_match_edge_connections` on another district: where walls and pieces
## stand comes from the seed.

const OTHER_SEED := 23


func describe() -> Dictionary:
	var d := super.describe()
	d["name"] = "The maps of another district route the same with their edge connections off"
	return d


func _seed() -> int:
	return OTHER_SEED
