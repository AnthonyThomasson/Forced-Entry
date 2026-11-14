extends "res://tests/vision/cone_skip_exact_test.gd"
## `vision/cone_skip_exact` with the cone's job cut into slices of `SLICED_UNITS` (a job of the
## houses of that test takes a few frames): every change it makes to the world falls between the
## slices of some job or other, and every cone the view publishes is still the reference cone of
## the pose it is of, held whole until the next, and no wait between two job starts goes past the
## backstop. What a slice changes is how many frames a cone takes, so the turning viewer's floors
## are of a cone every fourth frame (`_turn_floor`).

## The slice (units): a job takes about three frames.
const SLICED_UNITS := 140


func describe() -> Dictionary:
	var d := super.describe()
	d["name"] = "A cone built in slices is the reference cone of its pose through every change"
	d["description"] = (
		"The same changes as `vision/cone_skip_exact` (dents, a shove, a piece freed and added, "
		+ "doors, a posture and a death, solids arriving in reach) with the cone's job cut into "
		+ "slices: every published cone is the reference cone of its pose."
	)
	return d


func configure(s: TestSetup) -> void:
	super.configure(s)
	s.set_static(VisionSliceConfig, &"slice_units", SLICED_UNITS)
	s.set_static(VisionSliceConfig, &"cost_shape", SLICED_UNITS)


## A cycle of a job is about four frames here, so about 22 of the turning viewer's 90 frames.
func _turn_floor() -> int:
	return 20
