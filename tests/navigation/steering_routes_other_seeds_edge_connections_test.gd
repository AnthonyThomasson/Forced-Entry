extends "res://tests/navigation/steering_routes_match_edge_connections_test.gd"
## `navigation/steering_routes_match_edge_connections` on seeds where the pass joins more than the
## welded tiles do (a free edge touching another tile's at a wall corner on a border: a second,
## point-like link): the routes differ, but with the pass off at most `_longer_bound` routes are
## longer, every destination
## the pass reaches is reached, and none is shorter by more than `GAIN` px (measured: seed 24
## 224 px, a route in about fourteen; the bound is a little over it). A change that makes a route
## longer (beyond the pinch of `_longer_bound`) or a destination unreachable fails this.

const OTHER_SEED := 24
const GAIN := 240.0


func describe() -> Dictionary:
	var d := super.describe()
	d["name"] = "The steering map routes as well with its edge connections off on seed 24"
	d["description"] = (
		"Every route between the tiles' probe points and across every seam is as short or "
		+ "shorter with the pass off, and found whenever the pass finds it."
	)
	return d


func _seed() -> int:
	return OTHER_SEED


func _gain_bound() -> float:
	return GAIN
