extends "res://tests/navigation/steering_routes_other_seeds_edge_connections_test.gd"
## `navigation/steering_routes_other_seeds_edge_connections` on seed 6 (measured: shorter by up to
## 55 px; after a character stops on a corner of four tiles, 3 routes of 2401 longer, by up to
## 105 px, where the pass links two obstacle corners that only touch).

const SIX := 6
const SIX_GAIN := 60.0
## Measured: 3 routes, 105 px.
const SIX_LONGER := Vector2(3, 110)


func describe() -> Dictionary:
	var d := super.describe()
	d["name"] = "The steering map routes as well with its edge connections off on seed 6"
	return d


func _seed() -> int:
	return SIX


func _gain_bound() -> float:
	return SIX_GAIN


func _longer_bound() -> Vector2:
	return SIX_LONGER
