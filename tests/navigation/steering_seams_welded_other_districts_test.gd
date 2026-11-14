extends "res://tests/navigation/steering_seams_welded_test.gd"
## `navigation/steering_seams_welded` on another district: the layout (and so where walls and
## pieces meet a border) comes from the seed.

const OTHER_SEED := 23


func describe() -> Dictionary:
	var d := super.describe()
	d["name"] = "Every border between two steering tiles of another district is welded"
	return d


func _seed() -> int:
	return OTHER_SEED
