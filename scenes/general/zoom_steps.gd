class_name ZoomSteps
extends RefCounted
## General domain, camera: the 3D render's zoom in whole steps (`CameraConfig.zoom_steps_3d`, #193
## phase 2b G15), so a picture pixel is a whole number of screen pixels. The camera controller owns
## one: the wheel moves it a step at a time off the automatic zoom's step, and `snap` turns the
## automatic zoom (the follow's 1, the spectator's fit, a vehicle's zoom-out) into the step shown.

## How many steps the wheel moved the zoom off the automatic step, and the notches turned that have
## not made a step yet.
var offset := 0
var _rest := 0.0


## `notches` of the wheel (positive zooms in): every whole notch is a step; a trackpad's fractions
## gather up to one, and turning back drops what was gathered. Kept within the steps there are.
func wheel(notches: float) -> void:
	if signf(notches) != signf(_rest):
		_rest = 0.0
	_rest += notches
	var whole := int(_rest)  # truncates toward zero
	_rest -= float(whole)
	var last := CameraConfig.zoom_steps_3d.size() - 1
	offset = clampi(offset + whole, -last, last)


## The zoom to show for the automatic zoom `automatic`: its step (the nearest, or with `fit` the
## largest not over it, so a framing keeps everyone on the screen; the smallest when it is under all
## of them), then the wheel's steps on it (the wheel's offset is held to the steps there are, so
## turning back from an end is at once a step).
func snap(automatic: float, fit: bool) -> float:
	var steps := CameraConfig.zoom_steps_3d
	if steps.is_empty():
		return 1.0
	var index := 0
	for i in steps.size():
		if fit:
			if steps[i] <= automatic * 1.001:
				index = i
		elif absf(log(automatic / steps[i])) < absf(log(automatic / steps[index])):
			index = i
	offset = clampi(offset, -index, steps.size() - 1 - index)  # no turns saved up past an end
	return steps[index + offset]
