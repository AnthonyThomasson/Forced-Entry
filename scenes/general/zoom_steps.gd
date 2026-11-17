class_name ZoomSteps
extends RefCounted
## General domain, camera: the 3D render's zoom in whole steps (`Zoom3dConfig.steps`),
## so a picture pixel is a whole number of screen pixels. The camera controller owns
## one: the wheel moves it a step at a time off the automatic zoom's step, and `snap` turns the
## automatic zoom (the follow's 1, the spectator's fit, a vehicle's zoom-out) into the step shown.
## The automatic step has hysteresis (`Zoom3dConfig.hysteresis`), so an automatic zoom that
## hovers at a boundary (a vehicle's speed, a fit that creeps) does not flip the view between two
## steps.

## How many steps the wheel moved the zoom off the automatic step, and the notches turned that have
## not made a step yet (and when the last one turned, in ms).
var offset := 0
var _rest := 0.0
var _rest_at := 0
## The automatic step held now, an index into the steps; -1 before the first `snap`.
var _held := -1


## `notches` of the wheel (positive zooms in) at `now_ms`: every whole notch is a step; a trackpad's
## fractions gather up to one, and turning back, or a pause of `Zoom3dConfig.notch_idle`
## seconds, drops what was gathered. Kept within the steps there are.
func wheel(notches: float, now_ms: int) -> void:
	var idle := float(now_ms - _rest_at) > Zoom3dConfig.notch_idle * 1000.0
	if signf(notches) != signf(_rest) or idle:
		_rest = 0.0
	_rest_at = now_ms
	_rest += notches
	var whole := int(_rest)  # truncates toward zero
	_rest -= float(whole)
	var last := Zoom3dConfig.steps.size() - 1
	offset = clampi(offset + whole, -last, last)


## The zoom to show for the automatic zoom `automatic`: its step (the nearest, or with `fit` the
## largest not over it, so a framing keeps everyone on the screen; the smallest when it is under all
## of them), then the wheel's steps on it (the wheel's offset is held to the steps there are, so
## turning back from an end is at once a step). The automatic step changes only once `automatic` is
## past the boundary by `Zoom3dConfig.hysteresis` (a fraction of the zoom): the nearest
## step both ways, and a fit only upward, since a fit that falls below its step must show more at
## once, never leave someone off the screen.
func snap(automatic: float, fit: bool) -> float:
	var steps := Zoom3dConfig.steps
	if steps.is_empty():
		return 1.0
	var margin := 1.0 + Zoom3dConfig.hysteresis
	var index := _index_of(steps, automatic, fit)
	if _held >= 0 and _held < steps.size():
		if index > _held:  # rising: only once past the boundary by the margin
			index = maxi(_held, _index_of(steps, automatic / margin, fit))
		elif index < _held and not fit:  # falling: the same, but a fit falls at once
			index = mini(_held, _index_of(steps, automatic * margin, fit))
	_held = index
	offset = clampi(offset, -index, steps.size() - 1 - index)  # no turns saved up past an end
	return steps[index + offset]


## The step for `automatic`: the largest not over it with `fit`, else the nearest.
func _index_of(steps: PackedFloat32Array, automatic: float, fit: bool) -> int:
	var index := 0
	for i in steps.size():
		if fit:
			if steps[i] <= automatic * 1.001:
				index = i
		elif absf(log(automatic / steps[i])) < absf(log(automatic / steps[index])):
			index = i
	return index
