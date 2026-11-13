extends "res://tests/navigation/steering_routes_match_edge_connections_test.gd"
## `navigation/steering_routes_match_edge_connections` on another district: where walls and pieces
## meet a border comes from the seed.

const OTHER_SEED := 23


func describe() -> Dictionary:
	var d := super.describe()
	d["name"] = "The steering map of another district routes the same with its edge connections off"
	return d


func _seed() -> int:
	return OTHER_SEED
