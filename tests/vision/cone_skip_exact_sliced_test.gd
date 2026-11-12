extends "res://tests/vision/cone_skip_exact_test.gd"
## `vision/cone_skip_exact` with the cone's job cut into slices of `SLICED_UNITS` (a job of the
## houses of that test takes a few frames): every change it makes to the world falls between the
## slices of some job or other, and every cone the view publishes is still the reference cone of
## the pose it is of, held whole until the next, and no wait between two job starts goes past the
## backstop. What a slice changes is how many frames a cone takes, so the counts that said "each
## frame" say "each job" (`_per_job`).

## The slice (units): a job takes about three frames.
const SLICED_UNITS := 90


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


## Three frames a cone, so a turning viewer is published a third as often.
func _per_job(frames: int) -> int:
	return int(float(frames) / 4.0)
