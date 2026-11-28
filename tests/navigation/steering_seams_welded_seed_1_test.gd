extends "res://tests/navigation/steering_seams_welded_test.gd"
## `navigation/steering_seams_welded` as built on district seed 1 (the sweep of seeds that
## nothing needs a seam cut in one line with its corners, or more rounds than `NavSeams` has).

const SWEEP_SEED := 1


func describe() -> Dictionary:
	var d := super.describe()
	d["name"] = "Every border between two steering tiles of district seed 1 is welded"
	d["timeout"] = 30.0
	return d


func _seed() -> int:
	return SWEEP_SEED


func _stops() -> Array:
	return []
